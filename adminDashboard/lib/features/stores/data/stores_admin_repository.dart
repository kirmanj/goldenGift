import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/services/callable.dart';
import 'package:golden_gift/core/utils/firestore_parse.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/store_model.dart';

import '../../../core/data/audit_log.dart';
import '../../../core/session/admin_session.dart';
import 'callable_errors.dart';
import 'phone_input.dart';

/// Who may do what in Stores / Partners (SRS §9). Reviewing and suspending
/// are the `reviewPartner` / `setStoreStatus` callables (super | ops).
class StoresAccess {
  StoresAccess._();

  static bool canView(AdminRole r) => r != AdminRole.seller;
  static bool canReview(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops;
  static bool canEditProfile(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops;
}

/// `stores/{id}` plus the fields the shared model doesn't carry.
class StoreRecord {
  const StoreRecord({required this.store, this.createdAt});
  final StoreModel store;
  final DateTime? createdAt;

  factory StoreRecord.fromMap(String id, Map<String, dynamic> map) =>
      StoreRecord(store: StoreModel.fromMap(id, map), createdAt: FirestoreParse.date(map['createdAt']));
}

/// `stores/{id}/private/application` — what the partner sent from "Sell on
/// Golden Gift" (SRS §5.25; written by `submitPartnerApplication`).
class StoreApplication {
  const StoreApplication({
    this.storeName = '',
    this.ownerName = '',
    this.phone = '',
    this.city = '',
    this.category = '',
    this.instagram,
    this.samplePhotos = const [],
    this.submittedAt,
  });

  final String storeName;
  final String ownerName;
  final String phone;
  final String city;
  final String category;
  final String? instagram;
  final List<String> samplePhotos;
  final DateTime? submittedAt;

  factory StoreApplication.fromMap(Map<String, dynamic> map) => StoreApplication(
        storeName: map['storeName'] as String? ?? '',
        ownerName: map['ownerName'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        city: map['city'] as String? ?? '',
        category: map['category'] as String? ?? '',
        instagram: FirestoreParse.stringOrNull(map['instagram']),
        samplePhotos: FirestoreParse.stringList(map['samplePhotos']),
        submittedAt: FirestoreParse.date(map['submittedAt'] ?? map['createdAt']),
      );
}

/// The editable part of a store profile. Admins also set the commission;
/// sellers (Store profile page) never send it.
class StoreProfileUpdate {
  const StoreProfileUpdate({
    required this.name,
    this.description = LocalizedText.empty,
    this.logoUrl,
    this.coverUrl,
    this.phone,
    this.city,
    this.commissionPercent,
  });

  final LocalizedText name;
  final LocalizedText description;
  final String? logoUrl;
  final String? coverUrl;
  final String? phone;
  final String? city;

  /// null = unchanged (seller edits).
  final double? commissionPercent;

  static const nameMax = 60;
  static const descriptionMax = 1000;

  factory StoreProfileUpdate.of(StoreModel s, {bool withCommission = true}) => StoreProfileUpdate(
        name: s.name,
        description: s.description,
        logoUrl: s.logoUrl,
        coverUrl: s.coverUrl,
        phone: s.phone,
        city: s.city,
        commissionPercent: withCommission ? s.commissionPercent : null,
      );

  List<String> validate() {
    final errors = <String>[];
    if (name.en.trim().isEmpty) errors.add('English store name is required.');
    if ([name.en, name.ar ?? '', name.ku ?? ''].any((v) => v.trim().length > nameMax)) {
      errors.add('Keep the store name under $nameMax characters.');
    }
    if ([description.en, description.ar ?? '', description.ku ?? ''].any((v) => v.trim().length > descriptionMax)) {
      errors.add('Keep the description under $descriptionMax characters.');
    }
    if ((phone ?? '').trim().isNotEmpty && normalizeStaffPhone(phone!) == null) errors.add('The phone number is not valid.');
    final c = commissionPercent;
    if (c != null) {
      final e = validateCommission(c);
      if (e != null) errors.add(e);
    }
    return errors;
  }

  /// The Firestore update (cleared translations are deleted).
  Map<String, dynamic> changes() {
    String? opt(String? v) => (v?.trim().isEmpty ?? true) ? null : v!.trim();
    final phoneValue = opt(phone);
    return {
      'name': name.en.trim(),
      'nameAr': opt(name.ar) ?? FieldValue.delete(),
      'nameKu': opt(name.ku) ?? FieldValue.delete(),
      'description': description.en.trim(),
      'descriptionAr': opt(description.ar) ?? FieldValue.delete(),
      'descriptionKu': opt(description.ku) ?? FieldValue.delete(),
      'logoUrl': opt(logoUrl),
      'coverUrl': opt(coverUrl),
      'phone': phoneValue == null ? null : normalizeStaffPhone(phoneValue),
      'city': opt(city),
      if (commissionPercent != null) 'commissionPercent': commissionPercent,
    };
  }
}

/// SRS §12 item 5 (partner commission) — provisional default, owner to confirm.
const defaultCommissionPercent = 15.0;
const maxCommissionPercent = 50.0;

String? validateCommission(double? value) {
  if (value == null) return 'Enter the commission (0–${maxCommissionPercent.toStringAsFixed(0)} %).';
  if (value.isNaN || value < 0 || value > maxCommissionPercent) {
    return 'Commission must be between 0 and ${maxCommissionPercent.toStringAsFixed(0)} %.';
  }
  return null;
}

/// Reasons go to the partner (reject) or the audit trail (suspend / reactivate).
String? validateReason(String? value, {int min = 3, int max = 500}) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'A reason is required.';
  if (v.length < min) return 'Give a reason of at least $min characters.';
  if (v.length > max) return 'Keep the reason under $max characters.';
  return null;
}

String commissionLabel(double pct) =>
    pct == pct.roundToDouble() ? '${pct.toStringAsFixed(0)} %' : '${pct.toStringAsFixed(1)} %';

String storeStatusLabel(StoreStatus s) => switch (s) {
      StoreStatus.pendingApproval => 'Pending approval',
      StoreStatus.active => 'Active',
      StoreStatus.suspended => 'Suspended',
    };

/// Order lines that count as sales (cancelled / returned / refunded don't).
const closedLineStatuses = {
  OrderStatus.cancelledByBuyer,
  OrderStatus.cancelledBySeller,
  OrderStatus.returned,
  OrderStatus.refunded,
};

/// The lines of [order] that belong to [storeId] (multi-vendor, SRS §6.7).
List<OrderItem> storeLines(OrderModel order, String storeId) =>
    [for (final i in order.items) if (i.line.storeId == storeId) i];

/// Σ lineTotal of [storeId]'s lines that are still sales.
int storeSalesTotal(OrderModel order, String storeId) => storeLines(order, storeId)
    .where((i) => !closedLineStatuses.contains(i.status))
    .fold(0, (total, i) => total + i.line.lineTotal);

/// "Sales" card of a store: only that store's lines count (other partners'
/// items in the same order are ignored); commission due is an estimate.
class StoreSales {
  const StoreSales({required this.orderCount, required this.itemCount, required this.total, required this.commissionPercent});

  final int orderCount;
  final int itemCount;
  final int total;
  final double commissionPercent;

  int get commissionDue => (total * commissionPercent / 100).round();

  factory StoreSales.of(List<OrderModel> orders, String storeId, double commissionPercent) {
    var count = 0, items = 0, total = 0;
    for (final o in orders) {
      final lines = storeLines(o, storeId);
      if (lines.isEmpty) continue;
      count++;
      for (final l in lines) {
        if (closedLineStatuses.contains(l.status)) continue;
        items += l.line.qty;
        total += l.line.lineTotal;
      }
    }
    return StoreSales(orderCount: count, itemCount: items, total: total, commissionPercent: commissionPercent);
  }
}

class StoreNotFoundException implements Exception {
  const StoreNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'Store "$id" no longer exists.';
}

class StoresAdminRepository {
  StoresAdminRepository(this._db, this._call);
  final FirebaseFirestore _db;
  final CallableInvoker _call;

  static const salesOrders = 50;

  Stream<List<StoreRecord>> watchByStatus(StoreStatus status) => _db
      .collection(FirestorePaths.stores)
      .where('status', isEqualTo: status.name)
      .snapshots()
      .map((s) => sortStores([for (final d in s.docs) StoreRecord.fromMap(d.id, d.data())], status));

  /// Pending applications oldest first (review in order); others by name.
  static List<StoreRecord> sortStores(List<StoreRecord> list, StoreStatus status) => [...list]
    ..sort((a, b) {
      if (status == StoreStatus.pendingApproval) {
        final at = a.createdAt, bt = b.createdAt;
        if (at != null && bt != null && at != bt) return at.compareTo(bt);
      }
      return a.store.name.en.toLowerCase().compareTo(b.store.name.en.toLowerCase());
    });

  Stream<StoreRecord?> watchStore(String id) => _db
      .doc(FirestorePaths.storeDoc(id))
      .snapshots()
      .map((d) => d.exists ? StoreRecord.fromMap(d.id, d.data()!) : null);

  Stream<StoreApplication?> watchApplication(String id) => _db
      .doc(FirestorePaths.storeApplication(id))
      .snapshots()
      .map((d) => d.exists ? StoreApplication.fromMap(d.data()!) : null);

  /// Newest orders containing the store (index `storeIds` CONTAINS + `createdAt`).
  Stream<List<OrderModel>> watchStoreOrders(String id, {int limit = salesOrders}) => _db
      .collection(FirestorePaths.orders)
      .where('storeIds', arrayContains: id)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) OrderModel.fromMap(d.id, d.data())]);

  /// Profile edit by an admin (with commission) or the store's seller
  /// (without): one batch with the `store.update` audit entry.
  Future<void> updateProfile(StoreModel before, StoreProfileUpdate update, {required String actorUid}) async {
    if (actorUid.isEmpty) throw StateError('Not signed in.');
    final errors = update.validate();
    if (errors.isNotEmpty) throw ArgumentError(errors.join('\n'));
    final ref = _db.doc(FirestorePaths.storeDoc(before.id));
    if (!(await ref.get()).exists) throw StoreNotFoundException(before.id);
    final changes = update.changes();
    final batch = _db.batch()..update(ref, {...changes, 'updatedAt': FieldValue.serverTimestamp()});
    final beforeMap = before.toMap();
    AuditLog.add(batch, _db,
        adminUid: actorUid,
        action: 'store.update',
        target: ref.path,
        before: {for (final k in changes.keys) if (beforeMap.containsKey(k)) k: beforeMap[k]},
        after: changes);
    await batch.commit();
  }

  /// `reviewPartner` approve: store active + commission, seller claim, admins doc, notification.
  Future<String> approve(String storeId, double commissionPercent) async {
    final error = validateCommission(commissionPercent);
    if (error != null) throw ArgumentError(error);
    return _review({'storeId': storeId, 'decision': 'approve', 'commissionPercent': commissionPercent});
  }

  /// `reviewPartner` reject: the store doc is deleted (application archived), owner notified.
  Future<String> reject(String storeId, String reason) async {
    final error = validateReason(reason);
    if (error != null) throw ArgumentError(error);
    return _review({'storeId': storeId, 'decision': 'reject', 'reason': reason.trim()});
  }

  Future<String> _review(Map<String, dynamic> payload) async {
    final data = callableMap(await _call('reviewPartner', payload));
    return data['status'] as String? ?? '';
  }

  /// `setStoreStatus` (super | ops): suspend or reactivate with a reason.
  Future<String> setStatus(String storeId, StoreStatus status, String reason) async {
    if (status == StoreStatus.pendingApproval) throw ArgumentError('A store cannot go back to pending.');
    final error = validateReason(reason);
    if (error != null) throw ArgumentError(error);
    final data = callableMap(
        await _call('setStoreStatus', {'storeId': storeId, 'status': status.name, 'reason': reason.trim()}));
    return data['status'] as String? ?? status.name;
  }
}

final storesAdminRepositoryProvider = Provider<StoresAdminRepository>(
    (ref) => StoresAdminRepository(ref.watch(firestoreProvider), lazyCallable(ref)));

final storesByStatusProvider = StreamProvider.autoDispose.family<List<StoreRecord>, StoreStatus>(
    (ref, status) => ref.watch(storesAdminRepositoryProvider).watchByStatus(status));

final adminStoreProvider = StreamProvider.autoDispose.family<StoreRecord?, String>(
    (ref, id) => ref.watch(storesAdminRepositoryProvider).watchStore(id));

final storeApplicationProvider = StreamProvider.autoDispose.family<StoreApplication?, String>(
    (ref, id) => ref.watch(storesAdminRepositoryProvider).watchApplication(id));

final storeOrdersProvider = StreamProvider.autoDispose.family<List<OrderModel>, String>(
    (ref, id) => ref.watch(storesAdminRepositoryProvider).watchStoreOrders(id));
