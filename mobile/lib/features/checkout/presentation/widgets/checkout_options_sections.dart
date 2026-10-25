import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../orders/presentation/widgets/order_labels.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../providers/checkout_providers.dart';

/// Step 3 — gift options (SRS §5.11): "This is a gift" → hide prices on the
/// invoice + a gift message of at most 200 characters.
class CheckoutGiftSection extends StatelessWidget {
  const CheckoutGiftSection({
    super.key,
    required this.isGift,
    required this.hidePrices,
    required this.messageController,
    required this.onGiftChanged,
    required this.onHidePricesChanged,
    required this.onMessageChanged,
  });

  final bool isGift;
  final bool hidePrices;
  final TextEditingController messageController;
  final ValueChanged<bool> onGiftChanged;
  final ValueChanged<bool> onHidePricesChanged;
  final ValueChanged<String> onMessageChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OrderSection(
      title: l10n.giftOptions,
      icon: Icons.card_giftcard_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SwitchRow(
            key: const ValueKey('gift-switch'),
            label: l10n.thisIsAGift,
            value: isGift,
            onChanged: onGiftChanged,
          ),
          if (isGift) ...[
            _SwitchRow(
              key: const ValueKey('hide-prices-switch'),
              label: l10n.hidePricesOnInvoice,
              value: hidePrices,
              onChanged: onHidePricesChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            GGInput(
              key: const ValueKey('gift-message'),
              label: l10n.giftMessage,
              hint: l10n.giftMessageHint,
              controller: messageController,
              multiline: true,
              minLines: 3,
              maxLines: 6,
              maxLength: CheckoutController.giftMessageMax,
              showCounter: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: onMessageChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        value: value,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
        dense: false,
        title: Text(label, style: AppTextStyles.label.copyWith(fontSize: 15, color: AppColors.text(context))),
      );
}

/// Step 4 — payment method (SRS §5.11). Shows the methods enabled in
/// `app_settings/payments`; card / FastPay are listed but can't be chosen yet.
class CheckoutPaymentSection extends StatelessWidget {
  const CheckoutPaymentSection({
    super.key,
    required this.methods,
    required this.selected,
    required this.onChanged,
  });

  final List<(PaymentMethod, bool)> methods;
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;

  IconData _icon(PaymentMethod m) => switch (m) {
        PaymentMethod.cashOnDelivery => Icons.payments_outlined,
        PaymentMethod.wallet => Icons.account_balance_wallet_outlined,
        PaymentMethod.zainCash => Icons.smartphone_rounded,
        _ => Icons.credit_card_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OrderSection(
      title: l10n.paymentMethod,
      icon: Icons.account_balance_wallet_outlined,
      child: RadioGroup<PaymentMethod>(
        groupValue: selected,
        onChanged: (m) {
          if (m != null) onChanged(m);
        },
        child: Column(
          children: [
            for (final (method, usable) in methods)
              Opacity(
                opacity: usable ? 1 : 0.5,
                child: RadioListTile<PaymentMethod>(
                  key: ValueKey('payment-${method.name}'),
                  value: method,
                  enabled: usable,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(_icon(method), color: AppColors.gold(context)),
                  title: Text(
                    paymentMethodLabel(l10n, method),
                    style: AppTextStyles.label.copyWith(fontSize: 15, color: AppColors.text(context)),
                  ),
                  subtitle: method == PaymentMethod.zainCash
                      ? Text(
                          l10n.paymentZainCashHint,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Blocks the page while `placeOrder` runs (SRS §5.11) — or, with
/// [message], while the online payment starts.
class PlacingOrderOverlay extends StatelessWidget {
  const PlacingOrderOverlay({super.key, this.message});

  /// Replaces "Placing your order…".
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Positioned.fill(
      key: const ValueKey('placing-overlay'),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            ModalBarrier(dismissible: false, color: AppColors.black.withValues(alpha: 0.45)),
            Center(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.xl),
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 36,
                        child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.gold(context)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        message ?? l10n.placingOrder,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A red line under a section (city / minimum-order problems).
class CheckoutErrorLine extends StatelessWidget {
  const CheckoutErrorLine({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: errorText(context)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: errorText(context)),
              ),
            ),
          ],
        ),
      );
}
