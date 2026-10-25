import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/utils/validators.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/localized_text.dart';

import '../../core/data/audit_log.dart';
import '../../core/session/admin_session.dart';
import '../banners/banners_data.dart' show isHttpsUrl;
import '../categories/slug.dart';

/// `app_settings/{doc}` ids edited here (SRS §6.14).
class SettingsDocs {
  SettingsDocs._();
  static const general = 'general';
  static const cities = 'cities';
  static const payments = 'payments';
  static const referral = 'referral';
  static const search = 'search';
}

/// Raw `app_settings/{docId}`; null while the document does not exist (the
/// app then runs on the model defaults).
final settingsDocProvider = StreamProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, docId) => ref
    .watch(firestoreProvider)
    .doc(FirestorePaths.settingsDoc(docId))
    .snapshots()
    .map((s) => s.exists ? s.data() : null));

final settingsAdminRepositoryProvider = Provider.autoDispose<SettingsAdminRepository>((ref) =>
    SettingsAdminRepository(ref.watch(firestoreProvider), adminUid: ref.watch(adminSessionProvider)?.uid ?? ''));

class SettingsAdminRepository {
  SettingsAdminRepository(this.db, {required this.adminUid});

  final FirebaseFirestore db;
  final String adminUid;

  /// One batch: `set(merge)` of [after] (fields the model does not know
  /// are kept) + `settings.{docId}.update`.
  /// [before] is null when the document did not exist yet.
  Future<void> save(String docId, {required Map<String, dynamic>? before, required Map<String, dynamic> after}) async {
    if (adminUid.isEmpty) throw StateError('Not signed in as an admin.');
    final ref = db.doc(FirestorePaths.settingsDoc(docId));
    final batch = db.batch()..set(ref, after, SetOptions(merge: true));
    AuditLog.add(batch, db,
        adminUid: adminUid, action: 'settings.$docId.update', target: ref.path, before: before, after: after);
    await batch.commit();
  }
}

// ── Field validators (null = valid) ──

final _version = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$');
final _cutoff = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
final _phone = RegExp(r'^\+?[0-9][0-9 \-]{5,18}[0-9]$');

String? validateAppVersion(String? v) =>
    _version.hasMatch(v?.trim() ?? '') ? null : 'Use x.y.z, e.g. 1.2.0';

String? validateCutoff(String? v) => _cutoff.hasMatch(v?.trim() ?? '') ? null : 'Use 24-hour HH:mm, e.g. 14:00';

String? validateStoreUrl(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty || isHttpsUrl(value)) return null;
  return 'Must be an https:// link, or empty';
}

String? validateContactPhone(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty || _phone.hasMatch(value)) return null;
  return 'Digits, spaces and an optional leading +, e.g. +964 750 123 4567';
}

String? validateContactEmail(String? v) => Validators.email(v) == null ? null : 'Not a valid email address';

String? validateCount(String? v) {
  final n = int.tryParse(v?.trim() ?? '');
  if (n == null) return 'Required';
  if (n < 0) return 'Cannot be negative';
  return null;
}

// ── Whole-document validation ──

List<String> validateGeneralSettings(GeneralSettings s) {
  String? label(String name, String? error) => error == null ? null : '$name: $error';
  return [
    label('Support phone', validateContactPhone(s.supportPhone)),
    label('WhatsApp', validateContactPhone(s.whatsapp)),
    label('Support email', validateContactEmail(s.email)),
    label('Same-day cut-off', validateCutoff(s.sameDayCutoff)),
    if (s.minOrder < 0) 'Minimum order cannot be negative',
    label('Minimum iOS version', validateAppVersion(s.minAppVersionIos)),
    label('Minimum Android version', validateAppVersion(s.minAppVersionAndroid)),
    label('App Store link', validateStoreUrl(s.storeUrlIos)),
    label('Google Play link', validateStoreUrl(s.storeUrlAndroid)),
  ].whereType<String>().toList();
}

List<String> validateCities(List<CityModel> cities) {
  final errors = <String>[];
  final seen = <String>{};
  for (var i = 0; i < cities.length; i++) {
    final c = cities[i];
    final name = c.name.en.trim().isEmpty ? 'City ${i + 1}' : c.name.en.trim();
    if (c.name.en.trim().isEmpty) errors.add('$name: the English name is required');
    if (!isValidSlug(c.id)) {
      errors.add('$name: the id must be lowercase letters, digits and dashes');
    } else if (!seen.add(c.id)) {
      errors.add('$name: the id "${c.id}" is used more than once');
    }
    if (c.deliveryFee < 0) errors.add('$name: the delivery fee cannot be negative');
  }
  if (!cities.any((c) => c.isActive)) errors.add('At least one city must be active, or nobody can check out');
  return errors;
}

List<String> validatePaymentSettings(PaymentSettings p) => [
      if (!p.cashOnDelivery && !p.wallet && !p.anyOnlineGateway) 'At least one payment method must stay on',
    ];

List<String> validateReferralSettings(ReferralSettings r) => [
      if (r.joinBonus < 0 || r.orderBonus < 0) 'Bonuses cannot be negative',
      if (r.maxReferralsPerMonth < 0) 'The monthly limit cannot be negative',
      if (r.creditsExpiryDays < 0) 'The expiry cannot be negative',
    ];

List<String> validateSearchSettings(SearchSettings s) => [
      if (s.algoliaAppId.trim().isEmpty != s.algoliaSearchKey.trim().isEmpty)
        'Set both the Application ID and the search key (or neither)',
      if (s.indexName.trim().isEmpty) 'The index name is required',
      if (s.algoliaAppId.contains(' ') || s.algoliaSearchKey.contains(' ')) 'Ids and keys cannot contain spaces',
    ];

/// The seeded city list (SRS §4.3) for an empty `app_settings/cities`.
List<CityModel> defaultCities(List<String> names) =>
    [for (final n in names) CityModel(id: slugify(n), name: LocalizedText(n))];

// ── copyWith for the shared models. Each goes through toMap → fromMap, so a
// field the app adds to a model later (like `general.deliverySlots`) is
// carried along instead of being reset to its default. ──

extension GeneralSettingsCopy on GeneralSettings {
  GeneralSettings copyWith({
    String? supportPhone,
    String? whatsapp,
    String? email,
    String? instagram,
    String? sameDayCutoff,
    int? minOrder,
    bool? maintenanceMode,
    String? minAppVersionIos,
    String? minAppVersionAndroid,
    String? storeUrlIos,
    String? storeUrlAndroid,
  }) {
    final map = toMap();
    return GeneralSettings.fromMap({
      ...map,
      if (supportPhone != null) 'supportPhone': supportPhone,
      if (whatsapp != null) 'whatsapp': whatsapp,
      if (email != null) 'email': email,
      if (instagram != null) 'instagram': instagram,
      if (sameDayCutoff != null) 'sameDayCutoff': sameDayCutoff,
      if (minOrder != null) 'minOrder': minOrder,
      if (maintenanceMode != null) 'maintenanceMode': maintenanceMode,
      'minAppVersion': {
        ...?(map['minAppVersion'] as Map<String, dynamic>?),
        'ios': minAppVersionIos ?? this.minAppVersionIos,
        'android': minAppVersionAndroid ?? this.minAppVersionAndroid,
      },
      'storeUrls': {
        ...?(map['storeUrls'] as Map<String, dynamic>?),
        'ios': storeUrlIos ?? this.storeUrlIos,
        'android': storeUrlAndroid ?? this.storeUrlAndroid,
      },
    });
  }
}

extension CityCopy on CityModel {
  CityModel copyWith({String? id, LocalizedText? name, int? deliveryFee, bool? isActive}) {
    final map = toMap();
    if (name != null) {
      map
        ..remove('name')
        ..remove('nameAr')
        ..remove('nameKu')
        ..addAll(name.toMap('name'));
    }
    return CityModel.fromMap({
      ...map,
      if (id != null) 'id': id,
      if (deliveryFee != null) 'deliveryFee': deliveryFee,
      if (isActive != null) 'isActive': isActive,
    });
  }
}

extension PaymentSettingsCopy on PaymentSettings {
  PaymentSettings copyWith({bool? cashOnDelivery, bool? wallet, bool? card, bool? fastPay, bool? zainCash}) =>
      PaymentSettings.fromMap({
        ...toMap(),
        if (cashOnDelivery != null) 'cashOnDelivery': cashOnDelivery,
        if (wallet != null) 'wallet': wallet,
        if (card != null) 'card': card,
        if (fastPay != null) 'fastPay': fastPay,
        if (zainCash != null) 'zainCash': zainCash,
      });
}

extension ReferralSettingsCopy on ReferralSettings {
  ReferralSettings copyWith({int? joinBonus, int? orderBonus, int? maxReferralsPerMonth, int? creditsExpiryDays}) =>
      ReferralSettings.fromMap({
        ...toMap(),
        if (joinBonus != null) 'joinBonus': joinBonus,
        if (orderBonus != null) 'orderBonus': orderBonus,
        if (maxReferralsPerMonth != null) 'maxReferralsPerMonth': maxReferralsPerMonth,
        if (creditsExpiryDays != null) 'creditsExpiryDays': creditsExpiryDays,
      });
}

extension SearchSettingsCopy on SearchSettings {
  /// An empty index name reads back as the default `products` (SearchSettings.fromMap).
  SearchSettings copyWith({String? algoliaAppId, String? algoliaSearchKey, String? indexName}) =>
      SearchSettings.fromMap({
        ...toMap(),
        if (algoliaAppId != null) 'algoliaAppId': algoliaAppId,
        if (algoliaSearchKey != null) 'algoliaSearchKey': algoliaSearchKey,
        if (indexName != null) 'indexName': indexName,
      });
}
