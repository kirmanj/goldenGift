import '../../../core/constants/app_constants.dart';
import '../../../core/utils/search_tokenizer.dart';
import '../../../models/product_model.dart';
import 'product_query.dart';

/// The derived query fields of a product (SRS §6.4). Normally written by the
/// `onProductWrite` function; the admin dashboard writes them too, so data is
/// queryable even before functions are deployed. Must match
/// functions/src/shared/productDerived.ts — both are checked against
/// test/fixtures/product_query_keys.json.
class ProductDerived {
  ProductDerived._();

  static Map<String, dynamic> fieldsFor({
    required int price,
    int? compareAtPrice,
    required List<String> categoryIds,
    required List<String> availableCities,
    List<GiftAudience> giftFor = const [],
  }) {
    final cityKeys = availableCities.isEmpty ? [ProductKeys.allCities] : availableCities;
    return {
      'hasDiscount': compareAtPrice != null && compareAtPrice > price,
      'priceBand': PriceBands.bandOf(price),
      'cityKeys': cityKeys,
      'catCityKeys': [
        for (final c in categoryIds)
          for (final city in cityKeys) '$c|$city',
      ],
      // Gift type alone, × category, × city, × category × city (SRS §5.8a).
      'forKeys': [
        for (final a in giftFor) ...[
          ProductKeys.forKey(a),
          for (final c in categoryIds) ProductKeys.forKey(a, categoryId: c),
          for (final city in cityKeys) ProductKeys.forKey(a, cityKey: city),
          for (final c in categoryIds)
            for (final city in cityKeys) ProductKeys.forKey(a, categoryId: c, cityKey: city),
        ],
      ],
    };
  }

  /// Everything the product's queries rely on, including `searchKeywords`.
  static Map<String, dynamic> of(ProductModel p) => {
        ...fieldsFor(
          price: p.price,
          compareAtPrice: p.compareAtPrice,
          categoryIds: p.categoryIds,
          availableCities: p.availableCities,
          giftFor: p.giftFor,
        ),
        'searchKeywords': SearchTokenizer.keywords([...p.title.all, ...p.tags]),
      };
}
