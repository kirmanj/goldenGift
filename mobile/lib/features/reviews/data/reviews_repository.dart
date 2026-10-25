import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../models/review_model.dart';

/// Product reviews (SRS §5.26). Customers write their own review (one per
/// order + product, doc id `{orderId}_{uid}`, `isApproved: false`); only
/// approved reviews are listed; `onReviewWrite` maintains the aggregates.
class ReviewsRepository {
  ReviewsRepository(this._db);
  final FirebaseFirestore _db;

  Stream<List<ReviewModel>> watchApproved(String productId, {int limit = 20}) => _db
      .collection(FirestorePaths.productReviews(productId))
      .where('isApproved', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) ReviewModel.fromMap(d.id, d.data(), productId: productId)]);

  /// The customer's own review for that order line (pending or approved).
  Future<ReviewModel?> mine({required String productId, required String orderId, required String uid}) async {
    final snap =
        await _db.doc('${FirestorePaths.productReviews(productId)}/${ReviewModel.docId(orderId: orderId, uid: uid)}').get();
    return snap.exists ? ReviewModel.fromMap(snap.id, snap.data()!, productId: productId) : null;
  }

  /// Creates or replaces the review; editing sends it back to moderation.
  Future<void> submit({
    required String productId,
    required String orderId,
    required String uid,
    required String userName,
    required String storeId,
    required int rating,
    String text = '',
    List<String> images = const [],
  }) async {
    final first = userName.trim().split(RegExp(r'\s+')).first;
    await _db.doc('${FirestorePaths.productReviews(productId)}/${ReviewModel.docId(orderId: orderId, uid: uid)}').set({
      'productId': productId,
      'userId': uid,
      'userName': first,
      'storeId': storeId,
      'rating': rating.clamp(1, 5),
      'text': text.trim().length > ReviewModel.maxText ? text.trim().substring(0, ReviewModel.maxText) : text.trim(),
      'images': images.take(ReviewModel.maxImages).toList(),
      'orderId': orderId,
      'isApproved': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) => ReviewsRepository(ref.watch(firestoreProvider)));

final approvedReviewsProvider = StreamProvider.autoDispose.family<List<ReviewModel>, String>(
    (ref, productId) => ref.watch(reviewsRepositoryProvider).watchApproved(productId));
