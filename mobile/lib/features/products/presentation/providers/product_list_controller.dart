import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/product_model.dart';
import '../../data/product_query.dart';
import '../../data/product_search_repository.dart';

class ProductListState {
  const ProductListState({
    this.items = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.loadMoreError,
    this.fromCache = false,
    this.ignoredFilters = false,
    this.cursor,
  });

  final List<ProductModel> items;

  /// First page loading (show skeletons).
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;

  /// First page failed (show ErrorState with Retry).
  final Object? error;

  /// A later page failed (keep the items, offer retry at the bottom).
  final Object? loadMoreError;
  final bool fromCache;

  /// Text search fell back to Firestore and dropped the category / city filter.
  final bool ignoredFilters;
  final ProductCursor? cursor;

  bool get isEmpty => !isLoading && error == null && items.isEmpty;

  ProductListState copyWith({
    List<ProductModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
    bool? fromCache,
    bool? ignoredFilters,
    ProductCursor? cursor,
  }) =>
      ProductListState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
        loadMoreError: clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
        fromCache: fromCache ?? this.fromCache,
        ignoredFilters: ignoredFilters ?? this.ignoredFilters,
        cursor: cursor ?? this.cursor,
      );
}

/// Infinite products list, 20 per page (SRS §5.4 Discover, §5.8). One
/// instance per [ProductQuery]; pull-to-refresh calls [refresh].
class ProductListController extends StateNotifier<ProductListState> {
  ProductListController(this._repository, this.query, {this.pageSize = defaultPageSize})
      : super(const ProductListState()) {
    _loadFirst();
  }

  static const defaultPageSize = 20;

  final ProductSearchRepository _repository;
  final ProductQuery query;
  final int pageSize;
  int _generation = 0;

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    try {
      final page = await _repository.fetch(query, pageSize: pageSize);
      if (!mounted || generation != _generation) return;
      state = ProductListState(
        items: page.items,
        isLoading: false,
        hasMore: page.hasMore,
        fromCache: page.fromCache,
        ignoredFilters: page.ignoredFilters,
        cursor: page.cursor as ProductCursor?,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = ProductListState(isLoading: false, hasMore: false, error: e);
    }
  }

  /// Next page; ignored while a page is loading or when there is no more.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore || state.error != null) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    try {
      final page = await _repository.fetch(query, cursor: state.cursor, pageSize: pageSize);
      if (!mounted || generation != _generation) return;
      final seen = {for (final p in state.items) p.id};
      state = state.copyWith(
        items: [...state.items, ...page.items.where((p) => !seen.contains(p.id))],
        isLoadingMore: false,
        hasMore: page.hasMore,
        fromCache: page.fromCache,
        cursor: page.cursor as ProductCursor?,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(isLoadingMore: false, loadMoreError: e);
    }
  }

  /// Pull-to-refresh / Retry: reloads from the first page.
  Future<void> refresh() {
    state = state.items.isEmpty ? const ProductListState() : state.copyWith(clearError: true);
    return _loadFirst();
  }
}

final productListControllerProvider =
    StateNotifierProvider.autoDispose.family<ProductListController, ProductListState, ProductQuery>(
  (ref, query) => ProductListController(ref.watch(productSearchRepositoryProvider), query),
);
