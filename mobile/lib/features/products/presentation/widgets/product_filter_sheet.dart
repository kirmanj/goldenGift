import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../data/product_query.dart';
import '../gift_audience_ui.dart';

/// Opens the products filter sheet (SRS §5.8) on [query]. Resolves to the
/// new query when the user taps "Show results", or null when dismissed.
Future<ProductQuery?> showProductFilterSheet(BuildContext context, ProductQuery query) {
  return showModalBottomSheet<ProductQuery>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.card(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => ProductFilterSheet(initial: query),
  );
}

/// Label of a sort option.
String productSortLabel(AppLocalizations l10n, ProductSort sort) => switch (sort) {
      ProductSort.relevance => l10n.sortRelevance,
      ProductSort.newest => l10n.sortNewest,
      ProductSort.popular => l10n.sortPopular,
      ProductSort.priceLowHigh => l10n.sortPriceLowHigh,
      ProductSort.priceHighLow => l10n.sortPriceHighLow,
    };

/// "Under 25,000 IQD" · "25,000 IQD – 50,000 IQD" · … · "200,000 IQD and above".
///
/// In RTL every amount is wrapped in a right-to-left isolate (RLI … PDI):
/// otherwise the bidi algorithm interleaves the two amounts of a range
/// ("IQD – 50,000 IQD 25,000"). Each amount then looks like a [PriceText].
String priceBandLabel(AppLocalizations l10n, int band, {bool rtl = false}) {
  String amount(int value) {
    final text = CurrencyFormatter.format(value);
    return rtl ? '\u2067$text\u2069' : text;
  }

  final (min, max) = PriceBands.rangeOf(band);
  if (band == 0 && max != null) return l10n.priceUnder(amount(max));
  if (max == null) return l10n.priceAndAbove(amount(min));
  return l10n.priceBetween(amount(min), amount(max));
}

/// Sort (relevance only for a text search), price bands (multi-select), gift
/// type (SRS §5.8a), same-day / on-sale toggles and the deliver-to city. Edits a draft; nothing
/// changes on the list until "Show results".
class ProductFilterSheet extends ConsumerStatefulWidget {
  const ProductFilterSheet({super.key, required this.initial});

  final ProductQuery initial;

  @override
  ConsumerState<ProductFilterSheet> createState() => _ProductFilterSheetState();
}

class _ProductFilterSheetState extends ConsumerState<ProductFilterSheet> {
  late ProductQuery _draft = widget.initial;

  /// The order a list gets without an explicit sort.
  ProductSort get _defaultSort => _draft.hasText ? ProductSort.relevance : ProductSort.newest;

  // Choosing the default order clears the sort, so it doesn't count as a filter.
  void _setSort(ProductSort sort) => setState(() {
        _draft = sort == _defaultSort ? _draft.copyWith(clearSort: true) : _draft.copyWith(sort: sort);
      });

  void _toggleBand(int band) => setState(() {
        final bands = {..._draft.priceBands};
        if (!bands.remove(band)) bands.add(band);
        _draft = _draft.copyWith(priceBands: bands);
      });

  void _setGiftFor(GiftAudience? audience) => setState(() {
        _draft = audience == null ? _draft.copyWith(clearGiftFor: true) : _draft.copyWith(giftFor: audience);
      });

  void _setCity(String? cityId) => setState(() {
        _draft = cityId == null ? _draft.copyWith(clearCity: true) : _draft.copyWith(cityId: cityId);
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    final cities = ref.watch(activeCitiesProvider).valueOrNull ?? const [];
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sorts = [
      if (_draft.hasText) ProductSort.relevance,
      ProductSort.newest,
      ProductSort.popular,
      ProductSort.priceLowHigh,
      ProductSort.priceHighLow,
    ];
    final selectedSort = _draft.sort == ProductSort.relevance && !_draft.hasText ? _defaultSort : _draft.effectiveSort;

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
                      l10n.filters,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _draft = _draft.withoutFilters()),
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
                  _SectionTitle(l10n.sortBy),
                  _ChipWrap(
                    children: [
                      for (final sort in sorts)
                        CategoryChip(
                          label: productSortLabel(l10n, sort),
                          selected: selectedSort == sort,
                          onTap: () => _setSort(sort),
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
                  _SectionTitle(l10n.giftForTitle),
                  _ChipWrap(
                    children: [
                      CategoryChip(
                        label: l10n.giftForEveryone,
                        selected: _draft.giftFor == null,
                        onTap: () => _setGiftFor(null),
                      ),
                      for (final audience in GiftAudience.values)
                        CategoryChip(
                          label: audience.label(l10n),
                          icon: audience.icon,
                          selected: _draft.giftFor == audience,
                          onTap: () => _setGiftFor(audience),
                        ),
                    ],
                  ),
                  _SectionTitle(l10n.availability),
                  _SwitchRow(
                    label: l10n.sameDayOnly,
                    value: _draft.sameDayOnly,
                    onChanged: (v) => setState(() => _draft = _draft.copyWith(sameDayOnly: v)),
                  ),
                  _SwitchRow(
                    label: l10n.onSaleOnly,
                    value: _draft.discountOnly,
                    onChanged: (v) => setState(() => _draft = _draft.copyWith(discountOnly: v)),
                  ),
                  _SectionTitle(l10n.deliverTo),
                  _ChipWrap(
                    children: [
                      CategoryChip(
                        label: l10n.anyCity,
                        selected: _draft.cityId == null,
                        onTap: () => _setCity(null),
                      ),
                      for (final city in cities)
                        CategoryChip(
                          label: city.name.of(context),
                          selected: _draft.cityId == city.id,
                          onTap: () => _setCity(city.id),
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
              label: l10n.showResults,
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
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: children,
    );
  }
}

/// Label + switch on one tappable row (≥ 48 px).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyLarge.copyWith(color: AppColors.text(context)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Switch(
                value: value,
                onChanged: onChanged,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? AppColors.white : null,
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? gold : null,
                ),
                trackOutlineColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? gold : AppColors.line(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
