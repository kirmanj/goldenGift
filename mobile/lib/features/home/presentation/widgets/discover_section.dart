import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../categories/presentation/providers/categories_providers.dart';
import '../../../categories/presentation/widgets/coming_soon_category.dart';
import '../../../products/data/product_query.dart';
import '../../../products/presentation/widgets/product_list_slivers.dart';
import '../providers/home_providers.dart';
import 'home_sections.dart';

/// Discover (SRS §5.4 item 12, IMG_4479): "All" + category chips and an
/// infinite 2-column grid of the newest products in the selected category
/// (20 per page; the next page loads as the Home scroll nears the end).
/// The selection is owned by the Home screen so pull-to-refresh can reach it.
/// A coming-soon chip (SRS §5.7a) shows [ComingSoonInlineCard] instead of the
/// grid, without querying products.
class DiscoverSection extends ConsumerWidget {
  const DiscoverSection({super.key, required this.categoryId, required this.onCategoryChanged});

  /// null = All.
  final String? categoryId;
  final ValueChanged<String?> onCategoryChanged;

  static ProductQuery queryFor(String? categoryId) =>
      ProductQuery(categoryId: categoryId, sort: ProductSort.newest);

  /// The selected chip's category when it is coming soon (among the Home categories).
  static ComingSoonCategory? comingSoonFor(WidgetRef ref, String? categoryId) =>
      comingSoonCategoryIn(ref.read(homeCategoriesProvider).valueOrNull, categoryId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = queryFor(categoryId);
    final comingSoon = comingSoonCategoryIn(ref.watch(homeCategoriesProvider).valueOrNull, categoryId);

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: HomeLayout.section,
          sliver: SliverToBoxAdapter(child: SectionHeader(title: l10n.discover)),
        ),
        SliverToBoxAdapter(
          child: _DiscoverChips(selectedId: categoryId, onSelected: onCategoryChanged),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(HomeLayout.h, AppSpacing.md, HomeLayout.h, 0),
          sliver: comingSoon != null
              ? SliverToBoxAdapter(
                  child: ComingSoonInlineCard(info: comingSoon, onShowAllGifts: () => onCategoryChanged(null)),
                )
              : Builder(builder: (context) {
                  final state = watchProductList(ref, query);
                  return ProductListSlivers(
                    state: state,
                    onRetry: () => refreshProductList(ref, query),
                    onLoadMore: () => loadMoreProducts(ref, query),
                    empty: EmptyState(icon: Icons.search_off_rounded, title: l10n.noProductsTitle),
                  );
                }),
        ),
      ],
    );
  }
}

/// "All" + the Home categories as icon chips; hidden when there are none.
class _DiscoverChips extends ConsumerWidget {
  const _DiscoverChips({required this.selectedId, required this.onSelected});

  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(homeCategoriesProvider).valueOrNull ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final soon = comingSoonIdsIn(categories);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: SizedBox(
        height: CategoryChip.height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: HomeLayout.h),
          itemCount: categories.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, i) {
            if (i == 0) {
              return CategoryChip(
                label: l10n.all,
                selected: selectedId == null,
                onTap: () => onSelected(null),
              );
            }
            final category = categories[i - 1];
            return CategoryChip(
              key: ValueKey(category.id),
              label: category.title.of(context),
              imageUrl: category.iconUrl,
              comingSoon: soon.contains(category.id),
              selected: selectedId == category.id,
              onTap: () => onSelected(category.id),
            );
          },
        ),
      ),
    );
  }
}
