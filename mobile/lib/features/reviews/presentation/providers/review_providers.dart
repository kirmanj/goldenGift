import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../models/localized_text.dart';
import '../../../../models/review_model.dart';
import '../../data/reviews_repository.dart';

/// Approved reviews of a product, newest first, [limit] at a time — the
/// "See all" sheet grows the limit as the customer scrolls (SRS §5.26).
final approvedReviewsPageProvider =
    StreamProvider.autoDispose.family<List<ReviewModel>, ({String productId, int limit})>(
  (ref, key) => ref.watch(reviewsRepositoryProvider).watchApproved(key.productId, limit: key.limit),
);

/// The signed-in customer's own review of one order line (pending or
/// approved); null when there is none yet or nobody is signed in.
final myReviewProvider = FutureProvider.autoDispose.family<ReviewModel?, ({String productId, String orderId})>(
  (ref, key) async {
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    if (uid == null) return null;
    return ref.watch(reviewsRepositoryProvider).mine(productId: key.productId, orderId: key.orderId, uid: uid);
  },
);

/// What a review is about: one product of one delivered order.
class ReviewTarget {
  const ReviewTarget({
    required this.productId,
    required this.orderId,
    required this.storeId,
    required this.productTitle,
    this.image,
  });

  final String productId;
  final String orderId;
  final String storeId;
  final LocalizedText productTitle;
  final String? image;

  ({String productId, String orderId}) get key => (productId: productId, orderId: orderId);

  /// Storage folder for the review photos (`{folder}/{n}.jpg`).
  String photoFolder(String uid) => 'reviews/$uid/${orderId}_$productId';
}

/// Average of the loaded reviews — used while the product aggregates
/// (`onReviewWrite`) are not there yet.
double averageRating(List<ReviewModel> reviews) =>
    reviews.isEmpty ? 0 : reviews.fold<int>(0, (n, r) => n + r.rating) / reviews.length;
