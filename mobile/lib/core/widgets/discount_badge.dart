import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Error-red pill with the rounded discount percentage, e.g. "13%"
/// (SRS §4.4, IMG_4481; large variant under the Product Details carousel,
/// IMG_4508). White on `AppColors.error` is ≈ 5:1 contrast (passes AA).
/// Renders nothing when [percent] ≤ 0.
class DiscountBadge extends StatelessWidget {
  const DiscountBadge({super.key, required this.percent, this.large = false});

  final int percent;
  final bool large;

  static double _fontSize(bool large) => large ? 15 : 11;
  static const double _lineHeight = 1.25;
  static double _vPad(bool large) => large ? AppSpacing.xs : AppSpacing.xxs;

  /// Rendered height for [textScaler] — used to size product grid cells.
  static double heightFor(TextScaler textScaler, {bool large = false}) =>
      textScaler.scale(_fontSize(large)) * _lineHeight + 2 * _vPad(large);

  @override
  Widget build(BuildContext context) {
    if (percent <= 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: l10n.percentOff(percent),
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: large ? AppSpacing.sm + AppSpacing.xxs : AppSpacing.xs + AppSpacing.xxs,
          vertical: _vPad(large),
        ),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          '$percent%',
          maxLines: 1,
          textDirection: TextDirection.ltr,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: _fontSize(large),
            height: _lineHeight,
            fontWeight: FontWeight.w700,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}
