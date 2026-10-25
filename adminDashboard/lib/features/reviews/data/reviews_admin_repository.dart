import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/utils/firestore_parse.dart';
import 'package:golden_gift/models/review_model.dart';

import '../../../core/data/audit_log.dart';
import '../../../core/session/admin_session.dart';

/// Who may moderate (SRS §9 Reviews). Finance sees the queue read-only.
class ReviewsAccess {
  ReviewsAccess._();

  static bool canModerate(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops || r == AdminRole.content;
}

/// The queue's approval filter: new reviews wait with `isApproved = false`.
enum ReviewApproval { pending, approved, all }

String reviewApprovalLabel(ReviewApproval a) => switch (a) {
      ReviewApproval.pending => 'Pending',
      ReviewApproval.approved => 'Approved',
      ReviewApproval.all => 'All',
    };

/// Filters of the moderation queue (SRS §9: product, store, rating, approval state).
class ReviewFilters {
  const ReviewFilters({this.approval = ReviewApproval.pending, this.rating, this.productId, this.storeId});

  final ReviewApproval approval;

  /// 1–5.
  final int? rating;
  final String? productId;
  final String? storeId;

  ReviewFilters copyWith({
    ReviewApproval? approval,
    int? rating,
    bool clearRating = false,
    String? productId,
    bool clearProduct = false,
    String? storeId,
    bool clearStore = false,
  }) =>
      ReviewFilters(
        approval: approval ?? this.approval,
        rating: clearRating ? null : (rating ?? this.rating),
        productId: clearProduct ? null : (productId ?? this.productId),
        storeId: clearStore ? null : (storeId ?? this.storeId),
      );

  /// Whether [r] passes every filter (used for the per-product queue, whose
  /// filters are applied to the product's newest reviews on the client).
  bool matches(AdminReview r) =>
      (approval == ReviewApproval.all || r.review.isApproved == (approval == ReviewApproval.approved)) &&
      (rating == null || r.review.rating == rating) &&
      (productId == null || r.review.productId == productId) &&
      (storeId == null || r.review.storeId == storeId);

  @override
  bool operator ==(Object other) =>
      other is ReviewFilters &&
      other.approval == approval &&
      other.rating == rating &&
      other.productId == productId &&
      other.storeId == storeId;

  @override
  int get hashCode => Object.hash(approval, rating, productId, storeId);
}

/// A review plus where it lives and who last moderated it (`moderatedBy`,
/// `moderatedAt` are dashboard-only fields, not part of [ReviewModel]).
class AdminReview {
  const AdminReview({required this.review, required this.path, this.moderatedBy, this.moderatedAt});

  final ReviewModel review;

  /// `products/{productId}/reviews/{id}`.
  final String path;
  final String? moderatedBy;
  final DateTime? moderatedAt;

  String get id => review.id;

  /// This review with another approval state (the queue shows a just-made
  /// change before the listener catches up).
  AdminReview withApproved(bool approved) {
    final r = review;
    return AdminReview(
      review: ReviewModel(
        id: r.id,
        productId: r.productId,
        userId: r.userId,
        userName: r.userName,
        storeId: r.storeId,
        rating: r.rating,
        text: r.text,
        images: r.images,
        orderId: r.orderId,
        isApproved: approved,
        createdAt: r.createdAt,
      ),
      path: path,
      moderatedBy: moderatedBy,
      moderatedAt: moderatedAt,
    );
  }

  factory AdminReview.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const <String, dynamic>{};
    // The product id is the parent document's id; older docs may lack the field.
    final productId = d.reference.parent.parent?.id ?? data['productId'] as String? ?? '';
    return AdminReview(
      review: ReviewModel.fromMap(d.id, data, productId: productId),
      path: d.reference.path,
      moderatedBy: data['moderatedBy'] as String?,
      moderatedAt: FirestoreParse.date(data['moderatedAt']),
    );
  }
}

class BulkApproveResult {
  const BulkApproveResult({required this.approved, required this.skipped, required this.batches});
  final int approved;

  /// Already approved — nothing to write.
  final int skipped;
  final int batches;
}

/// Moderation of `products/{id}/reviews/{id}` (SRS §5.26, §9 Reviews).
/// Approve / hide only flips `isApproved` (+ `moderatedBy`, `moderatedAt`);
/// `onReviewWrite` recomputes the product and store aggregates, so nothing
/// here touches `ratingAvg` / `ratingCount`. Every write is one batch with its
/// `admin_audit_log` entry.
class ReviewsAdminRepository {
  ReviewsAdminRepository(this._db);
  final FirebaseFirestore _db;

  static const pageSize = 50;

  /// Firestore allows 500 writes per batch; bulk approve stays at ≤ 450
  /// (each review = its update + its audit entry).
  static const maxBatchWrites = 450;
  static const reviewsPerBatch = maxBatchWrites ~/ 2;

  /// How many of one product's newest reviews the per-product queue scans.
  static const perProductScan = 200;

  /// The whole queue is one collection-group query on `reviews`, newest
  /// first, with equality filters on `isApproved` / `rating` / `storeId`
  /// (collection-group indexes `<field> + createdAt desc`; Firestore merges
  /// them for combinations).
  ///
  /// A product filter reads that product's own subcollection instead (newest
  /// [perProductScan], no composite index) and applies the other filters on
  /// the client.
  Query<Map<String, dynamic>> query(ReviewFilters f, {int limit = pageSize}) {
    if (f.productId != null) {
      return _db
          .collection(FirestorePaths.productReviews(f.productId!))
          .orderBy('createdAt', descending: true)
          .limit(perProductScan);
    }
    Query<Map<String, dynamic>> q = _db.collectionGroup(FirestorePaths.reviews);
    if (f.approval != ReviewApproval.all) q = q.where('isApproved', isEqualTo: f.approval == ReviewApproval.approved);
    if (f.rating != null) q = q.where('rating', isEqualTo: f.rating);
    if (f.storeId != null) q = q.where('storeId', isEqualTo: f.storeId);
    return q.orderBy('createdAt', descending: true).limit(limit);
  }

  Stream<List<AdminReview>> watch(ReviewFilters f, {int limit = pageSize}) =>
      query(f, limit: limit).snapshots().map((s) {
        final list = [for (final d in s.docs) AdminReview.fromSnapshot(d)];
        return f.productId == null ? list : list.where(f.matches).take(limit).toList();
      });

  Stream<AdminReview?> watchOne(String path) =>
      _db.doc(path).snapshots().map((d) => d.exists ? AdminReview.fromSnapshot(d) : null);

  /// Approve (shown in the app) or hide (`isApproved = false`).
  Future<void> setApproved(AdminReview r, bool approved, {required String adminUid}) async {
    final batch = _db.batch();
    _moderate(batch, r, approved, adminUid);
    await batch.commit();
  }

  /// Approves every not-yet-approved review of [reviews], [reviewsPerBatch]
  /// per batch (≤ [maxBatchWrites] writes), one audit entry per review.
  Future<BulkApproveResult> bulkApprove(List<AdminReview> reviews, {required String adminUid}) async {
    final todo = reviews.where((r) => !r.review.isApproved).toList();
    var batches = 0;
    for (var i = 0; i < todo.length; i += reviewsPerBatch) {
      final batch = _db.batch();
      for (final r in todo.skip(i).take(reviewsPerBatch)) {
        _moderate(batch, r, true, adminUid);
      }
      await batch.commit();
      batches++;
    }
    return BulkApproveResult(approved: todo.length, skipped: reviews.length - todo.length, batches: batches);
  }

  void _moderate(WriteBatch batch, AdminReview r, bool approved, String adminUid) {
    batch.update(_db.doc(r.path), {
      'isApproved': approved,
      'moderatedBy': adminUid,
      'moderatedAt': FieldValue.serverTimestamp(),
    });
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: approved ? 'review.approve' : 'review.hide',
        target: r.path,
        before: {'isApproved': r.review.isApproved},
        after: {'isApproved': approved, 'rating': r.review.rating, 'productId': r.review.productId});
  }
}

final reviewsAdminRepositoryProvider =
    Provider<ReviewsAdminRepository>((ref) => ReviewsAdminRepository(ref.watch(firestoreProvider)));

final adminReviewsProvider = StreamProvider.autoDispose.family<List<AdminReview>, (ReviewFilters, int)>(
  (ref, args) => ref.watch(reviewsAdminRepositoryProvider).watch(args.$1, limit: args.$2),
);

final adminReviewProvider = StreamProvider.autoDispose.family<AdminReview?, String>(
  (ref, path) => ref.watch(reviewsAdminRepositoryProvider).watchOne(path),
);

/// English title of a product (row label / product filter), null when the
/// product doesn't exist.
final reviewProductTitleProvider = FutureProvider.autoDispose.family<String?, String>((ref, productId) async {
  if (productId.isEmpty || productId.contains('/')) return null;
  final snap = await ref.watch(firestoreProvider).doc(FirestorePaths.productDoc(productId)).get();
  final data = snap.data();
  if (data == null) return null;
  final title = data['title'];
  return title is String && title.isNotEmpty ? title : productId;
});
