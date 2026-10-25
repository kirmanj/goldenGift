import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/category_model.dart';
import '../../../categories/presentation/providers/categories_providers.dart';
import '../../../categories/presentation/widgets/coming_soon_category.dart';
import '../../data/product_query.dart';
import '../providers/product_list_controller.dart';
import '../widgets/product_category_chips.dart';
import '../widgets/product_filter_sheet.dart';
import '../widgets/product_list_slivers.dart';

/// Products list (SRS §5.8, IMG_4481 / 4482 / 4495): search (debounced
/// 400 ms) + filter sheet, category chips, then an infinite 2-column grid
/// (20 per page) with pull-to-refresh.
///
/// The current [ProductQuery] lives in this screen's state; every change
/// (text, chip, filter sheet) watches the list controller with the new query.
///
/// Coming soon gate (SRS §5.7a): when the query's category — or its parent —
/// is coming soon, the screen shows [ComingSoonCategoryPage] instead, so every
/// entry point (tiles, chips, banners, deep links) lands on it. A category
/// list waits for the categories before querying products, so no grid
/// flashes first and no product reads are spent on a coming-soon category.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key, this.initialQuery = const ProductQuery(), this.focusSearch = false});

  /// From the route's query parameters (see ProductQuery.fromQueryParameters).
  final ProductQuery initialQuery;

  /// Opened from Home's search bar: focus the search field right away.
  final bool focusSearch;

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  late ProductQuery _query = widget.initialQuery;
  late final _searchController = TextEditingController(text: widget.initialQuery.text);
  final _scrollController = ScrollController();

  /// The list shown before a chip opened a coming-soon category: Back
  /// returns to it instead of leaving the screen.
  ProductQuery? _beforeComingSoon;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setQuery(ProductQuery query) {
    if (query == _query) return;
    setState(() => _query = query);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _onSearch(String text) {
    var query = _query.copyWith(text: text);
    // "Best match" only means something for a text search.
    if (!query.hasText && query.sort == ProductSort.relevance) query = query.copyWith(clearSort: true);
    _setQuery(query);
  }

  void _onCategory(String? id) {
    final categories = ref.read(allCategoriesProvider).valueOrNull;
    if (comingSoonCategoryIn(categories, id) != null && comingSoonCategoryIn(categories, _query.categoryId) == null) {
      _beforeComingSoon = _query;
    }
    _setQuery(id == null ? _query.copyWith(clearCategory: true) : _query.copyWith(categoryId: id));
  }

  /// "Explore other categories" on the coming-soon page: that category, here.
  void _openCategory(CategoryModel category) {
    _beforeComingSoon = null;
    _setQuery(_query.copyWith(categoryId: category.id));
  }

  /// Back from the coming-soon page: the previous list, else pop, else Home
  /// (opened by a deep link, nothing to pop).
  void _leaveComingSoon() {
    final previous = _beforeComingSoon;
    if (previous != null) {
      _beforeComingSoon = null;
      _setQuery(previous);
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go(AppRoutes.mainTab(0));
    }
  }

  Future<void> _openFilters() async {
    final result = await showProductFilterSheet(context, _query);
    if (result != null && mounted) _setQuery(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = _query;
    final categories = ref.watch(allCategoriesProvider);
    final comingSoon = comingSoonCategoryIn(categories.valueOrNull, query.categoryId);
    if (comingSoon != null) {
      return PopScope(
        canPop: _beforeComingSoon == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leaveComingSoon();
        },
        child: ComingSoonCategoryPage(info: comingSoon, onBack: _leaveComingSoon, onCategorySelected: _openCategory),
      );
    }
    // A category list waits for the categories (cache-first, fast); if they
    // fail, the products load anyway.
    final waitForCategories = query.categoryId != null && !categories.hasValue && !categories.hasError;
    final state = waitForCategories ? const ProductListState() : watchProductList(ref, query);
    // Sort alone never empties a list, so only real filters offer "Reset filters".
    final canReset = query.copyWith(clearSort: true).activeFilterCount > 0;
    const h = AppSpacing.screenHorizontal;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        title: l10n.products,
        onCartTap: () => context.go(AppRoutes.mainTab(1)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(h, AppSpacing.sm, h, 0),
            child: GGSearchBar(
              hint: l10n.searchForProduct,
              controller: _searchController,
              autofocus: widget.focusSearch,
              onChanged: _onSearch,
              onSubmitted: _onSearch,
              onFilterTap: _openFilters,
              filterActive: query.activeFilterCount > 0,
            ),
          ),
          ProductCategoryChips(selectedId: query.categoryId, onSelected: _onCategory),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.gold(context),
              backgroundColor: AppColors.card(context),
              onRefresh: () => refreshProductList(ref, query),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (state.ignoredFilters)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(h, AppSpacing.md, h, 0),
                      sliver: SliverToBoxAdapter(
                        child: InfoBanner(message: l10n.searchFallbackNote),
                      ),
                    ),
                  if (state.fromCache)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(h, AppSpacing.md, h, 0),
                      sliver: SliverToBoxAdapter(
                        child: Align(alignment: AlignmentDirectional.centerStart, child: OfflineChip()),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      h,
                      AppSpacing.md,
                      h,
                      AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: ProductListSlivers(
                      state: state,
                      fillRemaining: true,
                      skeletonCount: 6,
                      onRetry: () => refreshProductList(ref, query),
                      onLoadMore: () => loadMoreProducts(ref, query),
                      empty: EmptyState(
                        icon: Icons.search_off_rounded,
                        title: l10n.noProductsTitle,
                        subtitle: l10n.noProductsBody,
                        ctaLabel: canReset ? l10n.resetFilters : null,
                        onCta: canReset ? () => _setQuery(query.withoutFilters()) : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
