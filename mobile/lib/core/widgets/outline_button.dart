import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'gg_button_content.dart';

/// Secondary pill button — gold border and gold text on a transparent fill,
/// same API and height as [PrimaryButton] (SRS §2.3; e.g. "My Rewards" in
/// the referral sheet, §5.4 item 13).
class OutlineButton extends StatelessWidget {
  const OutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.height = 56,
    this.fitLabel = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expand;
  final double height;

  /// Shrink a long label to fit (small phones at 130 % text) instead of "…".
  final bool fitLabel;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    // ButtonStyle.textStyle replaces (does not merge with) the theme text
    // style, so the locale font family must be set explicitly.
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    final enabled = onPressed != null && !isLoading;
    final sideColor = enabled || isLoading ? gold : AppColors.line(context);
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.goldText(context),
        disabledForegroundColor: AppColors.textMuted(context).withValues(alpha: 0.7),
        textStyle: AppTextStyles.button.copyWith(fontFamily: font),
        minimumSize: expand ? Size.fromHeight(height) : Size(height, height),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        side: BorderSide(color: sideColor, width: 1.4),
        shape: const StadiumBorder(),
      ),
      child: GGButtonContent(
        fitLabel: fitLabel,
        label: label,
        icon: icon,
        isLoading: isLoading,
        spinnerColor: gold,
      ),
    );
  }
}
