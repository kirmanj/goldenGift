import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../data/product_query.dart';
import '../providers/product_list_controller.dart';
import 'load_more_trigger.dart';
import 'product_sliver_grid.dart';

/// Watches one infinite products list. If the controller itself can't be
/// created (e.g. the backend isn't available) the list shows its error state
/// instead of breaking the screen it is part of (SRS §5.4 AC).
ProductListState watchProductList(WidgetRef ref, ProductQuery query) {
  try {
    return ref.watch(productListControllerProvider(query));
  } catch (e) {
    return ProductListState(isLoading: false, hasMore: false, error: e);
  }
}

/// Pull-to-refresh / Retry for [query]: reloads from the first page.
Future<void> refreshProductList(WidgetRef ref, ProductQuery query) async {
  try {
    await ref.read(productListControllerProvider(query).notifier).refresh();
  } catch (_) {
    ref.invalidate(productListControllerProvider(query));
  }
}

/// Requests the next page of [query] (ignored while one is loading).
void loadMoreProducts(WidgetRef ref, ProductQuery query) {
  try {
    ref.read(productListControllerProvider(query).notifier).loadMore();
  } catch (_) {
    // The controller failed to build; its error state already offers Retry.
  }
}

/// The body of an infinite products list as one sliver (SRS §4.8, §5.4 item
/// 12, §5.8): a skeleton grid while the first page loads, [ErrorState] with
/// Retry, [empty] when nothing matches, otherwise the 2-column grid followed by
/// a loading-more spinner or a "Couldn't load more" row with Retry.
///
/// [fillRemaining] centres the error / empty state in the remaining viewport
/// (a screen of its own); otherwise they take their natural height (a section
/// of a longer page).
class ProductListSlivers extends StatelessWidget {
  const ProductListSlivers({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onLoadMore,
    required this.empty,
    this.fillRemaining = false,
    this.skeletonCount = 4,
  });

  final ProductListState state;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final Widget empty;
  final bool fillRemaining;
  final int skeletonCount;

  Widget _box(Widget child) => fillRemaining
      ? SliverFillRemaining(hasScrollBody: false, child: child)
      : SliverToBoxAdapter(child: child);

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      if (state.isLoading) {
        return SliverToBoxAdapter(child: SkeletonLoader.productGrid(count: skeletonCount));
      }
      if (state.error != null) return _box(ErrorState(onRetry: onRetry));
      return _box(empty);
    }
    final canLoadMore = state.hasMore &&
        !state.isLoading &&
        !state.isLoadingMore &&
        state.error == null &&
        state.loadMoreError == null;
    return SliverMainAxisGroup(
      slivers: [
        LoadMoreTrigger(
          enabled: canLoadMore,
          onLoadMore: onLoadMore,
          child: ProductSliverGrid(products: state.items),
        ),
        if (state.isLoadingMore) const SliverToBoxAdapter(child: LoadingMoreIndicator()),
        if (state.loadMoreError != null && !state.isLoadingMore)
          SliverToBoxAdapter(child: LoadMoreErrorRow(onRetry: onLoadMore)),
      ],
    );
  }
}

/// Small gold spinner under a list while the next page loads.
class LoadingMoreIndicator extends StatelessWidget {
  const LoadingMoreIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Semantics(
          label: AppLocalizations.of(context)!.loading,
          child: SizedBox.square(
            dimension: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.gold(context)),
          ),
        ),
      ),
    );
  }
}

/// "Couldn't load more gifts." + Retry, shown when a later page fails.
class LoadMoreErrorRow extends StatelessWidget {
  const LoadMoreErrorRow({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        children: [
          Text(
            l10n.loadMoreFailed,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.retry),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.goldText(context),
              minimumSize: const Size.square(AppSpacing.minTapTarget),
              shape: const StadiumBorder(),
              textStyle: AppTextStyles.link.copyWith(fontFamily: font),
            ),
          ),
        ],
      ),
    );
  }
}
