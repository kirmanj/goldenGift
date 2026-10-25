import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../promo_codes/presentation/providers/cart_pricing.dart';
import '../../../promo_codes/presentation/widgets/promo_code_field.dart';
import '../../../wallet/data/wallet_repository.dart';
import '../../../wallet/presentation/widgets/use_credits_toggle.dart';
import '../../../wallet/presentation/widgets/wallet_ui.dart';
import '../providers/cart_lines.dart';

/// Totals + Checkout (SRS §5.10): subtotal, delivery (priced per city at
/// checkout), promo code field, "Use my credits" toggle (signed-in customers
/// with credits only), promo / credits deductions and the total
/// (subtotal − discount − credits). Checkout reads the same providers
/// ([cartPricingProvider], [appliedPromoProvider], [useCreditsProvider]).
class CartSummaryCard extends ConsumerWidget {
  const CartSummaryCard({super.key, required this.summary, required this.onCheckout});

  final CartSummary summary;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final text = AppColors.text(context);
    final credits = ref.watch(availableCreditsProvider);
    // Priced from the summary on screen (it may be the last complete one
    // while product docs reload).
    final pricing = CartPricing.compute(
      subtotal: summary.subtotal,
      promo: ref.watch(currentPromoResultProvider),
      credits: credits,
      useCredits: ref.watch(useCreditsProvider),
    );

    Widget row(String label, Widget value, {TextStyle? labelStyle, Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(label, style: labelStyle ?? AppTextStyles.bodyLarge.copyWith(color: muted)),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(child: value),
            ],
          ),
        );
    Widget valueText(String value, TextStyle style) => Text(value, textAlign: TextAlign.end, style: style);
    final deductionStyle =
        AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600, color: successTextColor(context));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line(context)),
        boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            l10n.subtotal,
            valueText(
              CurrencyFormatter.format(summary.subtotal),
              AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600, color: text),
            ),
          ),
          row(
            l10n.deliveryFee,
            valueText(l10n.deliveryCalculatedAtCheckout, AppTextStyles.bodyMedium.copyWith(color: muted)),
          ),
          const SizedBox(height: AppSpacing.sm),
          const PromoCodeField(),
          if (credits > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            UseCreditsToggle(available: credits),
          ],
          if (pricing.discount > 0)
            row(
              l10n.promoDiscountRow(pricing.promoCode ?? ''),
              AmountText(deductionAmount(pricing.discount), style: deductionStyle, textAlign: TextAlign.end),
              key: const ValueKey('cart-discount-row'),
            ),
          if (pricing.creditsUsed > 0)
            row(
              l10n.walletCredits,
              AmountText(deductionAmount(pricing.creditsUsed), style: deductionStyle, textAlign: TextAlign.end),
              key: const ValueKey('cart-credits-row'),
            ),
          Divider(height: AppSpacing.lg, color: AppColors.line(context)),
          row(
            l10n.total,
            valueText(
              CurrencyFormatter.format(pricing.total),
              AppTextStyles.heading3.copyWith(color: AppColors.goldText(context)),
            ),
            labelStyle: AppTextStyles.heading3.copyWith(color: text),
            key: const ValueKey('cart-total-row'),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: l10n.checkout,
            onPressed: summary.canCheckout ? onCheckout : null,
          ),
        ],
      ),
    );
  }
}
