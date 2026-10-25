import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../categories/presentation/providers/categories_providers.dart';
import '../../../products/data/product_query.dart';
import '../../../products/presentation/gift_audience_ui.dart';
import '../../../products/presentation/widgets/product_filter_sheet.dart' show priceBandLabel;
import '../../data/reels_repository.dart';

/// Opens the Reels filter (SRS §5.27). Resolves to the new filter on
/// "Show reels", or null when dismissed.
Future<ReelFilter?> showReelsFilterSheet(BuildContext context, ReelFilter filter) {
  return showModalBottomSheet<ReelFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.card(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => ReelsFilterSheet(initial: filter),
  );
}

/// Category (one, Available categories only), price bands (several) and gift
/// type (one). Edits a draft; the feed changes on "Show reels".
class ReelsFilterSheet extends ConsumerStatefulWidget {
  const ReelsFilterSheet({super.key, required this.initial});

  final ReelFilter initial;

  @override
  ConsumerState<ReelsFilterSheet> createState() => _ReelsFilterSheetState();
}

class _ReelsFilterSheetState extends ConsumerState<ReelsFilterSheet> {
  late ReelFilter _draft = widget.initial;

  void _toggleBand(int band) => setState(() {
        final bands = {..._draft.priceBands};
        if (!bands.remove(band)) bands.add(band);
        _draft = _draft.copyWith(priceBands: bands);
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final categories = availableCategoriesIn(ref.watch(allCategoriesProvider).valueOrNull ?? const []);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.screenHorizontal,
              0,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.reelsFilterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _draft = const ReelFilter()),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.goldText(context),
                    minimumSize: const Size.square(AppSpacing.minTapTarget),
                    shape: const StadiumBorder(),
                    textStyle: AppTextStyles.link.copyWith(fontFamily: font),
                  ),
                  child: Text(l10n.resetFilters),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionTitle(l10n.giftForTitle),
                  _ChipWrap(
                    children: [
                      CategoryChip(
                        label: l10n.giftForEveryone,
                        selected: _draft.giftFor == null,
                        onTap: () => setState(() => _draft = _draft.copyWith(clearGiftFor: true)),
                      ),
                      for (final audience in GiftAudience.values)
                        CategoryChip(
                          label: audience.label(l10n),
                          icon: audience.icon,
                          selected: _draft.giftFor == audience,
                          onTap: () => setState(() => _draft = _draft.copyWith(giftFor: audience)),
                        ),
                    ],
                  ),
                  _SectionTitle(l10n.price),
                  _ChipWrap(
                    children: [
                      for (var band = 0; band < PriceBands.count; band++)
                        CategoryChip(
                          label: priceBandLabel(l10n, band, rtl: rtl),
                          selected: _draft.priceBands.contains(band),
                          onTap: () => _toggleBand(band),
                        ),
                    ],
                  ),
                  _SectionTitle(l10n.reelsCategory),
                  _ChipWrap(
                    children: [
                      CategoryChip(
                        label: l10n.all,
                        selected: _draft.categoryId == null,
                        onTap: () => setState(() => _draft = _draft.copyWith(clearCategory: true)),
                      ),
                      for (final category in categories)
                        CategoryChip(
                          label: category.title.of(context),
                          imageUrl: category.iconUrl,
                          selected: _draft.categoryId == category.id,
                          onTap: () => setState(() => _draft = _draft.copyWith(categoryId: category.id)),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.sm,
              AppSpacing.screenHorizontal,
              AppSpacing.md + MediaQuery.paddingOf(context).bottom,
            ),
            child: PrimaryButton(
              label: l10n.reelsShowResults,
              onPressed: () => Navigator.of(context).pop(_draft),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: children);
  }
}
