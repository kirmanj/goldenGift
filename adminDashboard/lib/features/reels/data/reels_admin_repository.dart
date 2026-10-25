import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/features/reels/data/reel_derived.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/reel_model.dart';

import '../../../core/data/audit_log.dart';
import '../../../core/session/admin_session.dart';
import 'reel_media.dart';

/// Who may open the Reels module (SRS §9 Reels): catalogue staff — never
/// finance, never partner accounts (sellers: not in v1).
class ReelsAccess {
  ReelsAccess._();

  static bool canManage(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops || r == AdminRole.content;

  static const who = 'super admins, ops and content';
}

/// The status shown on a reel card (SRS §9 Reels).
enum ReelStatus {
  active('Active'),
  hidden('Hidden'),

  /// Active, but its product is inactive or gone, so the app doesn't show it.
  productUnavailable('Product unavailable');

  const ReelStatus(this.label);
  final String label;
}

ReelStatus reelStatusOf(ReelModel r) =>
    !r.isActive ? ReelStatus.hidden : (r.productUnavailable ? ReelStatus.productUnavailable : ReelStatus.active);

/// The filter chips above the grid: by the Active switch (a "Product
/// unavailable" reel is active, so it is listed under Active).
enum ReelFilter {
  all('All'),
  active('Active'),
  hidden('Hidden');

  const ReelFilter(this.label);
  final String label;

  bool matches(ReelModel r) => switch (this) {
        ReelFilter.all => true,
        ReelFilter.active => r.isActive,
        ReelFilter.hidden => !r.isActive,
      };
}

/// `m:ss` (rounded to the second); null when the duration is unknown.
String? formatReelDuration(int? durationMs) {
  if (durationMs == null || durationMs < 0) return null;
  final seconds = (durationMs / 1000).round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Whether width / height is (within 0.02 of) the recommended vertical 9:16.
bool isVertical916(double? aspectRatio) =>
    aspectRatio != null && (aspectRatio - ReelFileRules.recommendedAspectRatio).abs() <= 0.02;

class ReelValidationException implements Exception {
  const ReelValidationException(this.errors);
  final List<String> errors;
  @override
  String toString() => errors.join('\n');
}

class ReelNotFoundException implements Exception {
  const ReelNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'Reel "$id" no longer exists.';
}

/// Every rule a reel must pass before it is written.
List<String> validateReel(ReelModel r) {
  final errors = <String>[];
  if (r.productId.trim().isEmpty) errors.add('Choose the product this reel shows.');
  if (r.videoUrl.trim().isEmpty) errors.add('Choose the video (MP4).');
  for (final (lang, text) in [('English', r.caption.en), ('Arabic', r.caption.ar), ('Kurdish', r.caption.ku)]) {
    if ((text?.length ?? 0) > ReelModel.maxCaptionLength) {
      errors.add('The $lang caption is longer than ${ReelModel.maxCaptionLength} characters.');
    }
  }
  return errors;
}

/// Reads and writes `reels` for the dashboard (SRS §6.4a, §9 Reels). Every
/// write is ONE batch with its `admin_audit_log` entry, and always carries
/// the fields derived from the freshly read product ([ReelDerived]) so a reel
/// is queryable (`visible`, `filterKeys`, `priceBand`) before `onReelWrite` runs.
class ReelsAdminRepository {
  ReelsAdminRepository(this._db, this._media);
  final FirebaseFirestore _db;
  final ReelMediaStore _media;

  /// Newest first; the grid loads this many more with "Load more".
  static const pageSize = 120;

  static const _translationFields = ['captionAr', 'captionKu'];
  static const _timestampFields = {'createdAt', 'updatedAt'};

  CollectionReference<Map<String, dynamic>> get _reels => _db.collection(FirestorePaths.reels);

  /// Id of a new reel, known before uploading so the files go to `reels/{id}.*`.
  String newId() => _reels.doc().id;

  Future<ProductModel?> loadProduct(String productId) async {
    final id = productId.trim();
    if (id.isEmpty || id.contains('/')) return null;
    final snap = await _db.doc(FirestorePaths.productDoc(id)).get();
    final data = snap.data();
    return data == null ? null : ProductModel.fromMap(snap.id, data);
  }

  /// The reel's editable fields + the fields derived from [product].
  static Map<String, dynamic> reelData(ReelModel reel, ProductModel? product) => {
        ...reel.toEditableMap(),
        ...ReelDerived.fieldsFor(isActive: reel.isActive, product: product),
      };

  /// Creates (`createdBy`, `createdAt`) or updates `reels/{reel.id}` with a
  /// `reel.create` / `reel.update` audit entry. The product is read fresh; a
  /// product that no longer exists blocks the save. An update deletes caption
  /// translations that were cleared and leaves `createdBy` / `createdAt` alone.
  Future<void> save(ReelModel reel, {required bool isNew, required String adminUid}) async {
    final errors = validateReel(reel);
    if (errors.isNotEmpty) throw ReelValidationException(errors);
    final product = await loadProduct(reel.productId);
    if (product == null) {
      throw ReelValidationException(['The product “${reel.productId}” no longer exists — choose another one.']);
    }
    final ref = _reels.doc(reel.id);
    final target = FirestorePaths.reelDoc(reel.id);
    final data = reelData(reel, product);
    final batch = _db.batch();
    if (isNew) {
      final created = {...data, 'createdBy': adminUid};
      batch.set(ref, {
        ...created,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AuditLog.add(batch, _db, adminUid: adminUid, action: 'reel.create', target: target, after: created);
    } else {
      final current = (await ref.get()).data();
      if (current == null) throw ReelNotFoundException(reel.id);
      final before = _withoutTimestamps(current);
      final cleared = [for (final k in _translationFields) if (!data.containsKey(k)) k];
      batch.update(ref, {
        ...data,
        for (final k in cleared) k: FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final after = {...before, ...data}..removeWhere((k, _) => cleared.contains(k));
      AuditLog.add(batch, _db, adminUid: adminUid, action: 'reel.update', target: target, before: before, after: after);
    }
    await batch.commit();
  }

  /// Activate / Hide from the grid: `isActive` + `visible` and the other
  /// derived fields recomputed from the product (which may be gone).
  Future<void> setActive(String reelId, bool isActive, {required String adminUid}) async {
    final ref = _reels.doc(reelId);
    final current = (await ref.get()).data();
    if (current == null) throw ReelNotFoundException(reelId);
    final reel = ReelModel.fromMap(reelId, current);
    final product = await loadProduct(reel.productId);
    final changes = {
      'isActive': isActive,
      ...ReelDerived.fieldsFor(isActive: isActive, product: product),
    };
    final before = _withoutTimestamps(current);
    final batch = _db.batch()..update(ref, {...changes, 'updatedAt': FieldValue.serverTimestamp()});
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'reel.update',
        target: FirestorePaths.reelDoc(reelId),
        before: before,
        after: {...before, ...changes});
    await batch.commit();
  }

  /// Deletes the doc with a `reel.delete` audit entry (one batch), then its
  /// Storage files (missing ones are ignored). Returns a warning when the
  /// files could not be removed — the reel itself is gone either way.
  Future<String?> delete(String reelId, {required String adminUid}) async {
    final ref = _reels.doc(reelId);
    final current = (await ref.get()).data();
    final batch = _db.batch()..delete(ref);
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'reel.delete',
        target: FirestorePaths.reelDoc(reelId),
        before: current == null ? null : _withoutTimestamps(current));
    await batch.commit();
    try {
      await _media.deleteFiles(reelId);
      return null;
    } catch (e) {
      return 'The video and poster could not be removed from Storage: $e';
    }
  }

  static Map<String, dynamic> _withoutTimestamps(Map<String, dynamic> map) =>
      Map.of(map)..removeWhere((k, _) => _timestampFields.contains(k));
}

final reelsAdminRepositoryProvider = Provider<ReelsAdminRepository>(
    (ref) => ReelsAdminRepository(ref.watch(firestoreProvider), ref.watch(reelMediaStoreProvider)));

/// The newest [limit] reels (admins read every reel, SRS §6.17).
final adminReelsProvider = StreamProvider.autoDispose.family<List<ReelModel>, int>((ref, limit) => ref
    .watch(firestoreProvider)
    .collection(FirestorePaths.reels)
    .orderBy('createdAt', descending: true)
    .limit(limit)
    .snapshots()
    .map((s) => [for (final d in s.docs) ReelModel.fromMap(d.id, d.data())]));
