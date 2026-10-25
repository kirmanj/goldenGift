import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/presentation/providers/cart_lines.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../../domain/checkout_rules.dart';
import 'checkout_options_sections.dart';

/// Step 5 — order summary (SRS §5.11): the lines, subtotal, the delivery
/// city's fee and the total; the minimum-order note when below it.
class CheckoutSummarySection extends StatelessWidget {
  const CheckoutSummarySection({
    super.key,
    required this.summary,
    required this.totals,
    this.minimumMessage,
  });

  final CartSummary summary;
  final CheckoutTotals totals;
  final String? minimumMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    return OrderSection(
      title: l10n.orderSummary,
      icon: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in summary.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs + AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${line.item.qty}×',
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700, color: muted),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.item.titleSnapshot.of(context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: line.counts ? AppColors.text(context) : muted,
                            decoration: line.counts ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        if (!line.counts)
                          Text(
                            l10n.itemUnavailable,
                            style: AppTextStyles.bodySmall.copyWith(color: errorText(context)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (line.counts)
                    Text(
                      CurrencyFormatter.format(line.effectiveLineTotal),
                      textDirection: TextDirection.ltr,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text(context)),
                    ),
                ],
              ),
            ),
          Divider(height: AppSpacing.lg, color: AppColors.line(context)),
          AmountRow(label: l10n.subtotal, amount: totals.subtotal),
          AmountRow(label: l10n.deliveryFee, amount: totals.deliveryFee),
          if (totals.discount > 0) AmountRow(label: l10n.discount, amount: totals.discount, negative: true),
          if (totals.creditsUsed + totals.walletUsed > 0)
            AmountRow(label: l10n.walletPayment, amount: totals.creditsUsed + totals.walletUsed, negative: true),
          AmountRow(label: l10n.total, amount: totals.total, emphasized: true),
          if (minimumMessage != null) CheckoutErrorLine(key: const ValueKey('minimum-order'), message: minimumMessage!),
        ],
      ),
    );
  }
}
