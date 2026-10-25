import '../../../core/constants/app_constants.dart';
import '../../../models/product_model.dart';
import '../../../models/reel_model.dart';
import '../../products/data/product_query.dart';

/// Keys of the derived reel field `filterKeys` (SRS §6.4a): category, gift type
/// and the pair, so the Reels filter is ONE array filter. Must match
/// functions/src/shared/reelDerived.ts — both are checked against
/// test/fixtures/product_query_keys.json (`reelKeys`).
class ReelKeys {
  ReelKeys._();

  static String category(String categoryId) => 'cat:$categoryId';
  static String audience(GiftAudience audience) => 'for:${audience.name}';
  static String pair(String categoryId, GiftAudience a) => '${category(categoryId)}|${audience(a)}';

  /// The `filterKeys array-contains` value for a filter; null = no filter.
  static String? filterKey({String? categoryId, GiftAudience? audience}) => switch ((categoryId, audience)) {
        (final String c, final GiftAudience a) => pair(c, a),
        (final String c, null) => category(c),
        (null, final GiftAudience a) => ReelKeys.audience(a),
        (null, null) => null,
      };

  static List<String> filterKeysOf(List<String> categoryIds, List<GiftAudience> giftFor) => [
        for (final c in categoryIds) category(c),
        for (final a in giftFor) audience(a),
        for (final c in categoryIds)
          for (final a in giftFor) pair(c, a),
      ];
}

/// The fields of a reel derived from its product (SRS §6.4a). The dashboard
/// writes them on save so a new reel is queryable at once; `onReelWrite` /
/// `onProductWrite` keep them current.
class ReelDerived {
  ReelDerived._();

  static Map<String, dynamic> fieldsFor({required bool isActive, ProductModel? product}) {
    final categoryIds = <String>{...?product?.categoryIds.where((c) => c.isNotEmpty)}.toList();
    final giftFor = product?.giftFor ?? const <GiftAudience>[];
    return {
      'storeId': product?.storeId ?? '',
      'product': product == null ? null : ReelProduct.of(product).toMap(),
      'categoryIds': categoryIds,
      'giftFor': giftFor.map((a) => a.name).toList(),
      'priceBand': product == null ? 0 : PriceBands.bandOf(product.price),
      'filterKeys': ReelKeys.filterKeysOf(categoryIds, giftFor),
      'visible': isActive && product != null && product.isActive,
    };
  }
}
