import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/providers/app_settings_providers.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../models/app_settings_model.dart';
import 'datasources/product_sources.dart';
import 'product_query.dart';

enum SearchEngine { firestore, algolia }

/// Cursor that remembers which engine produced it.
class ProductCursor {
  const ProductCursor(this.engine, this.value);
  final SearchEngine engine;
  final Object? value;
}

/// Picks the engine per query (SRS §5.8): text → Algolia when configured,
/// falling back to Firestore keywords if Algolia is missing or fails;
/// everything else → one Firestore query.
class ProductSearchRepository {
  ProductSearchRepository({
    required FirestoreProductSource firestore,
    required Future<SearchSettings> Function() searchSettings,
    required http.Client httpClient,
  })  : _firestore = firestore,
        _searchSettings = searchSettings,
        _http = httpClient;

  final FirestoreProductSource _firestore;
  final Future<SearchSettings> Function() _searchSettings;
  final http.Client _http;

  Future<ProductPage> fetch(ProductQuery query, {ProductCursor? cursor, int pageSize = 20}) async {
    if (query.hasText && cursor?.engine != SearchEngine.firestore) {
      final settings = await _searchSettingsOrDefault();
      if (settings.isConfigured) {
        try {
          final page = await AlgoliaProductSource(_http, settings)
              .fetch(query, page: (cursor?.value as int?) ?? 0, pageSize: pageSize);
          return _wrap(page, SearchEngine.algolia);
        } catch (e) {
          // SRS §5.8: if the search service is unavailable, fall back to keywords.
          if (kDebugMode) debugPrint('algolia failed, using Firestore keywords: $e');
          if (cursor != null) rethrow; // don't mix engines mid-list
        }
      }
    }
    final page = await _firestore.fetch(
      query,
      after: cursor?.value as DocumentSnapshot<Object?>?,
      pageSize: pageSize,
    );
    return _wrap(page, SearchEngine.firestore);
  }

  Future<SearchSettings> _searchSettingsOrDefault() async {
    try {
      return await _searchSettings().timeout(const Duration(seconds: 3));
    } catch (_) {
      return const SearchSettings();
    }
  }

  ProductPage _wrap(ProductPage page, SearchEngine engine) => ProductPage(
        items: page.items,
        hasMore: page.hasMore,
        cursor: ProductCursor(engine, page.cursor),
        fromCache: page.fromCache,
        ignoredFilters: engine == SearchEngine.firestore && page.ignoredFilters,
      );
}

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final firestoreProductSourceProvider =
    Provider<FirestoreProductSource>((ref) => FirestoreProductSource(ref.watch(firestoreProvider)));

final productSearchRepositoryProvider = Provider<ProductSearchRepository>((ref) => ProductSearchRepository(
      firestore: ref.watch(firestoreProductSourceProvider),
      searchSettings: () => ref.read(searchSettingsProvider.future),
      httpClient: ref.watch(httpClientProvider),
    ));
