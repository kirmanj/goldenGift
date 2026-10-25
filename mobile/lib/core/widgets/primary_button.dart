import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'gg_button_content.dart';

/// Gold, pill-shaped call-to-action — height 56, dark text on gold
/// (SRS §2.3; Sign Up, Add to Cart, Start Shopping, Checkout).
///
/// [isLoading] keeps the gold fill and swaps the label for a spinner while
/// ignoring taps; a null [onPressed] renders the dimmed disabled state.
/// Full width by default; set [expand] to false for an inline pill.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
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

  /// Optional leading icon (mirrors automatically in RTL).
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
    final disabledFill =
        AppColors.isDark(context) ? gold.withValues(alpha: 0.35) : gold.withValues(alpha: 0.45);
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: AppColors.textOnPrimary,
        disabledBackgroundColor: isLoading ? gold : disabledFill,
        disabledForegroundColor: AppColors.textOnPrimary.withValues(alpha: 0.55),
        elevation: 0,
        textStyle: AppTextStyles.button.copyWith(fontFamily: font),
        minimumSize: expand ? Size.fromHeight(height) : Size(height, height),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: const StadiumBorder(),
      ),
      child: GGButtonContent(
        fitLabel: fitLabel,
        label: label,
        icon: icon,
        isLoading: isLoading,
        spinnerColor: AppColors.textOnPrimary,
      ),
    );
  }
}
