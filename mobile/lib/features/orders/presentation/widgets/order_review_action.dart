import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/order_model.dart';
import '../../../../models/review_model.dart';
import '../../../reviews/presentation/providers/review_providers.dart';
import '../../../reviews/presentation/widgets/review_form_sheet.dart';
import '../../../reviews/presentation/widgets/star_rating.dart';
import 'order_section.dart';

/// Lines that get a Rate action (SRS §5.12, §5.26): delivered lines of a
/// standard order, one per product (a review is per order + product).
Set<String> reviewableLineIds(OrderModel order) {
  if (order.orderType != OrderType.standard) return const {};
  final seen = <String>{};
  return {
    for (final item in order.items)
      if ((item.status == OrderStatus.delivered || order.status == OrderStatus.delivered) &&
          item.line.productId.isNotEmpty &&
          seen.add(item.line.productId))
        item.line.id,
  };
}

/// "★ Rate" for a delivered line — or, once reviewed, "Your review is pending
/// approval" / "Reviewed ★★★★☆" with Edit (editing re-enters moderation).
class OrderLineReviewAction extends ConsumerWidget {
  const OrderLineReviewAction({super.key, required this.target, required this.lineId});

  final ReviewTarget target;
  final String lineId;

  Future<void> _open(BuildContext context, WidgetRef ref, ReviewModel? existing) async {
    final l10n = AppLocalizations.of(context)!;
    final submitted = await showReviewFormSheet(context, target: target, existing: existing);
    if (!submitted || !context.mounted) return;
    ref.invalidate(myReviewProvider(target.key));
    showOrderSnack(context, l10n.reviewThanks);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final mine = ref.watch(myReviewProvider(target.key));
    // Unknown yet (or failed to load): nothing, rather than a Rate that may duplicate.
    if (!mine.hasValue) return const SizedBox.shrink();
    final review = mine.value;
    final gold = AppColors.goldText(context);
    final linkStyle = TextButton.styleFrom(
      foregroundColor: gold,
      minimumSize: const Size.square(AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );

    if (review == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: ValueKey('rate-$lineId'),
          onPressed: () => unawaited(_open(context, ref, null)),
          style: OutlinedButton.styleFrom(
            foregroundColor: gold,
            minimumSize: const Size.square(AppSpacing.minTapTarget),
            side: BorderSide(color: AppColors.gold(context), width: 1.2),
            shape: const StadiumBorder(),
            textStyle: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700),
          ),
          icon: const Icon(Icons.star_outline_rounded, size: 20),
          label: Text(l10n.reviewRate),
        ),
      );
    }

    final muted = AppColors.textMuted(context);
    return Wrap(
      key: ValueKey('review-status-$lineId'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: [
        Icon(
          review.isApproved ? Icons.check_circle_outline_rounded : Icons.hourglass_top_rounded,
          size: 18,
          color: review.isApproved ? AppColors.success : muted,
        ),
        Text(
          review.isApproved ? l10n.reviewReviewed : l10n.reviewPending,
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: muted),
        ),
        StarRatingDisplay(rating: review.rating.toDouble(), size: 14),
        TextButton(
          key: ValueKey('edit-review-$lineId'),
          onPressed: () => unawaited(_open(context, ref, review)),
          style: linkStyle,
          child: Text(l10n.reviewEdit, style: AppTextStyles.link.copyWith(fontSize: 14, color: gold)),
        ),
      ],
    );
  }
}
