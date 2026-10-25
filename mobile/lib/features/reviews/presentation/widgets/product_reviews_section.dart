import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../../../../models/review_model.dart';
import '../../data/reviews_repository.dart';
import '../providers/review_providers.dart';
import 'review_tile.dart';
import 'star_rating.dart';

/// Product Details ▸ Reviews, below About (SRS §5.26): the average and count
/// from the product aggregates, the 3 latest approved reviews and "See all".
/// Hidden while a product has no approved review. Watches only the reviews
/// stream, so option taps never rebuild it.
class ProductReviewsSection extends ConsumerWidget {
  const ProductReviewsSection({super.key, required this.product});

  final ProductModel product;

  static const preview = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final reviewsAsync = ref.watch(approvedReviewsProvider(product.id));
    final reviews = reviewsAsync.valueOrNull ?? const <ReviewModel>[];
    // Aggregates come from `onReviewWrite`; until it has run, use what loaded.
    final hasAggregates = product.ratingCount > 0;
    final count = hasAggregates ? product.ratingCount : reviews.length;
    final average = hasAggregates ? product.ratingAvg : averageRating(reviews);
    if (count == 0 && reviews.isEmpty) return const SizedBox.shrink();
    final showAll = count > preview || reviews.length > preview;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        key: const ValueKey('product-reviews'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.reviewsTitle,
                    style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                  ),
                ),
              ),
              if (showAll)
                TextButton(
                  key: const ValueKey('reviews-see-all'),
                  onPressed: () => unawaited(showAllReviewsSheet(context, product)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.goldText(context),
                    minimumSize: const Size.square(AppSpacing.minTapTarget),
                  ),
                  child: Text(l10n.reviewsSeeAll, style: AppTextStyles.link.copyWith(color: AppColors.goldText(context))),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          RatingSummary(average: average, count: count),
          if (reviewsAsync.isLoading && reviews.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const SkeletonLoader.list(count: 2),
          ],
          for (final review in reviews.take(preview)) ...[
            Divider(height: AppSpacing.lg + AppSpacing.sm, color: AppColors.line(context)),
            ReviewTile(review: review),
          ],
        ],
      ),
    );
  }
}

/// Every approved review of [product], 20 more each time the list nears its end.
Future<void> showAllReviewsSheet(BuildContext context, ProductModel product) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card(context),
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => _AllReviewsSheet(product: product),
    );

class _AllReviewsSheet extends ConsumerStatefulWidget {
  const _AllReviewsSheet({required this.product});
  final ProductModel product;

  @override
  ConsumerState<_AllReviewsSheet> createState() => _AllReviewsSheetState();
}

class _AllReviewsSheetState extends ConsumerState<_AllReviewsSheet> {
  static const _page = 20;
  int _limit = _page;

  /// The last page shown, kept while a bigger page loads.
  List<ReviewModel> _shown = const [];

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.extentAfter < 400 && _shown.length >= _limit) {
      setState(() => _limit += _page);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final product = widget.product;
    final page = ref.watch(approvedReviewsPageProvider((productId: product.id, limit: _limit)));
    if (page.valueOrNull != null) _shown = page.valueOrNull!;
    final count = product.ratingCount > 0 ? product.ratingCount : _shown.length;
    final average = product.ratingCount > 0 ? product.ratingAvg : averageRating(_shown);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 1,
      builder: (context, controller) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView(
          key: const ValueKey('all-reviews'),
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            0,
            AppSpacing.screenHorizontal,
            AppSpacing.xl,
          ),
          children: [
            Semantics(
              header: true,
              child: Text(l10n.reviewsTitle, style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
            ),
            const SizedBox(height: AppSpacing.sm),
            RatingSummary(average: average, count: count),
            for (final review in _shown) ...[
              Divider(height: AppSpacing.lg + AppSpacing.sm, color: AppColors.line(context)),
              ReviewTile(review: review),
            ],
            if (page.isLoading) ...[
              const SizedBox(height: AppSpacing.md),
              const SkeletonLoader.list(count: 2),
            ],
          ],
        ),
      ),
    );
  }
}
