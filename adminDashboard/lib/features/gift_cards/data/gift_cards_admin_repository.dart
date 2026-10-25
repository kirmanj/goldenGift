import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/services/callable.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/core/utils/firestore_parse.dart';
import 'package:golden_gift/features/gift_cards/data/gift_cards_repository.dart' show GiftCardsRepository;
import 'package:golden_gift/models/gift_card_model.dart';

import '../../../core/data/audit_log.dart';
import '../../../core/session/admin_session.dart';
import '../../stores/data/callable_errors.dart';
import '../../stores/data/phone_input.dart';

/// Who may do what in the Gift cards module (SRS §9).
class GiftCardsAccess {
  GiftCardsAccess._();

  static bool canEditTemplates(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops || r == AdminRole.content;
  static bool canIssue(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops || r == AdminRole.finance;
  static bool canDisable(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops || r == AdminRole.finance;

  /// Only super admins may issue an amount the template does not accept.
  static bool canOverrideAmount(AdminRole r) => r == AdminRole.superAdmin;
}

// ── Template rules (SRS §5.22, §6.10) ─────────────────────────────────────

class GiftCardRules {
  GiftCardRules._();

  /// Custom amounts, when allowed, start at this (both bounds 0 = no custom amount).
  static const minCustomAmount = 1000;

  /// Sanity cap on any card amount.
  static const maxAmount = 10000000;
  static const maxMessage = 200;
  static const defaultValidityDays = 365;
}

final _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

bool isHexColor(String? value) => value != null && _hex.hasMatch(value.trim());

/// `#RRGGBB` → Color (null when not a valid hex).
Color? colorFromHex(String? value) =>
    isHexColor(value) ? Color(int.parse('FF${value!.trim().substring(1)}', radix: 16)) : null;

/// Upper-case `#RRGGBB`, or null when empty.
String? normalizeHex(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  final withHash = v.startsWith('#') ? v : '#$v';
  return withHash.toUpperCase();
}

/// Positive, unique, ascending.
List<int> normalizePresetAmounts(Iterable<int> amounts) => (amounts.where((a) => a > 0).toSet().toList()..sort());

/// Every rule a template must pass before it is written.
List<String> validateTemplate(GiftCardTemplateModel t) {
  final errors = <String>[];
  if (t.name.en.trim().isEmpty) errors.add('English name is required.');
  final start = t.gradientStart?.trim() ?? '', end = t.gradientEnd?.trim() ?? '';
  if (start.isNotEmpty && !isHexColor(start)) errors.add('Gradient start must be a #RRGGBB colour.');
  if (end.isNotEmpty && !isHexColor(end)) errors.add('Gradient end must be a #RRGGBB colour.');
  if (start.isEmpty != end.isEmpty) errors.add('Set both gradient colours, or neither for the gold shimmer.');
  if (t.presetAmounts.any((a) => a <= 0)) errors.add('Preset amounts must be positive.');
  if (t.presetAmounts.toSet().length != t.presetAmounts.length) errors.add('Preset amounts must be unique.');
  if (t.presetAmounts.any((a) => a > GiftCardRules.maxAmount)) {
    errors.add('Preset amounts are at most ${CurrencyFormatter.format(GiftCardRules.maxAmount)}.');
  }
  final noCustom = t.minAmount == 0 && t.maxAmount == 0;
  if (!noCustom) {
    if (t.minAmount < GiftCardRules.minCustomAmount) {
      errors.add('The minimum custom amount is at least ${CurrencyFormatter.format(GiftCardRules.minCustomAmount)} '
          '(set both to 0 to turn custom amounts off).');
    }
    if (t.maxAmount < t.minAmount) errors.add('The maximum custom amount must be at least the minimum.');
    if (t.maxAmount > GiftCardRules.maxAmount) {
      errors.add('The maximum custom amount is at most ${CurrencyFormatter.format(GiftCardRules.maxAmount)}.');
    }
  }
  if (t.presetAmounts.isEmpty && noCustom) errors.add('Add a preset amount or allow custom amounts.');
  if (t.sortOrder < 0) errors.add('Sort order cannot be negative.');
  return errors;
}

/// One line describing what a template sells, e.g. "15,000 · 25,000 IQD or 10,000–500,000 IQD".
String templateAmountsLabel(GiftCardTemplateModel t) {
  final parts = <String>[
    if (t.presetAmounts.isNotEmpty) t.presetAmounts.map(CurrencyFormatter.formatCompact).join(' · '),
    if (t.allowsCustomAmount) 'custom ${CurrencyFormatter.formatCompact(t.minAmount)}–${CurrencyFormatter.formatCompact(t.maxAmount)}',
  ];
  return parts.isEmpty ? 'No amounts' : '${parts.join(' or ')} IQD';
}

class GiftCardValidationException implements Exception {
  const GiftCardValidationException(this.errors);
  final List<String> errors;
  @override
  String toString() => errors.join('\n');
}

class TemplateInUseException implements Exception {
  const TemplateInUseException(this.templateId);
  final String templateId;
  @override
  String toString() => 'Cards were issued with this template — deactivate it instead of deleting.';
}

// ── Issued cards ──────────────────────────────────────────────────────────

String giftCardStatusLabel(GiftCardStatus s) => switch (s) {
      GiftCardStatus.pending => 'Pending',
      GiftCardStatus.sent => 'Sent',
      GiftCardStatus.redeemed => 'Redeemed',
      GiftCardStatus.expired => 'Expired',
      GiftCardStatus.disabled => 'Disabled',
    };

/// Only cards that can still be redeemed can be disabled.
bool canDisableCard(GiftCardStatus s) => s == GiftCardStatus.pending || s == GiftCardStatus.sent;

/// `gift_cards/{id}` plus the fields the shared model doesn't carry.
class AdminGiftCard {
  const AdminGiftCard({required this.card, this.createdAt, this.disabledReason, this.disabledAt});
  final GiftCardModel card;
  final DateTime? createdAt;
  final String? disabledReason;
  final DateTime? disabledAt;

  String get id => card.id;

  factory AdminGiftCard.fromMap(String id, Map<String, dynamic> map) => AdminGiftCard(
        card: GiftCardModel.fromMap(id, map),
        createdAt: FirestoreParse.date(map['createdAt']),
        disabledReason: FirestoreParse.stringOrNull(map['disabledReason']),
        disabledAt: FirestoreParse.date(map['disabledAt']),
      );
}

/// Same normalisation as the app's redeem field: no dashes / spaces, upper case.
String normalizeGiftCardCode(String input) => GiftCardsRepository.normalizeCode(input);

/// Manual issue through `adminIssueGiftCard` (super | ops | finance); the
/// server generates the unique code, sets status sent and audits.
class ManualGiftCardIssue {
  const ManualGiftCardIssue({
    required this.templateId,
    required this.amount,
    required this.recipientName,
    this.recipientPhone,
    this.recipientEmail,
    this.message = '',
    this.expiresAt,
  });

  final String templateId;
  final int amount;
  final String recipientName;
  final String? recipientPhone;
  final String? recipientEmail;
  final String message;
  final DateTime? expiresAt;

  static DateTime defaultExpiry(DateTime now) =>
      DateTime(now.year, now.month, now.day + GiftCardRules.defaultValidityDays, 23, 59, 59);

  List<String> validate({required GiftCardTemplateModel? template, required bool overrideAmount, required DateTime now}) {
    final errors = <String>[];
    if (template == null || template.id != templateId) errors.add('Choose a template.');
    if (amount <= 0) {
      errors.add('Enter an amount.');
    } else if (amount > GiftCardRules.maxAmount) {
      errors.add('The amount is at most ${CurrencyFormatter.format(GiftCardRules.maxAmount)}.');
    } else if (template != null && !overrideAmount && !template.accepts(amount)) {
      errors.add('“${template.name.en}” does not accept ${CurrencyFormatter.format(amount)} '
          '(${templateAmountsLabel(template)}).');
    }
    if (recipientName.trim().length < 2) errors.add('Recipient name is required.');
    if ((recipientPhone ?? '').trim().isNotEmpty && normalizeStaffPhone(recipientPhone!) == null) {
      errors.add('The recipient phone is not valid.');
    }
    final emailError = validateStaffEmail(recipientEmail);
    if (emailError != null) errors.add('The recipient email is not valid.');
    if (message.trim().length > GiftCardRules.maxMessage) {
      errors.add('Keep the message under ${GiftCardRules.maxMessage} characters.');
    }
    if (expiresAt != null && !expiresAt!.isAfter(now)) errors.add('The expiry must be in the future.');
    return errors;
  }

  Map<String, dynamic> toPayload() {
    final phone = (recipientPhone ?? '').trim();
    final email = (recipientEmail ?? '').trim();
    return {
      'templateId': templateId,
      'amount': amount,
      'recipientName': recipientName.trim(),
      if (phone.isNotEmpty) 'recipientPhone': normalizeStaffPhone(phone) ?? phone,
      if (email.isNotEmpty) 'recipientEmail': email.toLowerCase(),
      if (message.trim().isNotEmpty) 'message': message.trim(),
      if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    };
  }
}

class IssuedGiftCard {
  const IssuedGiftCard({required this.giftCardId, required this.code});
  final String giftCardId;
  final String code;

  /// `ABCD-EFGH-JKLM`
  String get formattedCode =>
      code.length == 12 ? '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}' : code;
}

/// Gift-card templates CRUD and issued-card admin (SRS §9 "Gift cards").
/// Direct writes are ONE batch with their `admin_audit_log` entry.
class GiftCardsAdminRepository {
  GiftCardsAdminRepository(this._db, this._call);
  final FirebaseFirestore _db;
  final CallableInvoker _call;

  static const pageSize = 50;

  CollectionReference<Map<String, dynamic>> get _templates => _db.collection(FirestorePaths.giftCardTemplates);
  CollectionReference<Map<String, dynamic>> get _cards => _db.collection(FirestorePaths.giftCards);

  // Templates ─────────────────────────────────────────────────────────────

  Stream<List<GiftCardTemplateModel>> watchTemplates() => _templates
      .snapshots()
      .map((s) => sortTemplates([for (final d in s.docs) GiftCardTemplateModel.fromMap(d.id, d.data())]));

  static List<GiftCardTemplateModel> sortTemplates(List<GiftCardTemplateModel> list) => [...list]
    ..sort((a, b) {
      final bySort = a.sortOrder.compareTo(b.sortOrder);
      return bySort != 0 ? bySort : a.id.compareTo(b.id);
    });

  /// Id of a template that isn't saved yet (its artwork uploads there first).
  String newTemplateId() => _templates.doc().id;

  Future<void> createTemplate(GiftCardTemplateModel t, {required String adminUid}) async {
    _requireAdmin(adminUid);
    final errors = validateTemplate(t);
    if (errors.isNotEmpty) throw GiftCardValidationException(errors);
    final ref = _templates.doc(t.id);
    final data = t.toMap();
    final batch = _db.batch()
      ..set(ref, {...data, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    AuditLog.add(batch, _db, adminUid: adminUid, action: 'giftCardTemplate.create', target: ref.path, after: data);
    await batch.commit();
  }

  /// Cleared translations are deleted.
  Future<void> updateTemplate(GiftCardTemplateModel before, GiftCardTemplateModel after, {required String adminUid}) async {
    _requireAdmin(adminUid);
    if (before.id != after.id) throw ArgumentError('A template id cannot change.');
    final errors = validateTemplate(after);
    if (errors.isNotEmpty) throw GiftCardValidationException(errors);
    final ref = _templates.doc(after.id);
    final data = after.toMap();
    final batch = _db.batch()
      ..update(ref, {
        ...data,
        for (final k in const ['nameAr', 'nameKu'])
          if (!data.containsKey(k)) k: FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    AuditLog.add(batch, _db,
        adminUid: adminUid, action: 'giftCardTemplate.update', target: ref.path, before: before.toMap(), after: data);
    await batch.commit();
  }

  Future<void> setTemplateActive(GiftCardTemplateModel t, bool isActive, {required String adminUid}) async {
    _requireAdmin(adminUid);
    final ref = _templates.doc(t.id);
    final batch = _db.batch()..update(ref, {'isActive': isActive, 'updatedAt': FieldValue.serverTimestamp()});
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'giftCardTemplate.update',
        target: ref.path,
        before: {'isActive': t.isActive},
        after: {'isActive': isActive});
    await batch.commit();
  }

  /// True when an issued card references the template (it can't be deleted then).
  Future<bool> isTemplateUsed(String templateId) async =>
      (await _cards.where('templateId', isEqualTo: templateId).limit(1).get()).docs.isNotEmpty;

  /// Deletes an unused template; throws [TemplateInUseException] otherwise.
  Future<void> deleteTemplate(GiftCardTemplateModel t, {required String adminUid}) async {
    _requireAdmin(adminUid);
    if (await isTemplateUsed(t.id)) throw TemplateInUseException(t.id);
    final ref = _templates.doc(t.id);
    final batch = _db.batch()..delete(ref);
    AuditLog.add(batch, _db, adminUid: adminUid, action: 'giftCardTemplate.delete', target: ref.path, before: t.toMap());
    await batch.commit();
  }

  /// Rewrites `sortOrder` to the list position for every template that moved
  /// (one batch, one `giftCardTemplate.reorder` entry). Returns how many moved.
  Future<int> reorder(List<GiftCardTemplateModel> ordered, {required String adminUid}) async {
    _requireAdmin(adminUid);
    final before = <String, dynamic>{}, after = <String, dynamic>{};
    final batch = _db.batch();
    for (var i = 0; i < ordered.length; i++) {
      final t = ordered[i];
      if (t.sortOrder == i) continue;
      batch.update(_templates.doc(t.id), {'sortOrder': i});
      before[t.id] = t.sortOrder;
      after[t.id] = i;
    }
    if (after.isEmpty) return 0;
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'giftCardTemplate.reorder',
        target: FirestorePaths.giftCardTemplates,
        before: before,
        after: after);
    await batch.commit();
    return after.length;
  }

  // Issued cards ──────────────────────────────────────────────────────────

  /// Newest first (index `status` + `createdAt` when filtered).
  Stream<List<AdminGiftCard>> watchCards({GiftCardStatus? status, int limit = pageSize}) {
    Query<Map<String, dynamic>> q = _cards;
    if (status != null) q = q.where('status', isEqualTo: status.name);
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => [for (final d in s.docs) AdminGiftCard.fromMap(d.id, d.data())]);
  }

  /// Exact code lookup (typed with or without dashes, any case).
  Stream<List<AdminGiftCard>> watchByCode(String input) => _cards
      .where('code', isEqualTo: normalizeGiftCardCode(input))
      .limit(5)
      .snapshots()
      .map((s) => [for (final d in s.docs) AdminGiftCard.fromMap(d.id, d.data())]);

  Stream<AdminGiftCard?> watchCard(String id) =>
      _cards.doc(id).snapshots().map((d) => d.exists ? AdminGiftCard.fromMap(d.id, d.data()!) : null);

  /// Disable a pending / sent card (it can no longer be redeemed).
  Future<void> disableCard(AdminGiftCard card, {required String reason, required String adminUid}) async {
    _requireAdmin(adminUid);
    if (!canDisableCard(card.card.status)) {
      throw StateError('A ${giftCardStatusLabel(card.card.status).toLowerCase()} card cannot be disabled.');
    }
    final r = reason.trim();
    if (r.length < 3) throw ArgumentError('A reason of at least 3 characters is required.');
    final ref = _cards.doc(card.id);
    final batch = _db.batch()
      ..update(ref, {
        'status': GiftCardStatus.disabled.name,
        'disabledReason': r,
        'disabledBy': adminUid,
        'disabledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'giftCard.disable',
        target: ref.path,
        before: {'status': card.card.status.name, 'balance': card.card.balance},
        after: {'status': GiftCardStatus.disabled.name, 'reason': r});
    await batch.commit();
  }

  Future<IssuedGiftCard> issue(ManualGiftCardIssue request) async {
    final data = callableMap(await _call('adminIssueGiftCard', request.toPayload()));
    return IssuedGiftCard(giftCardId: data['giftCardId'] as String? ?? '', code: data['code'] as String? ?? '');
  }

  static void _requireAdmin(String uid) {
    if (uid.isEmpty) throw StateError('Not signed in as an admin.');
  }
}

final giftCardsAdminRepositoryProvider = Provider<GiftCardsAdminRepository>(
    (ref) => GiftCardsAdminRepository(ref.watch(firestoreProvider), lazyCallable(ref)));

final adminGiftCardTemplatesProvider = StreamProvider.autoDispose<List<GiftCardTemplateModel>>(
    (ref) => ref.watch(giftCardsAdminRepositoryProvider).watchTemplates());

final adminGiftCardsProvider = StreamProvider.autoDispose.family<List<AdminGiftCard>, (GiftCardStatus?, int)>(
    (ref, args) => ref.watch(giftCardsAdminRepositoryProvider).watchCards(status: args.$1, limit: args.$2));

final giftCardCodeSearchProvider = StreamProvider.autoDispose.family<List<AdminGiftCard>, String>(
    (ref, code) => ref.watch(giftCardsAdminRepositoryProvider).watchByCode(code));

final adminGiftCardProvider = StreamProvider.autoDispose.family<AdminGiftCard?, String>(
    (ref, id) => ref.watch(giftCardsAdminRepositoryProvider).watchCard(id));
