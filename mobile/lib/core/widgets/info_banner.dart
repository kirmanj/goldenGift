import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

enum InfoBannerType { warning, success, info, error }

/// Soft-tinted message strip with an icon (SRS §5.9 item 3, IMG_4494):
/// warning-soft "This product requires N days for preparation",
/// success-soft "This product can be shipped same day", plus info / error.
///
/// Dark-mode soft backgrounds are the base colour blended onto the dark
/// surface (SRS §2.3 dark soft tones). Text is darkened (light mode) or
/// lightened (dark mode) from the base colour to keep ≥ 4.5:1 contrast.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.type = InfoBannerType.info,
    this.icon,
  });

  final String message;
  final InfoBannerType type;

  /// Overrides the default icon for [type].
  final IconData? icon;

  static Color _baseFor(InfoBannerType type) => switch (type) {
        InfoBannerType.warning => AppColors.warning,
        InfoBannerType.success => AppColors.success,
        InfoBannerType.info => AppColors.info,
        InfoBannerType.error => AppColors.error,
      };

  IconData get _defaultIcon => switch (type) {
        InfoBannerType.warning => Icons.error_outline_rounded,
        InfoBannerType.success => Icons.local_shipping_outlined,
        InfoBannerType.info => Icons.info_outline_rounded,
        InfoBannerType.error => Icons.report_gmailerrorred_rounded,
      };

  /// Soft background for [type] in the current theme.
  static Color softColor(BuildContext context, InfoBannerType type) {
    final base = _baseFor(type);
    if (AppColors.isDark(context)) {
      return Color.alphaBlend(base.withValues(alpha: 0.2), AppColors.darkSurface);
    }
    return switch (type) {
      InfoBannerType.warning => AppColors.warningSoft,
      InfoBannerType.success => AppColors.successSoft,
      InfoBannerType.error => AppColors.errorSoft,
      InfoBannerType.info => Color.alphaBlend(base.withValues(alpha: 0.1), AppColors.surface),
    };
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final base = _baseFor(type);
    final fg = dark
        ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.35), base)
        : Color.alphaBlend(AppColors.black.withValues(alpha: 0.3), base);
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: softColor(context, type),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? _defaultIcon, size: 20, color: dark ? fg : base),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodyMedium.copyWith(
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
