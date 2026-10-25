import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/products/data/datasources/product_sources.dart';
import 'package:golden_gift/features/products/data/product_derived.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/products/data/product_search_repository.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A product document with the derived fields `onProductWrite` maintains (SRS §6.4).
Map<String, dynamic> _product({
  required String title,
  required int price,
  int? compareAt,
  List<String> categories = const [],
  List<String> cities = const [],
  String availability = 'sameDay',
  bool featured = false,
  bool active = true,
  int sales = 0,
  required DateTime created,
  List<String> keywords = const [],
  List<GiftAudience> giftFor = const [],
}) {
  final cityKeys = cities.isEmpty ? [ProductKeys.allCities] : cities;
  return {
    'title': title,
    'price': price,
    'compareAtPrice': compareAt,
    'categoryIds': categories,
    'availableCities': cities,
    'availability': availability,
    'isFeatured': featured,
    'isActive': active,
    'salesCount': sales,
    'createdAt': created,
    'searchKeywords': keywords,
    'hasDiscount': compareAt != null && compareAt > price,
    'priceBand': PriceBands.bandOf(price),
    'cityKeys': cityKeys,
    'catCityKeys': [for (final c in categories) for (final city in cityKeys) '$c|$city'],
    'giftFor': giftFor.map((a) => a.name).toList(),
    'forKeys': ProductDerived.fieldsFor(
      price: price,
      categoryIds: categories,
      availableCities: cities,
      giftFor: giftFor,
    )['forKeys'],
  };
}

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  final docs = {
    'frame': _product(title: 'Frame', price: 35000, compareAt: 40000, categories: ['frames', 'love'], featured: true, sales: 50, created: DateTime(2026, 1, 5), keywords: ['wooden', 'frame'], giftFor: [GiftAudience.men, GiftAudience.women]),
    'mug': _product(title: 'Mug', price: 12000, categories: ['mugs'], sales: 300, created: DateTime(2026, 1, 9), keywords: ['mug', 'photo'], giftFor: GiftAudience.values),
    'breakfast': _product(title: 'Breakfast', price: 45000, categories: ['breakfast'], cities: ['erbil', 'duhok'], availability: 'preparationDays', sales: 120, created: DateTime(2026, 1, 7), keywords: ['breakfast', 'box'], giftFor: [GiftAudience.women]),
    'necklace': _product(title: 'Necklace', price: 220000, compareAt: 260000, categories: ['jewelry-and-watches', 'love'], featured: true, sales: 10, created: DateTime(2026, 1, 8), keywords: ['name', 'necklace'], giftFor: [GiftAudience.women]),
    'hidden': _product(title: 'Hidden', price: 10000, categories: ['mugs'], active: false, created: DateTime(2026, 1, 10), keywords: ['mug'], giftFor: [GiftAudience.men]),
    'frame-baghdad': _product(title: 'Frame Baghdad', price: 30000, categories: ['frames'], cities: ['baghdad'], sales: 5, created: DateTime(2026, 1, 6), keywords: ['frame'], giftFor: [GiftAudience.companies]),
  };
  for (final e in docs.entries) {
    await db.collection('products').doc(e.key).set(e.value);
  }
  return db;
}

Future<List<String>> _ids(FirestoreProductSource s, ProductQuery q) async =>
    (await s.fetch(q)).items.map((p) => p.id).toList();

void main() {
  group('FirestoreProductSource — one query per filter combination (SRS §5.8)', () {
    late FirestoreProductSource source;
    setUp(() async => source = FirestoreProductSource(await _seed()));

    test('default: active products, newest first', () async {
      expect(await _ids(source, const ProductQuery()), ['mug', 'necklace', 'breakfast', 'frame-baghdad', 'frame']);
    });

    test('category', () async {
      expect(await _ids(source, const ProductQuery(categoryId: 'frames')), ['frame-baghdad', 'frame']);
    });

    test('city: products for that city plus unrestricted ones', () async {
      expect(await _ids(source, const ProductQuery(cityId: 'erbil')), ['mug', 'necklace', 'breakfast', 'frame']);
    });

    test('category + city uses the combined keys', () async {
      expect(await _ids(source, const ProductQuery(categoryId: 'frames', cityId: 'erbil')), ['frame']);
      expect(await _ids(source, const ProductQuery(categoryId: 'frames', cityId: 'baghdad')), ['frame-baghdad', 'frame']);
    });

    test('same day, on sale, featured', () async {
      expect(await _ids(source, const ProductQuery(sameDayOnly: true)), isNot(contains('breakfast')));
      expect(await _ids(source, const ProductQuery(discountOnly: true)), ['necklace', 'frame']);
      expect(await _ids(source, const ProductQuery(featuredOnly: true)), ['necklace', 'frame']);
    });

    test('price bands', () async {
      expect(await _ids(source, const ProductQuery(priceBands: {0})), ['mug']);
      expect(await _ids(source, const ProductQuery(priceBands: {1, 4})), ['necklace', 'breakfast', 'frame-baghdad', 'frame']);
      // all bands selected = no price filter
      expect((await _ids(source, const ProductQuery(priceBands: {0, 1, 2, 3, 4}))).length, 5);
    });

    test('sorts', () async {
      expect(await _ids(source, const ProductQuery(sort: ProductSort.popular)), ['mug', 'breakfast', 'frame', 'necklace', 'frame-baghdad']);
      expect(await _ids(source, const ProductQuery(sort: ProductSort.priceLowHigh)), ['mug', 'frame-baghdad', 'frame', 'breakfast', 'necklace']);
      expect((await _ids(source, const ProductQuery(sort: ProductSort.priceHighLow))).first, 'necklace');
    });

    test('gift type alone and with category / city / price / sale is one query on forKeys (SRS §5.8a)', () async {
      expect(await _ids(source, const ProductQuery(giftFor: GiftAudience.women)), ['mug', 'necklace', 'breakfast', 'frame']);
      expect(await _ids(source, const ProductQuery(giftFor: GiftAudience.companies)), ['mug', 'frame-baghdad']);
      expect(await _ids(source, const ProductQuery(giftFor: GiftAudience.companies, categoryId: 'frames')), ['frame-baghdad']);
      expect(await _ids(source, const ProductQuery(giftFor: GiftAudience.companies, cityId: 'erbil')), ['mug']);
      expect(await _ids(source, const ProductQuery(giftFor: GiftAudience.women, categoryId: 'frames', cityId: 'erbil')), ['frame']);
      expect(await _ids(source, const ProductQuery(giftFor: GiftAudience.women, categoryId: 'love', priceBands: {4}, discountOnly: true)),
          ['necklace']);
      expect(await _ids(source, const ProductQuery(giftFor: GiftAudience.men, sort: ProductSort.priceHighLow)), ['frame', 'mug']);
    });

    test('paging continues after the last document', () async {
      final first = await source.fetch(const ProductQuery(), pageSize: 2);
      expect(first.items.map((p) => p.id), ['mug', 'necklace']);
      expect(first.hasMore, isTrue);
      final second = await source.fetch(const ProductQuery(), after: first.cursor as dynamic, pageSize: 2);
      expect(second.items.map((p) => p.id), ['breakfast', 'frame-baghdad']);
      final third = await source.fetch(const ProductQuery(), after: second.cursor as dynamic, pageSize: 2);
      expect(third.items.map((p) => p.id), ['frame']);
      expect(third.hasMore, isFalse);
    });

    test('text fallback searches keywords and reports dropped category/city filters', () async {
      final page = await source.fetch(const ProductQuery(text: 'Frame', categoryId: 'love'));
      expect(page.items.map((p) => p.id).toSet(), {'frame', 'frame-baghdad'});
      expect(page.ignoredFilters, isTrue);
      expect((await source.fetch(const ProductQuery(text: 'Frame', giftFor: GiftAudience.men))).ignoredFilters, isTrue);
      final plain = await source.fetch(const ProductQuery(text: 'mug'));
      expect(plain.items.map((p) => p.id), ['mug']); // inactive "hidden" excluded
      expect(plain.ignoredFilters, isFalse);
    });
  });

  group('AlgoliaProductSource', () {
    const settings = SearchSettings(algoliaAppId: 'APP', algoliaSearchKey: 'search-key');

    test('filters mirror the Firestore query', () {
      expect(
        AlgoliaProductSource.filtersFor(const ProductQuery(
            categoryId: 'frames', cityId: 'erbil', sameDayOnly: true, discountOnly: true, featuredOnly: true, priceBands: {2, 1})),
        'isActive:true AND categoryIds:"frames" AND (cityKeys:"erbil" OR cityKeys:"all") AND '
        'availability:"sameDay" AND hasDiscount:true AND isFeatured:true AND (priceBand=1 OR priceBand=2)',
      );
      expect(AlgoliaProductSource.filtersFor(const ProductQuery()), 'isActive:true');
      expect(AlgoliaProductSource.filtersFor(const ProductQuery(giftFor: GiftAudience.companies)),
          'isActive:true AND giftFor:"companies"');
    });

    test('replica per sort', () {
      final s = AlgoliaProductSource(http.Client(), settings);
      expect(s.indexFor(ProductSort.relevance), 'products');
      expect(s.indexFor(ProductSort.priceHighLow), 'products_price_desc');
    });

    test('sends a normalized query with the search-only key and maps hits', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'nbPages': 3,
            'hits': [
              {'objectID': 'p1', 'title': 'Mug', 'titleKu': 'کوپ', 'price': 12000, 'compareAtPrice': 15000,
               'images': ['https://x/1.jpg'], 'colorDots': ['#000000', '#FFFFFF'], 'createdAt': 1767225600},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final page = await AlgoliaProductSource(client, settings)
          .fetch(const ProductQuery(text: '  كوب  ', sort: ProductSort.popular), page: 1);

      // Hostnames are case-insensitive; Uri lower-cases them.
      expect(sent.url.toString(), 'https://app-dsn.algolia.net/1/indexes/products_popular/query');
      expect(sent.headers['X-Algolia-Application-Id'], 'APP');
      expect(sent.headers['X-Algolia-API-Key'], 'search-key');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['query'], 'کوب'); // ك → ک, trimmed
      expect(body['page'], 1);
      expect(body['hitsPerPage'], 20);

      final p = page.items.single;
      expect(p.id, 'p1');
      expect(p.title.resolve('ckb'), 'کوپ');
      expect(p.discountPercent, 20);
      expect(p.colorDots, ['#000000', '#FFFFFF']);
      expect(p.createdAt, DateTime.fromMillisecondsSinceEpoch(1767225600 * 1000));
      expect(page.hasMore, isTrue);
      expect(page.cursor, 2);
    });

    test('an HTTP error is an exception (the repository then falls back)', () async {
      final client = MockClient((_) async => http.Response('{"message":"Invalid API key"}', 403));
      expect(() => AlgoliaProductSource(client, settings).fetch(const ProductQuery(text: 'mug')),
          throwsA(isA<AlgoliaException>()));
    });
  });

  group('ProductSearchRepository engine choice', () {
    late FakeFirebaseFirestore db;
    setUp(() async => db = await _seed());

    ProductSearchRepository repo(SearchSettings settings, http.Client client) => ProductSearchRepository(
          firestore: FirestoreProductSource(db),
          searchSettings: () async => settings,
          httpClient: client,
        );

    final algoliaOk = MockClient((_) async => http.Response(
        jsonEncode({'nbPages': 1, 'hits': [{'objectID': 'from-algolia', 'title': 'A', 'price': 1000}]}), 200));
    final algoliaDown = MockClient((_) async => http.Response('down', 503));
    const configured = SearchSettings(algoliaAppId: 'APP', algoliaSearchKey: 'k');

    test('text + Algolia configured → Algolia', () async {
      final page = await repo(configured, algoliaOk).fetch(const ProductQuery(text: 'mug'));
      expect(page.items.single.id, 'from-algolia');
      expect((page.cursor as ProductCursor).engine, SearchEngine.algolia);
    });

    test('text + Algolia failing → Firestore keywords', () async {
      final page = await repo(configured, algoliaDown).fetch(const ProductQuery(text: 'mug'));
      expect(page.items.single.id, 'mug');
      expect((page.cursor as ProductCursor).engine, SearchEngine.firestore);
    });

    test('text without Algolia settings → Firestore, flags dropped filters', () async {
      final page = await repo(const SearchSettings(), algoliaOk).fetch(const ProductQuery(text: 'frame', cityId: 'erbil'));
      expect(page.ignoredFilters, isTrue);
      expect((page.cursor as ProductCursor).engine, SearchEngine.firestore);
    });

    test('browsing never calls Algolia', () async {
      var calls = 0;
      final counting = MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      await repo(configured, counting).fetch(const ProductQuery(categoryId: 'frames'));
      expect(calls, 0);
    });
  });
}
