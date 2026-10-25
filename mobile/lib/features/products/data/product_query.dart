import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/firestore_parse.dart';

/// Sort orders of the products list (SRS §5.8). `null` on a [ProductQuery]
/// means the default: best match for a text search, newest otherwise.
enum ProductSort { relevance, newest, popular, priceLowHigh, priceHighLow }

/// The §5.8 price filter as bands, so it stays a single Firestore query.
/// Must match `priceBandOf` in functions/src/shared/productDerived.ts
/// (both are checked against test/fixtures/product_query_keys.json).
class PriceBands {
  PriceBands._();

  /// Upper bounds (exclusive) of bands 0–3 in IQD; band 4 is open-ended.
  static const bounds = [25000, 50000, 100000, 200000];
  static const count = 5;

  static int bandOf(int price) {
    for (var i = 0; i < bounds.length; i++) {
      if (price < bounds[i]) return i;
    }
    return bounds.length;
  }

  /// Inclusive minimum and exclusive maximum (null = no maximum).
  static (int, int?) rangeOf(int band) {
    assert(band >= 0 && band < count);
    final min = band == 0 ? 0 : bounds[band - 1];
    final max = band < bounds.length ? bounds[band] : null;
    return (min, max);
  }
}

/// Keys of the derived product fields `cityKeys` / `catCityKeys` (SRS §6.4).
class ProductKeys {
  ProductKeys._();

  /// Stands for "deliverable to every served city".
  static const allCities = 'all';

  static List<String> cityAnyOf(String cityId) => [cityId, allCities];

  static List<String> catCityAnyOf(String categoryId, String cityId) =>
      ['$categoryId|$cityId', '$categoryId|$allCities'];

  /// One `forKeys` entry (SRS §5.8a, §6.4): gift type [audience], optionally
  /// narrowed to a category and / or a city key (a city id or [allCities]).
  static String forKey(GiftAudience audience, {String? categoryId, String? cityKey}) => [
        audience.name,
        if (categoryId != null) 'cat:$categoryId',
        if (cityKey != null) 'city:$cityKey',
      ].join('|');

  /// `forKeys array-contains-any` values for "a gift for [audience]", optionally
  /// in [categoryId] and deliverable to [cityId].
  static List<String> forAnyOf(GiftAudience audience, {String? categoryId, String? cityId}) => cityId == null
      ? [forKey(audience, categoryId: categoryId)]
      : [for (final city in cityAnyOf(cityId)) forKey(audience, categoryId: categoryId, cityKey: city)];
}

/// Everything that defines one products list (SRS §5.8): used as the
/// family key of the list controller, so it has value equality.
@immutable
class ProductQuery {
  const ProductQuery({
    this.categoryId,
    this.text = '',
    this.sort,
    this.priceBands = const {},
    this.sameDayOnly = false,
    this.discountOnly = false,
    this.featuredOnly = false,
    this.cityId,
    this.giftFor,
  });

  final String? categoryId;
  final String text;
  final ProductSort? sort;
  final Set<int> priceBands;
  final bool sameDayOnly;
  final bool discountOnly;

  /// Home ▸ Featured ▸ View All (not offered in the filter sheet).
  final bool featuredOnly;

  /// Deliver-to city id.
  final String? cityId;

  /// Gift type filter (SRS §5.8a); null = everyone.
  final GiftAudience? giftFor;

  bool get hasText => text.trim().isNotEmpty;

  ProductSort get effectiveSort => sort ?? (hasText ? ProductSort.relevance : ProductSort.newest);

  /// Filters chosen in the filter sheet (drives the badge on the filter button).
  int get activeFilterCount =>
      (priceBands.isNotEmpty && priceBands.length < PriceBands.count ? 1 : 0) +
      (sameDayOnly ? 1 : 0) +
      (discountOnly ? 1 : 0) +
      (cityId != null ? 1 : 0) +
      (giftFor != null ? 1 : 0) +
      (sort != null ? 1 : 0);

  ProductQuery copyWith({
    String? categoryId,
    bool clearCategory = false,
    String? text,
    ProductSort? sort,
    bool clearSort = false,
    Set<int>? priceBands,
    bool? sameDayOnly,
    bool? discountOnly,
    bool? featuredOnly,
    String? cityId,
    bool clearCity = false,
    GiftAudience? giftFor,
    bool clearGiftFor = false,
  }) =>
      ProductQuery(
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        text: text ?? this.text,
        sort: clearSort ? null : (sort ?? this.sort),
        priceBands: priceBands ?? this.priceBands,
        sameDayOnly: sameDayOnly ?? this.sameDayOnly,
        discountOnly: discountOnly ?? this.discountOnly,
        featuredOnly: featuredOnly ?? this.featuredOnly,
        cityId: clearCity ? null : (cityId ?? this.cityId),
        giftFor: clearGiftFor ? null : (giftFor ?? this.giftFor),
      );

  /// Clears the filter-sheet choices, keeping category, text and featured.
  ProductQuery withoutFilters() => ProductQuery(categoryId: categoryId, text: text, featuredOnly: featuredOnly);

  /// `/products?category=frames&q=mug&sort=popular&price=1,2&sameDay=1&sale=1&featured=1&city=erbil&for=women`
  Map<String, String> toQueryParameters() => {
        if (categoryId != null) 'category': categoryId!,
        if (hasText) 'q': text.trim(),
        if (sort != null) 'sort': sort!.name,
        if (priceBands.isNotEmpty) 'price': (priceBands.toList()..sort()).join(','),
        if (sameDayOnly) 'sameDay': '1',
        if (discountOnly) 'sale': '1',
        if (featuredOnly) 'featured': '1',
        if (cityId != null) 'city': cityId!,
        if (giftFor != null) 'for': giftFor!.name,
      };

  factory ProductQuery.fromQueryParameters(Map<String, String> params) {
    ProductSort? sort;
    for (final s in ProductSort.values) {
      if (s.name == params['sort']) sort = s;
    }
    final bands = (params['price'] ?? '')
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .where((b) => b >= 0 && b < PriceBands.count)
        .toSet();
    String? nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;
    return ProductQuery(
      categoryId: nonEmpty(params['category']),
      text: params['q'] ?? '',
      sort: sort,
      priceBands: bands,
      sameDayOnly: params['sameDay'] == '1',
      discountOnly: params['sale'] == '1',
      featuredOnly: params['featured'] == '1',
      cityId: nonEmpty(params['city']),
      giftFor: FirestoreParse.enumOrNull(GiftAudience.values, params['for']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProductQuery &&
      other.categoryId == categoryId &&
      other.text.trim() == text.trim() &&
      other.sort == sort &&
      setEquals(other.priceBands, priceBands) &&
      other.sameDayOnly == sameDayOnly &&
      other.discountOnly == discountOnly &&
      other.featuredOnly == featuredOnly &&
      other.cityId == cityId &&
      other.giftFor == giftFor;

  @override
  int get hashCode => Object.hash(categoryId, text.trim(), sort, Object.hashAllUnordered(priceBands),
      sameDayOnly, discountOnly, featuredOnly, cityId, giftFor);

  @override
  String toString() => 'ProductQuery(${toQueryParameters()})';
}
