import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/router/app_router.dart' show AppRoutes;
import 'package:golden_gift/models/banner_model.dart';
import 'package:golden_gift/models/localized_text.dart';

import '../../core/data/audit_log.dart';
import '../../core/session/admin_session.dart';

/// Every banner, sorted by placement then `sortOrder` (SRS §5.4, §6.8).
final adminBannersProvider = StreamProvider.autoDispose<List<BannerModel>>((ref) => ref
    .watch(firestoreProvider)
    .collection(FirestorePaths.banners)
    .snapshots()
    .map((s) => sortBanners([for (final d in s.docs) BannerModel.fromMap(d.id, d.data())])));

List<BannerModel> sortBanners(List<BannerModel> list) => [...list]
  ..sort((a, b) {
    final byPlacement = a.placement.index.compareTo(b.placement.index);
    if (byPlacement != 0) return byPlacement;
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    return bySort != 0 ? bySort : a.id.compareTo(b.id);
  });

final bannerAdminRepositoryProvider = Provider.autoDispose<BannerAdminRepository>((ref) =>
    BannerAdminRepository(ref.watch(firestoreProvider), adminUid: ref.watch(adminSessionProvider)?.uid ?? ''));

/// English title of `products/{id}`; null when there is no such product.
final productTitleProvider = FutureProvider.autoDispose.family<String?, String>((ref, rawId) async {
  final id = rawId.trim();
  if (id.isEmpty || id.contains('/')) return null;
  final snap = await ref.watch(firestoreProvider).doc(FirestorePaths.productDoc(id)).get();
  final data = snap.data();
  if (!snap.exists || data == null) return null;
  final title = LocalizedText.fromMap(data, 'title').en;
  return title.isEmpty ? id : title;
});

String placementLabel(BannerPlacement p) => switch (p) {
      BannerPlacement.homeTop => 'Home · top carousel',
      BannerPlacement.homeMid1 => 'Home · promo 1 ("Request any gift")',
      BannerPlacement.homeMid2 => 'Home · promo 2 ("Become a partner")',
      BannerPlacement.homeBottom => 'Home · bottom carousel',
    };

String placementHint(BannerPlacement p) => switch (p) {
      BannerPlacement.homeTop => 'Under the header card. 16:7 artwork, auto-plays every 5 s.',
      BannerPlacement.homeMid1 => 'After "Popular". Usually opens Special requests.',
      BannerPlacement.homeMid2 => 'After "Featured". Usually opens Become a partner.',
      BannerPlacement.homeBottom => 'After "For you", e.g. "Design your gift card".',
    };

String actionTypeLabel(BannerActionType t) => switch (t) {
      BannerActionType.category => 'Category',
      BannerActionType.product => 'Product',
      BannerActionType.url => 'Web link',
      BannerActionType.route => 'App screen',
    };

/// App screens a `route` banner may open (customer app AppRoutes).
const bannerRouteOptions = <(String, String)>[
  (AppRoutes.specialRequests, 'Special requests'),
  (AppRoutes.becomePartner, 'Become a partner'),
  (AppRoutes.giftCards, 'Gift cards'),
  (AppRoutes.categories, 'All categories'),
  (AppRoutes.promoCodes, 'Promo codes'),
  (AppRoutes.inviteAndEarn, 'Invite & earn'),
  (AppRoutes.aiGiftSearch, 'AI gift search'),
  (AppRoutes.secretSanta, 'Secret Santa'),
];

String routeLabel(String route) {
  for (final (path, label) in bannerRouteOptions) {
    if (path == route) return label;
  }
  return route;
}

enum BannerStatus {
  live('Live'),
  scheduled('Scheduled'),
  expired('Expired'),
  inactive('Inactive');

  const BannerStatus(this.label);
  final String label;
}

/// Mirrors `BannerModel.isLiveAt` (what the app shows) and says why not.
BannerStatus bannerStatus(BannerModel b, DateTime now) {
  if (!b.isActive) return BannerStatus.inactive;
  if (b.endAt != null && now.isAfter(b.endAt!)) return BannerStatus.expired;
  if (b.startAt != null && now.isBefore(b.startAt!)) return BannerStatus.scheduled;
  return BannerStatus.live;
}

bool isHttpsUrl(String value) {
  final v = value.trim();
  if (v.isEmpty || v.contains(' ')) return false;
  final uri = Uri.tryParse(v);
  return uri != null && uri.scheme == 'https' && uri.host.contains('.');
}

bool _isWebUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
}

/// Field → message. Keys: `imageUrl`, `imageUrlAr`, `imageUrlKu`, `action`, `schedule`.
/// [categoryIds], when given, must contain a `category` action's value.
/// Whether a `product` id exists is checked by the editor (needs a read).
Map<String, String> validateBanner(BannerModel b, {Iterable<String>? categoryIds}) {
  final errors = <String, String>{};
  if (b.imageUrl.trim().isEmpty) {
    errors['imageUrl'] = 'The English artwork is required';
  } else if (!_isWebUrl(b.imageUrl)) {
    errors['imageUrl'] = 'Not a valid image URL';
  }
  if (b.imageUrlAr != null && !_isWebUrl(b.imageUrlAr!)) errors['imageUrlAr'] = 'Not a valid image URL';
  if (b.imageUrlKu != null && !_isWebUrl(b.imageUrlKu!)) errors['imageUrlKu'] = 'Not a valid image URL';

  final value = b.actionValue.trim();
  final actionError = switch (b.actionType) {
    BannerActionType.category => value.isEmpty
        ? 'Pick the category to open'
        : (categoryIds != null && !categoryIds.contains(value) ? 'Category "$value" does not exist' : null),
    BannerActionType.product => value.isEmpty ? 'Enter the product id to open' : null,
    BannerActionType.url => isHttpsUrl(value) ? null : 'Links must be full https:// URLs',
    BannerActionType.route =>
      bannerRouteOptions.any((r) => r.$1 == value) ? null : 'Pick the app screen to open',
  };
  if (actionError != null) errors['action'] = actionError;

  if (b.startAt != null && b.endAt != null && !b.endAt!.isAfter(b.startAt!)) {
    errors['schedule'] = 'The end must be after the start';
  }
  return errors;
}

class BannerValidationException implements Exception {
  const BannerValidationException(this.errors);
  final Map<String, String> errors;
  @override
  String toString() => errors.values.join('\n');
}

/// Banner writes: one batch per change, each with its audit entry.
class BannerAdminRepository {
  BannerAdminRepository(this.db, {required this.adminUid});

  final FirebaseFirestore db;
  final String adminUid;

  DocumentReference<Map<String, dynamic>> _doc(String id) => db.collection(FirestorePaths.banners).doc(id);

  /// Id for a new banner, known before saving so uploads can use `banners/{id}.jpg`.
  String newId() => db.collection(FirestorePaths.banners).doc().id;

  void _requireAdmin() {
    if (adminUid.isEmpty) throw StateError('Not signed in as an admin.');
  }

  int _nextSortOrder(BannerPlacement placement, List<BannerModel> existing, {String? exceptId}) {
    final orders = existing.where((b) => b.placement == placement && b.id != exceptId).map((b) => b.sortOrder);
    return orders.isEmpty ? 0 : orders.reduce(math.max) + 1;
  }

  /// Added at the end of its placement.
  Future<void> create(BannerModel banner, {required List<BannerModel> existing, Iterable<String>? categoryIds}) async {
    _requireAdmin();
    final errors = validateBanner(banner, categoryIds: categoryIds);
    if (errors.isNotEmpty) throw BannerValidationException(errors);
    final ref = _doc(banner.id);
    final data = copyBanner(banner, sortOrder: _nextSortOrder(banner.placement, existing)).toMap();
    final batch = db.batch()..set(ref, data);
    AuditLog.add(batch, db, adminUid: adminUid, action: 'banner.create', target: ref.path, after: data);
    await batch.commit();
  }

  /// Keeps its position, unless it moved to another placement (→ the end of it).
  Future<void> update(BannerModel before, BannerModel after,
      {required List<BannerModel> existing, Iterable<String>? categoryIds}) async {
    _requireAdmin();
    if (before.id != after.id) throw ArgumentError('A banner id cannot change.');
    final errors = validateBanner(after, categoryIds: categoryIds);
    if (errors.isNotEmpty) throw BannerValidationException(errors);
    final ref = _doc(after.id);
    final moved = before.placement != after.placement;
    final sortOrder = moved ? _nextSortOrder(after.placement, existing, exceptId: after.id) : before.sortOrder;
    final data = after.toMap();
    if (moved) {
      data['sortOrder'] = sortOrder;
    } else {
      data.remove('sortOrder');
    }
    for (final key in const ['imageUrlAr', 'imageUrlKu']) {
      data.putIfAbsent(key, FieldValue.delete);
    }
    final batch = db.batch()..update(ref, data);
    AuditLog.add(batch, db,
        adminUid: adminUid,
        action: 'banner.update',
        target: ref.path,
        before: before.toMap(),
        after: copyBanner(after, sortOrder: sortOrder).toMap());
    await batch.commit();
  }

  Future<void> delete(BannerModel banner) async {
    _requireAdmin();
    final ref = _doc(banner.id);
    final batch = db.batch()..delete(ref);
    AuditLog.add(batch, db, adminUid: adminUid, action: 'banner.delete', target: ref.path, before: banner.toMap());
    await batch.commit();
  }

  /// Rewrites `sortOrder` = position for the banners of one placement whose
  /// position changed, with one `banner.reorder` entry. Returns how many moved.
  Future<int> reorder(BannerPlacement placement, List<BannerModel> ordered) async {
    _requireAdmin();
    final before = <String, dynamic>{};
    final after = <String, dynamic>{};
    final batch = db.batch();
    for (var i = 0; i < ordered.length; i++) {
      final b = ordered[i];
      if (b.placement != placement) throw ArgumentError('Banner ${b.id} is not in ${placement.name}.');
      if (b.sortOrder == i) continue;
      batch.update(_doc(b.id), {'sortOrder': i});
      before[b.id] = b.sortOrder;
      after[b.id] = i;
    }
    if (after.isEmpty) return 0;
    AuditLog.add(batch, db,
        adminUid: adminUid,
        action: 'banner.reorder',
        target: FirestorePaths.banners,
        before: {'placement': placement.name, 'sortOrder': before},
        after: {'placement': placement.name, 'sortOrder': after});
    await batch.commit();
    return after.length;
  }
}

/// Through toMap → fromMap so fields added to the model later are kept.
BannerModel copyBanner(BannerModel b, {required int sortOrder}) =>
    BannerModel.fromMap(b.id, {...b.toMap(), 'sortOrder': sortOrder});
