import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';

/// Read-only row of 5 gold stars (full / half / empty) announced as
/// "Rated 4.5 out of 5" (SRS §5.26).
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({super.key, required this.rating, this.size = 16});

  final double rating;
  final double size;

  /// "4.6" — one decimal, Western digits (as on the reference screens).
  static String format(double rating) => rating.clamp(0, 5).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final gold = AppColors.gold(context);
    final value = rating.clamp(0.0, 5.0);
    return Semantics(
      label: l10n.reviewStarsLabel(format(value)),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              value >= i
                  ? Icons.star_rounded
                  : value >= i - 0.5
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded,
              size: size,
              color: value >= i - 0.5 ? gold : AppColors.textMuted(context).withValues(alpha: 0.6),
            ),
        ],
      ),
    );
  }
}

/// 1–5 star picker with 44 px targets; each star is a button announced as
/// "4 stars" and marked selected up to the current value.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({super.key, required this.value, required this.onChanged, this.hasError = false});

  /// 0 = nothing chosen yet.
  final int value;
  final ValueChanged<int> onChanged;
  final bool hasError;

  static const double tapTarget = AppSpacing.minTapTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final gold = AppColors.gold(context);
    final idle = hasError ? AppColors.error : AppColors.textMuted(context).withValues(alpha: 0.7);
    return Wrap(
      spacing: AppSpacing.xxs,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: true,
            selected: i <= value,
            label: l10n.reviewStarButton(i),
            excludeSemantics: true,
            onTap: () => onChanged(i),
            child: InkResponse(
              key: ValueKey('review-star-$i'),
              onTap: () => onChanged(i),
              radius: tapTarget / 2,
              child: SizedBox.square(
                dimension: tapTarget,
                child: Icon(
                  i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 36,
                  color: i <= value ? gold : idle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "4.6 ★★★★½ · 23 reviews" summary block for Product Details.
class RatingSummary extends StatelessWidget {
  const RatingSummary({super.key, required this.average, required this.count});

  final double average;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm + AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        Text(
          StarRatingDisplay.format(average),
          key: const ValueKey('rating-average'),
          textDirection: TextDirection.ltr,
          style: AppTextStyles.heading1.copyWith(color: AppColors.text(context)),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StarRatingDisplay(rating: average, size: 20),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n.reviewsCount(count),
              key: const ValueKey('rating-count'),
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
            ),
          ],
        ),
      ],
    );
  }
}
