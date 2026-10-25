import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/features/products/data/datasources/product_sources.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/products/data/product_search_repository.dart';
import 'package:golden_gift/features/products/presentation/providers/product_list_controller.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

ProductModel _p(String id) => ProductModel(id: id, title: LocalizedText(id), storeId: 's', price: 1000);

/// Serves pages of [total] products, [pageSize] each, optionally failing once.
class _PagedRepo implements ProductSearchRepository {
  _PagedRepo(this.total, {this.failFirst = false, this.failSecondPage = false});
  final int total;
  bool failFirst;
  bool failSecondPage;
  final calls = <int>[];

  @override
  Future<ProductPage> fetch(ProductQuery query, {ProductCursor? cursor, int pageSize = 20}) async {
    final start = (cursor?.value as int?) ?? 0;
    calls.add(start);
    if (failFirst && start == 0) {
      failFirst = false;
      throw Exception('offline');
    }
    if (failSecondPage && start > 0) {
      failSecondPage = false;
      throw Exception('flaky');
    }
    final end = (start + pageSize).clamp(0, total);
    return ProductPage(
      items: [for (var i = start; i < end; i++) _p('p$i')],
      hasMore: end < total,
      cursor: ProductCursor(SearchEngine.firestore, end),
    );
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('loads the first page, then appends pages until there are no more', () async {
    final repo = _PagedRepo(45);
    final c = ProductListController(repo, const ProductQuery());
    expect(c.state.isLoading, isTrue);
    await _settle();
    expect(c.state.items.length, 20);
    expect(c.state.hasMore, isTrue);

    await c.loadMore();
    await c.loadMore();
    expect(c.state.items.length, 45);
    expect(c.state.hasMore, isFalse);

    await c.loadMore(); // nothing left: no request
    expect(repo.calls, [0, 20, 40]);
  });

  test('concurrent loadMore calls request a page once', () async {
    final repo = _PagedRepo(60);
    final c = ProductListController(repo, const ProductQuery());
    await _settle();
    await Future.wait([c.loadMore(), c.loadMore(), c.loadMore()]);
    expect(repo.calls, [0, 20]);
  });

  test('first-page error → error state; refresh retries', () async {
    final repo = _PagedRepo(5, failFirst: true);
    final c = ProductListController(repo, const ProductQuery());
    await _settle();
    expect(c.state.error, isNotNull);
    expect(c.state.isLoading, isFalse);
    await c.refresh();
    expect(c.state.error, isNull);
    expect(c.state.items.length, 5);
    expect(c.state.isEmpty, isFalse);
  });

  test('a failing later page keeps the items and can be retried', () async {
    final repo = _PagedRepo(30, failSecondPage: true);
    final c = ProductListController(repo, const ProductQuery());
    await _settle();
    await c.loadMore();
    expect(c.state.items.length, 20);
    expect(c.state.loadMoreError, isNotNull);
    await c.loadMore();
    expect(c.state.items.length, 30);
    expect(c.state.loadMoreError, isNull);
  });

  test('empty result', () async {
    final c = ProductListController(_PagedRepo(0), const ProductQuery());
    await _settle();
    expect(c.state.isEmpty, isTrue);
  });
}
