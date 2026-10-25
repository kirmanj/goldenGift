import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../products/data/product_query.dart';
import '../providers/categories_providers.dart';
import '../widgets/category_grid.dart';

/// All Categories (SRS §5.7, IMG_4496–4500): app bar with cart, a pill search
/// that filters locally in every language, and a 3-column tile grid. A tile
/// opens the products list filtered by that category.
class AllCategoriesScreen extends ConsumerStatefulWidget {
  const AllCategoriesScreen({super.key});

  @override
  ConsumerState<AllCategoriesScreen> createState() => _AllCategoriesScreenState();
}

class _AllCategoriesScreenState extends ConsumerState<AllCategoriesScreen> {
  String _search = '';

  void _onSearch(String value) {
    if (value != _search) setState(() => _search = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final categories = ref.watch(allCategoriesProvider);
    const h = AppSpacing.screenHorizontal;
    final listPadding = EdgeInsets.fromLTRB(h, AppSpacing.sm, h, AppSpacing.lg + MediaQuery.paddingOf(context).bottom);

    final Widget body;
    if (categories.hasValue) {
      final visible = filterCategories(categories.value!, _search);
      body = visible.isEmpty
          ? _FillScroll(
              child: EmptyState(icon: Icons.search_off_rounded, title: l10n.noCategoriesMatch),
            )
          : CategoryGrid(
              categories: visible,
              all: categories.value,
              padding: listPadding,
              onTap: (category) => context.push(AppRoutes.productsFor(ProductQuery(categoryId: category.id))),
            );
    } else if (categories.hasError) {
      body = _FillScroll(
        child: ErrorState(onRetry: () => ref.invalidate(allCategoriesProvider)),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          padding: listPadding,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: categoryGridDelegate(
            context,
            constraints.maxWidth - listPadding.horizontal,
            columns: CategoryGrid.columns,
          ),
          itemCount: 12,
          itemBuilder: (_, __) => const CategoryTileSkeleton(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        title: l10n.allCategories,
        onCartTap: () => context.go(AppRoutes.mainTab(1)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(h, AppSpacing.sm, h, AppSpacing.md),
            child: GGSearchBar(
              hint: l10n.searchForCategory,
              // Local filtering is instant; no need to debounce.
              debounce: Duration.zero,
              onChanged: _onSearch,
              onSubmitted: _onSearch,
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Centres a state widget in the remaining space, scrolling when it doesn't
/// fit (keyboard open, large text).
class _FillScroll extends StatelessWidget {
  const _FillScroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
    );
  }
}
