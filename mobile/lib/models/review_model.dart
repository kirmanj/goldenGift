import '../core/utils/firestore_parse.dart';

/// `products/{productId}/reviews/{id}` (SRS §5.26, §6.4). One review per
/// customer per product per order (doc id `{orderId}_{uid}`); hidden until an
/// admin sets `isApproved`. `onReviewWrite` keeps the product / store
/// aggregates (approved reviews only).
class ReviewModel {
  const ReviewModel({
    required this.id,
    required this.productId,
    required this.userId,
    required this.userName,
    required this.storeId,
    required this.rating,
    this.text = '',
    this.images = const [],
    required this.orderId,
    this.isApproved = false,
    this.moderatedBy,
    this.moderatedAt,
    this.createdAt,
  });

  final String id;
  final String productId;
  final String userId;

  /// First name only (shown publicly).
  final String userName;
  final String storeId;

  /// 1–5.
  final int rating;
  final String text;
  final List<String> images;
  final String orderId;
  final bool isApproved;

  /// Admin who last approved / hid it (dashboard).
  final String? moderatedBy;
  final DateTime? moderatedAt;
  final DateTime? createdAt;

  static const maxText = 500;
  static const maxImages = 3;

  static String docId({required String orderId, required String uid}) => '${orderId}_$uid';

  factory ReviewModel.fromMap(String id, Map<String, dynamic> map, {String? productId}) => ReviewModel(
        id: id,
        productId: productId ?? map['productId'] as String? ?? '',
        userId: map['userId'] as String? ?? '',
        userName: map['userName'] as String? ?? '',
        storeId: map['storeId'] as String? ?? '',
        rating: FirestoreParse.integer(map['rating']).clamp(1, 5),
        text: map['text'] as String? ?? '',
        images: FirestoreParse.stringList(map['images']),
        orderId: map['orderId'] as String? ?? '',
        isApproved: FirestoreParse.boolean(map['isApproved']),
        moderatedBy: FirestoreParse.stringOrNull(map['moderatedBy']),
        moderatedAt: FirestoreParse.date(map['moderatedAt']),
        createdAt: FirestoreParse.date(map['createdAt']),
      );
}
