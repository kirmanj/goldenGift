import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/core/utils/firestore_parse.dart';
import 'package:golden_gift/core/utils/promo_rules.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/promo_code_model.dart';

import '../../../core/data/audit_log.dart';
import '../../../core/session/admin_session.dart';

/// Who may use the Promo codes module (SRS §9): content, ops and super admins
/// edit; finance reads (incl. the usage report); sellers never see it.
class PromoAccess {
  PromoAccess._();

  static bool canView(AdminRole r) => r != AdminRole.seller;
  static bool canEdit(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops || r == AdminRole.content;
}

enum PromoStatus {
  live('Live'),
  inactive('Inactive'),
  usedUp('Used up'),
  expired('Expired');

  const PromoStatus(this.label);
  final String label;
}

/// Same precedence as [PromoRules.evaluate]: inactive, then expired, then the
/// total usage limit.
PromoStatus promoStatus(PromoCodeModel p, DateTime now) {
  if (!p.isActive || p.value <= 0) return PromoStatus.inactive;
  if (p.expiresAt != null && !now.isBefore(p.expiresAt!)) return PromoStatus.expired;
  if (p.usageLimit != null && p.usageCount >= p.usageLimit!) return PromoStatus.usedUp;
  return PromoStatus.live;
}

/// "10% (max 5,000 IQD)" / "5,000 IQD off".
String promoDiscountLabel(PromoCodeModel p) => switch (p.type) {
      PromoType.percent =>
        '${p.value}%${p.maxDiscount != null && p.maxDiscount! > 0 ? ' (max ${CurrencyFormatter.format(p.maxDiscount!)})' : ''}',
      PromoType.fixed => '${CurrencyFormatter.format(p.value)} off',
    };

String promoUsesLabel(PromoCodeModel p) => '${p.usageCount} / ${p.usageLimit ?? '∞'}';

String promoRejectionLabel(PromoRejection r, PromoCodeModel p) => switch (r) {
      PromoRejection.notFound => 'Code not found',
      PromoRejection.inactive => 'Inactive — customers cannot use it',
      PromoRejection.expired => 'Expired',
      PromoRejection.minOrder => 'Below the minimum order of ${CurrencyFormatter.format(p.minOrder ?? 0)}',
      PromoRejection.usageLimit => 'Usage limit reached',
      PromoRejection.perUserLimit => 'This customer has used it the maximum number of times',
      PromoRejection.firstOrderOnly => 'First order only — this customer has ordered before',
      PromoRejection.notApplicable => 'No cart line matches the category / store restriction',
    };

/// Upper-case letters, digits and dashes (the doc id — SRS §6.9).
final promoCodePattern = RegExp(r'^[A-Z0-9-]{3,20}$');

/// Fixed discounts below this are not worth a code (and smaller than any product).
const minFixedDiscount = 250;
const maxPromoAmount = 100000000;

String? validatePromoCode(String? raw, {Iterable<String> taken = const []}) {
  final code = PromoCodeModel.normalize(raw ?? '');
  if (code.isEmpty) return 'Required';
  if (!promoCodePattern.hasMatch(code)) return '3–20 characters: letters A–Z, digits and dashes';
  if (taken.contains(code)) return 'The code $code already exists';
  return null;
}

/// Every rule a promo code must pass before it is written (SRS §5.23, §6.9).
List<String> validatePromo(PromoCodeModel p, {required bool isNew, required DateTime now, Iterable<String> takenCodes = const []}) {
  final errors = <String>[];
  if (isNew) {
    final codeError = validatePromoCode(p.code, taken: takenCodes);
    if (codeError != null) errors.add('Code: $codeError');
  }
  if (p.title.en.trim().isEmpty) errors.add('English title is required');
  switch (p.type) {
    case PromoType.percent:
      if (p.value < 1 || p.value > 100) errors.add('A percent discount must be between 1 and 100');
      if (p.maxDiscount != null && p.maxDiscount! <= 0) errors.add('Max discount must be more than 0 (or empty for no cap)');
    case PromoType.fixed:
      if (p.value < minFixedDiscount) errors.add('A fixed discount must be at least ${CurrencyFormatter.format(minFixedDiscount)}');
      if (p.value > maxPromoAmount) errors.add('A fixed discount must be at most ${CurrencyFormatter.format(maxPromoAmount)}');
      if (p.maxDiscount != null) errors.add('Max discount only applies to percent codes');
  }
  if (p.minOrder != null && p.minOrder! < 0) errors.add('Minimum order cannot be negative');
  if (p.usageLimit != null && p.usageLimit! < 1) errors.add('Usage limit must be at least 1 (leave it empty for unlimited)');
  if (p.perUserLimit < 0) errors.add('Per-customer limit cannot be negative (0 = unlimited)');
  if (p.expiresAt == null) {
    errors.add('Pick an expiry date and time');
  } else if (isNew && !p.expiresAt!.isAfter(now)) {
    errors.add('The expiry must be in the future');
  }
  return errors;
}

class PromoValidationException implements Exception {
  const PromoValidationException(this.errors);
  final List<String> errors;
  @override
  String toString() => errors.join('\n');
}

class PromoCodeTakenException implements Exception {
  const PromoCodeTakenException(this.code);
  final String code;
  @override
  String toString() => 'The code $code already exists.';
}

/// A used code keeps its orders' history; deactivate it instead.
class PromoInUseException implements Exception {
  const PromoInUseException(this.usageCount);
  final int usageCount;
  @override
  String toString() => 'This code has been used $usageCount time(s) — deactivate it instead of deleting it.';
}

/// Every promo code, live ones first, then by code.
final adminPromoCodesProvider = StreamProvider.autoDispose<List<PromoCodeModel>>((ref) => ref
    .watch(firestoreProvider)
    .collection(FirestorePaths.promoCodes)
    .snapshots()
    .map((s) => sortPromos([for (final d in s.docs) PromoCodeModel.fromMap(d.id, d.data())], DateTime.now())));

List<PromoCodeModel> sortPromos(List<PromoCodeModel> list, DateTime now) => [...list]
  ..sort((a, b) {
    final byStatus = promoStatus(a, now).index.compareTo(promoStatus(b, now).index);
    return byStatus != 0 ? byStatus : a.code.compareTo(b.code);
  });

final promoAdminRepositoryProvider = Provider.autoDispose<PromoAdminRepository>(
    (ref) => PromoAdminRepository(ref.watch(firestoreProvider), adminUid: ref.watch(adminSessionProvider)?.uid ?? ''));

/// Promo code writes. Each call is ONE batch carrying the change and its
/// `admin_audit_log` entry. `usageCount` / `usages` belong to `placeOrder`:
/// set to 0 on create and never written again here.
class PromoAdminRepository {
  PromoAdminRepository(this.db, {required this.adminUid});
  final FirebaseFirestore db;
  final String adminUid;

  static const usageReportLimit = 100;

  DocumentReference<Map<String, dynamic>> doc(String code) => db.doc('${FirestorePaths.promoCodes}/$code');

  void _requireAdmin() {
    if (adminUid.isEmpty) throw StateError('Not signed in as an admin.');
  }

  Future<void> create(PromoCodeModel promo, {DateTime? now, Iterable<String> takenCodes = const []}) async {
    _requireAdmin();
    final errors = validatePromo(promo, isNew: true, now: now ?? DateTime.now(), takenCodes: takenCodes);
    if (errors.isNotEmpty) throw PromoValidationException(errors);
    final ref = doc(promo.code);
    if ((await ref.get()).exists) throw PromoCodeTakenException(promo.code);
    final data = {
      ...promo.toMap(),
      'usageCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = db.batch()..set(ref, data);
    AuditLog.add(batch, db, adminUid: adminUid, action: 'promo.create', target: ref.path, after: data);
    await batch.commit();
  }

  /// Everything but the code (the doc id) and the usage counter. Cleared
  /// translations are deleted.
  Future<void> update(PromoCodeModel before, PromoCodeModel after, {DateTime? now}) async {
    _requireAdmin();
    if (before.code != after.code) throw ArgumentError('A promo code cannot be renamed.');
    final errors = validatePromo(after, isNew: false, now: now ?? DateTime.now());
    if (errors.isNotEmpty) throw PromoValidationException(errors);
    final ref = doc(after.code);
    final data = <String, dynamic>{...after.toMap(), 'updatedAt': FieldValue.serverTimestamp()}..remove('usageCount');
    for (final key in const ['titleAr', 'titleKu', 'descriptionAr', 'descriptionKu']) {
      data.putIfAbsent(key, FieldValue.delete);
    }
    final batch = db.batch()..update(ref, data);
    AuditLog.add(batch, db,
        adminUid: adminUid, action: 'promo.update', target: ref.path, before: before.toMap(), after: after.toMap());
    await batch.commit();
  }

  Future<void> setActive(PromoCodeModel promo, bool active) async {
    _requireAdmin();
    final ref = doc(promo.code);
    final batch = db.batch()..update(ref, {'isActive': active, 'updatedAt': FieldValue.serverTimestamp()});
    AuditLog.add(batch, db,
        adminUid: adminUid,
        action: 'promo.toggle',
        target: ref.path,
        before: {'isActive': promo.isActive},
        after: {'isActive': active});
    await batch.commit();
  }

  /// Only an unused code can be deleted (checked against the stored counter,
  /// not the possibly stale list).
  Future<void> delete(PromoCodeModel promo) async {
    _requireAdmin();
    final ref = doc(promo.code);
    final snap = await ref.get();
    final used = FirestoreParse.integer(snap.data()?['usageCount'], promo.usageCount);
    if (used > 0) throw PromoInUseException(used);
    final batch = db.batch()..delete(ref);
    AuditLog.add(batch, db,
        adminUid: adminUid, action: 'promo.delete', target: ref.path, before: {...promo.toMap(), 'usageCount': used});
    await batch.commit();
  }

  /// Orders that used [code], newest first. Index: orders (promoCode ASC, createdAt DESC).
  Stream<List<OrderModel>> watchUsage(String code, {int limit = usageReportLimit}) => db
      .collection(FirestorePaths.orders)
      .where('promoCode', isEqualTo: code)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) OrderModel.fromMap(d.id, d.data())]);
}

final promoUsageProvider = StreamProvider.autoDispose
    .family<List<OrderModel>, String>((ref, code) => ref.watch(promoAdminRepositoryProvider).watchUsage(code));

/// Orders that don't count towards the report totals.
const _notCounted = {
  OrderStatus.cancelledByBuyer,
  OrderStatus.cancelledBySeller,
  OrderStatus.returned,
  OrderStatus.refunded,
};

/// Totals of the usage report. Cancelled / returned / refunded orders are
/// listed but excluded from the discount and revenue sums.
class PromoUsageTotals {
  const PromoUsageTotals({required this.orders, required this.counted, required this.discount, required this.revenue});
  final int orders;
  final int counted;
  final int discount;

  /// Sum of the counted orders' `total`.
  final int revenue;

  int get excluded => orders - counted;

  factory PromoUsageTotals.of(List<OrderModel> orders) {
    final counted = orders.where((o) => !_notCounted.contains(o.status)).toList();
    return PromoUsageTotals(
      orders: orders.length,
      counted: counted.length,
      discount: counted.fold(0, (s, o) => s + o.discount),
      revenue: counted.fold(0, (s, o) => s + o.total),
    );
  }
}
