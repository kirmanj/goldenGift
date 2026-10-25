import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/review_model.dart';
import '../../../orders/presentation/widgets/order_dialogs.dart' show showPhotoViewer;
import 'star_rating.dart';

/// One approved review (SRS §5.26): first name, stars, date, text and photo
/// thumbnails that open the full-screen viewer.
class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.review});

  final ReviewModel review;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final name = review.userName.trim().isEmpty ? l10n.reviewAnonymous : review.userName.trim();
    final initial = name.characters.first.toUpperCase();
    return Column(
      key: ValueKey('review-${review.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
                child: Text(
                  initial,
                  style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.goldText(context)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        name,
                        style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                      ),
                      if (review.createdAt != null)
                        Text(
                          AppDates.display(review.createdAt!),
                          style: AppTextStyles.bodySmall.copyWith(color: muted),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  StarRatingDisplay(rating: review.rating.toDouble()),
                ],
              ),
            ),
          ],
        ),
        if (review.text.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            review.text.trim(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text(context)),
          ),
        ],
        if (review.images.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < review.images.length; i++)
                Semantics(
                  button: true,
                  label: l10n.photosCount(review.images.length),
                  child: InkWell(
                    key: ValueKey('review-photo-${review.id}-$i'),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => showPhotoViewer(context, review.images, initialIndex: i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: SizedBox.square(dimension: 56, child: GGNetworkImage(url: review.images[i])),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
