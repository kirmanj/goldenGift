import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/cart_item_model.dart';
import '../../../product_details/presentation/widgets/option_formatting.dart';
import '../providers/cart_lines.dart';
import 'quantity_stepper.dart';

/// "Frame: Walnut · Text: Happy B-day · 2 photos" (SRS §5.10).
String cartSelectionSummary(BuildContext context, CartItemModel item) {
  final l10n = AppLocalizations.of(context)!;
  final parts = <String>[];
  for (final s in item.selections) {
    final String? value;
    if (s.valueLabel != null) {
      value = s.valueLabel!.of(context);
    } else if (s.text != null) {
      value = s.text;
    } else if (s.date != null) {
      value = formatOptionDate(s.date!);
    } else {
      value = null; // photos are counted once at the end
    }
    if (value == null || value.isEmpty) continue;
    final label = s.label.of(context);
    parts.add(label.isEmpty ? value : '$label: $value');
  }
  if (item.photoCount > 0) parts.add(l10n.photosCount(item.photoCount));
  return parts.join(' · ');
}

/// One cart line (SRS §5.10): image, title, selection summary, unit price,
/// quantity stepper and remove. Unavailable lines are dimmed with an
/// error-red note (and excluded from totals by `CartSummary`); a changed
/// price shows the new one.
class CartLineTile extends StatelessWidget {
  const CartLineTile({
    super.key,
    required this.line,
    required this.maxQty,
    required this.onQtyChanged,
    required this.onRemove,
  });

  final CartLine line;
  final int maxQty;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onRemove;

  static const double imageSize = 76;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final item = line.item;
    final unavailable = line.status == CartLineStatus.unavailable;
    final priceChanged = line.status == CartLineStatus.priceChanged && line.currentUnitPrice != null;
    final summary = cartSelectionSummary(context, item);
    final dim = unavailable ? 0.5 : 1.0;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.sm + AppSpacing.xs,
        AppSpacing.sm + AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.sm + AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: unavailable ? AppColors.error.withValues(alpha: 0.5) : AppColors.line(context),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: dim,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox.square(
                dimension: imageSize,
                child: GGNetworkImage(url: item.imageSnapshot),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Opacity(
                          opacity: dim,
                          child: Text(
                            item.titleSnapshot.of(context),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.label.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                              color: AppColors.text(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.remove,
                      onPressed: onRemove,
                      icon: Icon(Icons.delete_outline_rounded, color: AppColors.textMuted(context)),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (summary.isNotEmpty)
                        Opacity(
                          opacity: dim,
                          child: Text(
                            summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
                          ),
                        ),
                      if (unavailable) ...[
                        const SizedBox(height: AppSpacing.xs),
                        _LineNote(
                          icon: Icons.error_outline_rounded,
                          text: l10n.itemUnavailable,
                          color: errorTextColor(context),
                        ),
                      ],
                      if (priceChanged) ...[
                        const SizedBox(height: AppSpacing.xs),
                        _LineNote(
                          icon: Icons.info_outline_rounded,
                          text: l10n.priceChangedNote(CurrencyFormatter.format(line.currentUnitPrice!)),
                          color: AppColors.goldText(context),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            Opacity(
                              opacity: dim,
                              child: PriceText(price: line.currentUnitPrice ?? item.unitPrice),
                            ),
                            QuantityStepper(
                              value: item.qty,
                              max: maxQty < item.qty ? item.qty : maxQty,
                              onChanged: unavailable ? null : onQtyChanged,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineNote extends StatelessWidget {
  const _LineNote({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }
}
