import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Circular surface button — app-bar back / cart, filter, bell (SRS §2.3
/// shape language). Light mode: white circle with a 1 px border and a soft
/// shadow; dark mode: near-black circle with a 1 px border and no shadow.
///
/// The visual circle is [size]; the tap target is never smaller than
/// [minTapTarget] (48 dp, SRS §8).
/// An optional gold [badgeCount] sits on the top-end corner (cart count).
class GGCircleButton extends StatelessWidget {
  const GGCircleButton({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    this.onPressed,
    this.size = 44,
    this.iconSize = 22,
    this.iconColor,
    this.badgeCount,
    this.toggled,
  }) : assert(icon != null || child != null, 'Provide an icon or a child');

  final IconData? icon;

  /// Custom content instead of [icon] (e.g. a language code).
  final Widget? child;

  /// Accessibility label + long-press tooltip (icon-only button).
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  /// Defaults to `AppColors.text(context)`.
  final Color? iconColor;

  /// Shown as a gold count badge when > 0 (99+ above 99).
  final int? badgeCount;

  /// Exposes a toggle state to screen readers (e.g. wishlist heart).
  final bool? toggled;

  static const double minTapTarget = AppSpacing.minTapTarget;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final count = badgeCount ?? 0;
    final tapSize = math.max(size, minTapTarget);

    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        toggled: toggled,
        label: count > 0 ? '$tooltip ($count)' : tooltip,
        onTap: onPressed,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: onPressed,
            radius: size / 2,
            containedInkWell: false,
            highlightShape: BoxShape.circle,
            child: SizedBox.square(
              dimension: tapSize,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Ink(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.line(context)),
                        boxShadow: dark ? null : AppElevation.soft,
                      ),
                      child: Center(
                        child: child ??
                            Icon(
                              icon,
                              size: iconSize,
                              color: iconColor ?? AppColors.text(context),
                            ),
                      ),
                    ),
                    if (count > 0)
                      PositionedDirectional(
                        top: -AppSpacing.xs,
                        end: -AppSpacing.xs,
                        child: _CountBadge(count: count),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.gold(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.card(context), width: 2),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTextStyles.bodySmall.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.2,
          color: AppColors.textOnPrimary,
        ),
      ),
    );
  }
}
