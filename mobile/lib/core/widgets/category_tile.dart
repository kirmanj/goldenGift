import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'gg_network_image.dart';

/// Category grid tile: soft-grey rounded square with the category's 3D
/// icon image (or a fallback Material icon) and a two-line label beneath
/// (SRS §5.4 item 3, §5.7; IMG_4476, IMG_4496).
///
/// [CategoryTile.more] is the Home grid's last tile: a gold rounded icon
/// square labelled "More" that opens All Categories.
///
/// [comingSoon] (SRS §5.7a) keeps the tile fully visible but gives it a
/// soft-gold square with a hairline gold rim and a small gold-outline "Soon"
/// pill in the top-end corner; screen readers hear "{label}, coming soon".
///
/// Needs a bounded width (grid cell). In a grid, size cells with
/// [CategoryTile.heightFor] (square + two label lines at the current text
/// scale), e.g. `mainAxisExtent: CategoryTile.heightFor(context, cellWidth)`.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required String this.label,
    this.iconUrl,
    this.icon = Icons.card_giftcard_rounded,
    this.onTap,
    this.comingSoon = false,
  }) : isMoreTile = false;

  /// "More" tile; [label] defaults to the localized "More".
  const CategoryTile.more({super.key, this.label, this.onTap})
      : isMoreTile = true,
        iconUrl = null,
        icon = Icons.more_horiz_rounded,
        comingSoon = false;

  final String? label;
  final String? iconUrl;

  /// Shown when [iconUrl] is empty or fails to load.
  final IconData icon;
  final VoidCallback? onTap;
  final bool isMoreTile;

  /// The category is "coming soon" (SRS §5.7a): shows the "Soon" pill.
  final bool comingSoon;

  static const double _labelFont = 13;
  static const double _labelHeight = 1.3;

  /// Tile height for a given tile width at the current text scale.
  static double heightFor(BuildContext context, double width) =>
      width +
      AppSpacing.sm +
      2 * MediaQuery.textScalerOf(context).scale(_labelFont) * _labelHeight +
      2; // sub-pixel rounding slack

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = label ?? l10n.more;
    final Widget content;
    if (isMoreTile) {
      content = FractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 0.5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.gold(context),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: const FittedBox(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xs),
              child: Icon(Icons.more_horiz_rounded, color: AppColors.textOnPrimary),
            ),
          ),
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
        child: GGNetworkImage(
          url: iconUrl,
          fit: BoxFit.contain,
          fallbackIcon: icon,
          fallbackColor: comingSoon ? AppColors.soft(context) : AppColors.field(context),
        ),
      );
    }

    final square = Ink(
      decoration: BoxDecoration(
        color: comingSoon ? AppColors.soft(context) : AppColors.field(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: comingSoon ? Border.all(color: AppColors.gold(context).withValues(alpha: 0.45)) : null,
      ),
      child: Center(child: content),
    );

    return Semantics(
      button: true,
      label: comingSoon ? l10n.categoryComingSoonLabel(text) : text,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: comingSoon
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        square,
                        const PositionedDirectional(
                          top: AppSpacing.xs,
                          start: AppSpacing.xs,
                          end: AppSpacing.xs,
                          child: Align(
                            alignment: AlignmentDirectional.topEnd,
                            child: SoonPill(),
                          ),
                        ),
                      ],
                    )
                  : square,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: _labelFont,
                height: _labelHeight,
                fontWeight: FontWeight.w600,
                color: AppColors.text(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small gold-outline "Soon" pill for coming-soon categories (SRS §5.7a):
/// tiles, chips. Scales down rather than overflow in narrow tiles at large
/// text; decorative for screen readers (the tile / chip label says it).
class SoonPill extends StatelessWidget {
  const SoonPill({super.key});

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    return ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.topEnd,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: gold),
            boxShadow: AppElevation.soft,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xs + AppSpacing.xxs,
              AppSpacing.xxs,
              AppSpacing.sm,
              AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 10, color: gold),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  AppLocalizations.of(context)!.categorySoonBadge,
                  maxLines: 1,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 10,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: AppColors.goldText(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
