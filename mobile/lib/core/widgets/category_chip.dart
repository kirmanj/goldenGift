import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../../l10n/l10n.dart';
import 'category_tile.dart' show SoonPill;
import 'gg_network_image.dart';

/// Pill filter chip with an optional leading icon or category image
/// (SRS §5.8 category chips, §5.4 item 12 Discover chips; IMG_4481).
/// Selected = soft-gold fill + gold border; unselected = surface + border.
/// [comingSoon] adds the gold "Soon" pill after the label (SRS §5.7a).
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.imageUrl,
    this.comingSoon = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Leading Material icon (ignored when [imageUrl] is set).
  final IconData? icon;

  /// Leading category image, shown in a small circle.
  final String? imageUrl;

  /// A coming-soon category: trailing "Soon" pill.
  final bool comingSoon;

  /// The pill is the tap target: [AppSpacing.minTapTarget] tall.
  static const double height = AppSpacing.minTapTarget;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final Widget? leading = hasImage
        ? ClipOval(
            child: SizedBox.square(
              dimension: 28,
              child: GGNetworkImage(url: imageUrl, fallbackColor: AppColors.field(context)),
            ),
          )
        : icon == null
            ? null
            : Icon(icon, size: 18, color: selected ? gold : AppColors.textMuted(context));

    return Semantics(
      button: true,
      selected: selected,
      // The pill is excluded from semantics; say it after the label instead.
      hint: comingSoon ? AppLocalizations.of(context)!.comingSoon : null,
      child: Material(
        color: selected ? AppColors.soft(context) : AppColors.card(context),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? gold : AppColors.line(context),
            width: selected ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: height,
            padding: EdgeInsetsDirectional.only(
              start: leading == null ? AppSpacing.md : AppSpacing.sm,
              end: AppSpacing.md,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading,
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(
                      fontSize: 14,
                      color: AppColors.text(context),
                    ),
                  ),
                ),
                if (comingSoon) ...[
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  const SoonPill(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
