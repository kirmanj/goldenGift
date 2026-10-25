import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/utils/search_tokenizer.dart';
import '../../../../models/app_settings_model.dart';
import '../../../../models/product_model.dart';
import '../product_query.dart';

/// One page of a products list.
class ProductPage {
  const ProductPage({
    required this.items,
    required this.hasMore,
    this.cursor,
    this.fromCache = false,
    this.ignoredFilters = false,
  });

  final List<ProductModel> items;
  final bool hasMore;

  /// Opaque position to continue from (engine-specific).
  final Object? cursor;

  /// Served from the offline cache (SRS §4.8 "offline" chip).
  final bool fromCache;

  /// The text-search fallback had to drop the category / city filter
  /// (Firestore allows one array filter per query; Algolia is not configured).
  final bool ignoredFilters;
}

/// Browse queries (and the text-search fallback) straight from Firestore
/// (SRS §5.8 AC): every filter combination is ONE query with at most one array
/// filter, thanks to the derived fields `cityKeys` / `catCityKeys` / `priceBand`.
class FirestoreProductSource {
  FirestoreProductSource(this._db);
  final FirebaseFirestore _db;

  /// Firestore allows ≤ 30 disjunctions: ≤ 5 keyword tokens × ≤ 4 price bands.
  static const maxKeywordTokens = 5;

  /// True when this query can't apply the category / city / gift-type filter (text fallback).
  static bool dropsArrayFilters(ProductQuery q) =>
      q.hasText && (q.categoryId != null || q.cityId != null || q.giftFor != null);

  Query<Map<String, dynamic>> buildQuery(ProductQuery q) {
    Query<Map<String, dynamic>> query =
        _db.collection(FirestorePaths.products).where('isActive', isEqualTo: true);

    // Exactly one array filter.
    final category = q.categoryId;
    final city = q.cityId;
    final audience = q.giftFor;
    if (q.hasText) {
      final tokens = SearchTokenizer.tokenize(q.text).take(maxKeywordTokens).toList();
      query = query.where('searchKeywords', arrayContainsAny: tokens.isEmpty ? ['\u0000'] : tokens);
    } else if (audience != null) {
      // Gift type (+ category, + city) is one array filter: `forKeys` (SRS §5.8a).
      final keys = ProductKeys.forAnyOf(audience, categoryId: category, cityId: city);
      query = keys.length == 1
          ? query.where('forKeys', arrayContains: keys.single)
          : query.where('forKeys', arrayContainsAny: keys);
    } else if (category != null && city != null) {
      query = query.where('catCityKeys', arrayContainsAny: ProductKeys.catCityAnyOf(category, city));
    } else if (category != null) {
      query = query.where('categoryIds', arrayContains: category);
    } else if (city != null) {
      query = query.where('cityKeys', arrayContainsAny: ProductKeys.cityAnyOf(city));
    }

    if (q.sameDayOnly) query = query.where('availability', isEqualTo: 'sameDay');
    if (q.discountOnly) query = query.where('hasDiscount', isEqualTo: true);
    if (q.featuredOnly) query = query.where('isFeatured', isEqualTo: true);
    if (q.priceBands.isNotEmpty && q.priceBands.length < PriceBands.count) {
      query = query.where('priceBand', whereIn: q.priceBands.toList()..sort());
    }

    return switch (q.effectiveSort) {
      ProductSort.popular || ProductSort.relevance => query.orderBy('salesCount', descending: true),
      ProductSort.newest => query.orderBy('createdAt', descending: true),
      ProductSort.priceLowHigh => query.orderBy('price'),
      ProductSort.priceHighLow => query.orderBy('price', descending: true),
    };
  }

  Future<ProductPage> fetch(ProductQuery q, {DocumentSnapshot<Object?>? after, int pageSize = 20}) async {
    var query = buildQuery(q);
    if (after != null) query = query.startAfterDocument(after);
    query = query.limit(pageSize);
    final snap = await query.get();
    return ProductPage(
      items: [for (final d in snap.docs) ProductModel.fromMap(d.id, d.data())],
      hasMore: snap.docs.length == pageSize,
      cursor: snap.docs.isEmpty ? after : snap.docs.last,
      fromCache: snap.metadata.isFromCache,
      ignoredFilters: dropsArrayFilters(q),
    );
  }
}

/// Text search through Algolia's REST API with the public search-only key
/// (SRS §5.8, §12 item 7). Records are written by `onProductWrite`.
class AlgoliaProductSource {
  AlgoliaProductSource(this._http, this._settings);

  final http.Client _http;
  final SearchSettings _settings;

  static const timeout = Duration(seconds: 6);

  /// Replica per sort order (configured by functions/scripts/algolia-setup.ts).
  String indexFor(ProductSort sort) {
    final base = _settings.indexName;
    return switch (sort) {
      ProductSort.relevance => base,
      ProductSort.newest => '${base}_newest',
      ProductSort.popular => '${base}_popular',
      ProductSort.priceLowHigh => '${base}_price_asc',
      ProductSort.priceHighLow => '${base}_price_desc',
    };
  }

  /// Algolia filter expression equivalent to [FirestoreProductSource.buildQuery].
  static String filtersFor(ProductQuery q) {
    final parts = <String>['isActive:true'];
    if (q.categoryId != null) parts.add('categoryIds:"${q.categoryId}"');
    if (q.cityId != null) {
      parts.add('(${ProductKeys.cityAnyOf(q.cityId!).map((c) => 'cityKeys:"$c"').join(' OR ')})');
    }
    if (q.sameDayOnly) parts.add('availability:"sameDay"');
    if (q.discountOnly) parts.add('hasDiscount:true');
    if (q.featuredOnly) parts.add('isFeatured:true');
    if (q.giftFor != null) parts.add('giftFor:"${q.giftFor!.name}"');
    if (q.priceBands.isNotEmpty && q.priceBands.length < PriceBands.count) {
      parts.add('(${(q.priceBands.toList()..sort()).map((b) => 'priceBand=$b').join(' OR ')})');
    }
    return parts.join(' AND ');
  }

  Future<ProductPage> fetch(ProductQuery q, {int page = 0, int pageSize = 20}) async {
    final uri = Uri.https('${_settings.algoliaAppId}-dsn.algolia.net',
        '/1/indexes/${Uri.encodeComponent(indexFor(q.effectiveSort))}/query');
    final response = await _http
        .post(
          uri,
          headers: {
            'X-Algolia-Application-Id': _settings.algoliaAppId,
            'X-Algolia-API-Key': _settings.algoliaSearchKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            // Same normalization as the indexed `searchText` (ك/ک, ي/ی, diacritics).
            'query': SearchTokenizer.normalize(q.text.trim()),
            'filters': filtersFor(q),
            'page': page,
            'hitsPerPage': pageSize,
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw AlgoliaException(response.statusCode, response.body);
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final hits = (body['hits'] as List? ?? const []).whereType<Map<String, dynamic>>();
    final nbPages = (body['nbPages'] as num?)?.toInt() ?? 0;
    return ProductPage(
      items: [
        for (final hit in hits)
          ProductModel.fromMap(hit['objectID'] as String, {
            ...hit,
            // Records store epoch seconds; the model reads millis.
            if (hit['createdAt'] is num) 'createdAt': ((hit['createdAt'] as num) * 1000).round(),
          }),
      ],
      hasMore: page + 1 < nbPages,
      cursor: page + 1,
    );
  }
}

class AlgoliaException implements Exception {
  AlgoliaException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'AlgoliaException($statusCode)';
}
