import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Gold-shimmer "★ Featured" pill shown on the top-start corner of a
/// featured product's image (SRS §4.4, IMG_4477). Dark text on gold.
class FeaturedBadge extends StatelessWidget {
  const FeaturedBadge({super.key, this.label});

  /// Defaults to the localized "Featured".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ?? AppLocalizations.of(context)!.featured;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.sm - AppSpacing.xxs,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          gradient: AppColors.goldShimmer,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 13, color: AppColors.textOnPrimary),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 11,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textOnPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
