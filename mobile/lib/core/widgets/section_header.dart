import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Home / list section title with a gold "View All" link on the end side
/// (SRS §5.4 items 4, 6, 7; IMG_4476). The link is hidden when
/// [onViewAll] is null.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onViewAll,
    this.viewAllLabel,
    this.padding = EdgeInsetsDirectional.zero,
    this.maxLines = 1,
  });

  final String title;
  final VoidCallback? onViewAll;

  /// Defaults to the localized "View All".
  final String? viewAllLabel;
  final EdgeInsetsGeometry padding;

  /// Title lines before the ellipsis (2 for long localized titles).
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.goldText(context);
    // ButtonStyle.textStyle replaces (does not merge with) the theme text
    // style, so the locale font family must be set explicitly.
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sectionTitle.copyWith(color: AppColors.text(context)),
                ),
              ),
            ),
            if (onViewAll != null)
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: gold,
                  minimumSize: const Size.square(AppSpacing.minTapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  shape: const StadiumBorder(),
                  textStyle: AppTextStyles.link.copyWith(fontFamily: font),
                ),
                child: Text(viewAllLabel ?? AppLocalizations.of(context)!.viewAll),
              ),
          ],
        ),
      ),
    );
  }
}
