import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Colour family of a row icon (IMG_4490's coloured circles, shown here as
/// soft tints so gold stays the only strong accent).
enum ProfileTileTone { gold, info, success, warning, error, neutral }

/// Error red that keeps ≥ 4.5:1 for text on dark surfaces too.
Color profileErrorText(BuildContext context) => AppColors.isDark(context)
    ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.3), AppColors.error)
    : AppColors.error;

/// Round soft-tinted icon used by the Profile and Settings rows.
class ProfileIconBadge extends StatelessWidget {
  const ProfileIconBadge({
    super.key,
    required this.icon,
    this.tone = ProfileTileTone.gold,
    this.size = 44,
  });

  final IconData icon;
  final ProfileTileTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final Color background;
    final Color foreground;
    if (tone == ProfileTileTone.gold) {
      background = AppColors.soft(context);
      foreground = AppColors.gold(context);
    } else {
      final base = switch (tone) {
        ProfileTileTone.info => AppColors.info,
        ProfileTileTone.success => AppColors.success,
        ProfileTileTone.warning => AppColors.warning,
        ProfileTileTone.error => AppColors.error,
        _ => AppColors.textMuted(context),
      };
      background = Color.alphaBlend(base.withValues(alpha: dark ? 0.22 : 0.12), AppColors.card(context));
      foreground = dark ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.25), base) : base;
    }
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.5, color: foreground),
      ),
    );
  }
}

/// One Profile / Settings row: soft-tinted round icon, title, optional
/// subtitle (gold by default, SRS §5.13) and a chevron that mirrors in RTL.
/// [trailing] replaces nothing — it sits before the chevron (e.g. a switch
/// with [showChevron] false). Whole row is the tap target (≥ 64 px high).
class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.tone = ProfileTileTone.gold,
    this.onTap,
    this.trailing,
    this.showChevron = true,
    this.destructive = false,
    this.padding = const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.screenHorizontal),
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Defaults to `AppColors.goldText(context)`.
  final Color? subtitleColor;
  final ProfileTileTone tone;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;

  /// Error-red title (Logout, Delete account).
  final bool destructive;
  final EdgeInsetsGeometry padding;

  static const double minHeight = 64;

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive ? profileErrorText(context) : AppColors.text(context);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding.add(
                const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.sm + AppSpacing.xxs),
              ),
              child: Row(
                children: [
                  ProfileIconBadge(icon: icon, tone: tone),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.label.copyWith(fontSize: 16, color: titleColor),
                        ),
                        if (hasSubtitle) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            subtitle!,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 13,
                              color: subtitleColor ?? AppColors.goldText(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    trailing!,
                  ],
                  if (showChevron) ...[
                    const SizedBox(width: AppSpacing.sm),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 26,
                        color: AppColors.textMuted(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
