import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/services/callable.dart';
import 'package:golden_gift/features/ai_search/data/ai_search_repository.dart';
import 'package:golden_gift/features/products/data/datasources/product_sources.dart';
import 'package:golden_gift/features/products/data/product_search_repository.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:http/http.dart' as http;

Future<void> product(FakeFirebaseFirestore db, String id, String title, int price, {bool active = true}) =>
    db.doc(FirestorePaths.productDoc(id)).set({
      'title': title,
      'storeId': 's1',
      'price': price,
      'isActive': active,
      'searchKeywords': title.toLowerCase().split(' '),
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      'salesCount': 0,
    });

AiSearchRepository repo(FakeFirebaseFirestore db, CallableInvoker call) => AiSearchRepository(
      db,
      call,
      ProductSearchRepository(
        firestore: FirestoreProductSource(db),
        searchSettings: () async => const SearchSettings(),
        httpClient: http.Client(),
      ),
    );


void main() {
  test('keeps the AI ranking and reasons, drops unknown or inactive products', () async {
    final db = FakeFirebaseFirestore();
    await product(db, 'p1', 'Plant pot', 30000);
    await product(db, 'p2', 'Graduation frame', 45000);
    await product(db, 'p3', 'Old mug', 10000, active: false);
    final sent = <Map<String, dynamic>>[];
    final result = await repo(db, (name, data) async {
      expect(name, 'aiGiftSearch');
      sent.add(data);
      return {
        'searchId': 's1',
        'results': [
          {'productId': 'p2', 'reason': 'For her graduation'},
          {'productId': 'missing', 'reason': 'x'},
          {'productId': 'p3', 'reason': 'inactive'},
          {'productId': 'p1', 'reason': 'She loves plants'},
        ],
      };
    }).search('  my sister graduates, loves plants  ', locale: 'en', budgetMax: 50000);

    expect(sent.single, {'query': 'my sister graduates, loves plants', 'locale': 'en', 'budgetMax': 50000});
    expect(result.usedFallback, isFalse);
    expect(result.searchId, 's1');
    expect(result.suggestions.map((s) => s.product.id), ['p2', 'p1']);
    expect(result.suggestions.first.reason, 'For her graduation');
  });

  test('falls back to keyword search (within budget) when the function fails', () async {
    final db = FakeFirebaseFirestore();
    await product(db, 'p1', 'Plant pot', 30000);
    await product(db, 'p2', 'Plant terrarium', 90000);
    final result = await repo(db, (_, __) async => throw FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND'))
        .search('plant', locale: 'ar', budgetMax: 50000);
    expect(result.usedFallback, isTrue);
    expect(result.rateLimited, isFalse);
    expect(result.suggestions.map((s) => s.product.id), ['p1']);
  });

  test('rate limit is reported and still shows fallback results', () async {
    final db = FakeFirebaseFirestore();
    await product(db, 'p1', 'Plant pot', 30000);
    final result =
        await repo(db, (_, __) async => throw FirebaseFunctionsException(code: 'resource-exhausted', message: 'limit'))
            .search('plant', locale: 'ckb');
    expect(result.rateLimited, isTrue);
    expect(result.suggestions, hasLength(1));
  });

  test('empty query does nothing', () async {
    var called = false;
    final result = await repo(FakeFirebaseFirestore(), (_, __) async {
      called = true;
      return null;
    }).search('   ', locale: 'en');
    expect(called, isFalse);
    expect(result.suggestions, isEmpty);
  });
}
