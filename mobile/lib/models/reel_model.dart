import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';
import 'product_model.dart';

/// `reels/{id}` (SRS §6.4a, §5.27): a short product video of the Reels tab.
///
/// The dashboard writes the editable fields; the fields derived from the
/// linked product ([storeId], [product], [categoryIds], [giftFor], [priceBand],
/// [filterKeys], [visible]) come from `ReelDerived` (dashboard) and the
/// `onReelWrite` / `onProductWrite` functions.
class ReelModel {
  const ReelModel({
    required this.id,
    required this.productId,
    required this.videoUrl,
    this.posterUrl,
    this.durationMs,
    this.aspectRatio,
    this.caption = LocalizedText.empty,
    this.isActive = true,
    this.storeId = '',
    this.product,
    this.categoryIds = const [],
    this.giftFor = const [],
    this.priceBand = 0,
    this.filterKeys = const [],
    this.visible = false,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String productId;
  final String videoUrl;
  final String? posterUrl;
  final int? durationMs;

  /// Width / height of the video (9:16 ≈ 0.5625); null = unknown.
  final double? aspectRatio;

  /// Optional, ≤ 150 characters.
  final LocalizedText caption;
  final bool isActive;

  // ── Derived from the product ──
  final String storeId;
  final ReelProduct? product;
  final List<String> categoryIds;
  final List<GiftAudience> giftFor;
  final int priceBand;
  final List<String> filterKeys;

  /// `isActive` and the product exists and is active: what the feed queries.
  final bool visible;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const maxCaptionLength = 150;

  factory ReelModel.fromMap(String id, Map<String, dynamic> map) {
    final product = map['product'];
    final ratio = FirestoreParse.decimal(map['aspectRatio']);
    return ReelModel(
      id: id,
      productId: map['productId'] as String? ?? '',
      videoUrl: map['videoUrl'] as String? ?? '',
      posterUrl: FirestoreParse.stringOrNull(map['posterUrl']),
      durationMs: FirestoreParse.integerOrNull(map['durationMs']),
      aspectRatio: ratio > 0 ? ratio : null,
      caption: LocalizedText.fromMap(map, 'caption'),
      isActive: FirestoreParse.boolean(map['isActive'], true),
      storeId: map['storeId'] as String? ?? '',
      product: product is Map ? ReelProduct.fromMap(FirestoreParse.map(product)) : null,
      categoryIds: FirestoreParse.stringList(map['categoryIds']),
      giftFor: giftAudiencesOf(map['giftFor']),
      priceBand: FirestoreParse.integer(map['priceBand']),
      filterKeys: FirestoreParse.stringList(map['filterKeys']),
      visible: FirestoreParse.boolean(map['visible']),
      createdBy: FirestoreParse.stringOrNull(map['createdBy']),
      createdAt: FirestoreParse.date(map['createdAt']),
      updatedAt: FirestoreParse.date(map['updatedAt']),
    );
  }

  /// The fields the dashboard edits (without timestamps / derived fields).
  Map<String, dynamic> toEditableMap() => {
        'productId': productId,
        'videoUrl': videoUrl,
        'posterUrl': posterUrl,
        'durationMs': durationMs,
        'aspectRatio': aspectRatio,
        ...caption.toMap('caption'),
        'isActive': isActive,
      };

  /// An active reel whose product is unavailable (dashboard status).
  bool get productUnavailable => isActive && !visible;
}

/// What a reel's product card shows (`reels.product`, SRS §6.4a) — copied from
/// the product so the feed needs no product reads.
class ReelProduct {
  const ReelProduct({
    required this.title,
    this.image,
    required this.price,
    this.compareAtPrice,
    this.isActive = true,
  });

  final LocalizedText title;
  final String? image;
  final int price;
  final int? compareAtPrice;
  final bool isActive;

  bool get hasDiscount => compareAtPrice != null && compareAtPrice! > price;

  factory ReelProduct.fromMap(Map<String, dynamic> map) => ReelProduct(
        title: LocalizedText.fromMap(map, 'title'),
        image: FirestoreParse.stringOrNull(map['image']),
        price: FirestoreParse.integer(map['price']),
        compareAtPrice: FirestoreParse.integerOrNull(map['compareAtPrice']),
        isActive: FirestoreParse.boolean(map['isActive'], true),
      );

  factory ReelProduct.of(ProductModel p) => ReelProduct(
        title: p.title,
        image: p.mainImage,
        price: p.price,
        compareAtPrice: p.compareAtPrice,
        isActive: p.isActive,
      );

  /// Same shape as `reelProductSnapshot` in functions/src/shared/reelDerived.ts.
  Map<String, dynamic> toMap() => {
        ...title.toMap('title'),
        'image': image,
        'price': price,
        'compareAtPrice': compareAtPrice,
        'isActive': isActive,
      };
}
