import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/products/data/product_derived.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/models/product_model.dart';

/// The same fixture is checked by functions/test/productDerived.test.ts: the
/// app's query keys and the server's derived fields must agree (SRS §5.8, §6.4).
void main() {
  final fixture = jsonDecode(File('test/fixtures/product_query_keys.json').readAsStringSync())
      as Map<String, dynamic>;

  group('PriceBands', () {
    test('bounds match the fixture', () {
      expect(PriceBands.bounds, fixture['priceBandBounds']);
    });
    for (final c in (fixture['priceBand'] as List).cast<Map<String, dynamic>>()) {
      test('${c['price']} IQD → band ${c['band']}', () {
        expect(PriceBands.bandOf(c['price'] as int), c['band']);
      });
    }
    test('every band range contains exactly its prices', () {
      for (var band = 0; band < PriceBands.count; band++) {
        final (min, max) = PriceBands.rangeOf(band);
        expect(PriceBands.bandOf(min), band);
        if (max != null) expect(PriceBands.bandOf(max - 1), band);
      }
      expect(PriceBands.rangeOf(PriceBands.count - 1).$2, isNull);
    });
  });

  group('ProductDerived (same cases as functions/test/productDerived.test.ts)', () {
    for (final c in (fixture['derived'] as List).cast<Map<String, dynamic>>()) {
      final input = c['input'] as Map<String, dynamic>;
      test('$input', () {
        expect(
          ProductDerived.fieldsFor(
            price: input['price'] as int,
            compareAtPrice: input['compareAtPrice'] as int?,
            categoryIds: (input['categoryIds'] as List).cast<String>(),
            availableCities: (input['availableCities'] as List).cast<String>(),
            // Known values only, de-duplicated — as ProductModel.fromMap reads them.
            giftFor: giftAudiencesOf(input['giftFor']),
          ),
          c['output'],
        );
      });
    }
  });

  group('ProductKeys', () {
    for (final c in (fixture['queryKeys'] as List).cast<Map<String, dynamic>>()) {
      test('${c['category']} + ${c['city']}', () {
        expect(ProductKeys.cityAnyOf(c['city'] as String), c['cityAnyOf']);
        expect(ProductKeys.catCityAnyOf(c['category'] as String, c['city'] as String), c['catCityAnyOf']);
      });
    }
    for (final c in (fixture['forQueryKeys'] as List).cast<Map<String, dynamic>>()) {
      test('gift for ${c['audience']} + ${c['category']} + ${c['city']}', () {
        expect(
          ProductKeys.forAnyOf(GiftAudience.values.byName(c['audience'] as String),
              categoryId: c['category'] as String?, cityId: c['city'] as String?),
          c['forAnyOf'],
        );
      });
    }
  });

  group('ProductQuery', () {
    const full = ProductQuery(
      categoryId: 'frames',
      text: 'wooden frame',
      sort: ProductSort.priceLowHigh,
      priceBands: {2, 1},
      sameDayOnly: true,
      discountOnly: true,
      featuredOnly: true,
      cityId: 'erbil',
      giftFor: GiftAudience.women,
    );

    test('round-trips through route query parameters', () {
      final params = full.toQueryParameters();
      expect(params['price'], '1,2');
      expect(ProductQuery.fromQueryParameters(params), full);
    });

    test('bad parameters are ignored, not fatal', () {
      final q = ProductQuery.fromQueryParameters(const {'sort': 'cheapest', 'price': '1,x,9', 'category': ''});
      expect(q.sort, isNull);
      expect(q.priceBands, {1});
      expect(q.categoryId, isNull);
    });

    test('value equality (it is a provider family key)', () {
      expect(const ProductQuery(priceBands: {1, 2}), const ProductQuery(priceBands: {2, 1}));
      expect(const ProductQuery(text: ' mug '), const ProductQuery(text: 'mug'));
      expect(const ProductQuery(priceBands: {1, 2}).hashCode, const ProductQuery(priceBands: {2, 1}).hashCode);
      expect(const ProductQuery(categoryId: 'a'), isNot(const ProductQuery(categoryId: 'b')));
    });

    test('default sort: best match for text, newest otherwise', () {
      expect(const ProductQuery().effectiveSort, ProductSort.newest);
      expect(const ProductQuery(text: 'mug').effectiveSort, ProductSort.relevance);
      expect(const ProductQuery(text: 'mug', sort: ProductSort.popular).effectiveSort, ProductSort.popular);
    });

    test('filter badge counts sheet choices only', () {
      expect(const ProductQuery(categoryId: 'frames', text: 'x', featuredOnly: true).activeFilterCount, 0);
      expect(full.activeFilterCount, 6); // sort, price, sameDay, sale, city, gift for
      expect(const ProductQuery(priceBands: {0, 1, 2, 3, 4}).activeFilterCount, 0); // all bands = no filter
    });

    test('withoutFilters keeps category, text and featured', () {
      expect(full.withoutFilters(),
          const ProductQuery(categoryId: 'frames', text: 'wooden frame', featuredOnly: true));
    });

    test('copyWith can clear nullable fields', () {
      expect(full.copyWith(clearCategory: true, clearCity: true, clearSort: true).categoryId, isNull);
      expect(full.copyWith(clearCity: true).cityId, isNull);
      expect(full.copyWith(clearGiftFor: true).giftFor, isNull);
    });

    test('gift type: `for=` parameter, unknown values ignored', () {
      expect(full.toQueryParameters()['for'], 'women');
      expect(ProductQuery.fromQueryParameters(const {'for': 'companies'}).giftFor, GiftAudience.companies);
      expect(ProductQuery.fromQueryParameters(const {'for': 'aliens'}).giftFor, isNull);
      expect(const ProductQuery(giftFor: GiftAudience.men), isNot(const ProductQuery(giftFor: GiftAudience.women)));
    });
  });
}
