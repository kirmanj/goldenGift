import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/app_settings_model.dart';

import '../../core/widgets/form_widgets.dart';
import 'settings_data.dart';
import 'settings_doc_editor.dart';

/// `app_settings/payments`: which methods Checkout offers (SRS §5.11, §6.14).
class PaymentsSettingsTab extends StatelessWidget {
  const PaymentsSettingsTab({super.key, this.onDirtyChanged});
  final ValueChanged<bool>? onDirtyChanged;

  @override
  Widget build(BuildContext context) => SettingsDocEditor<PaymentSettings>(
        docId: SettingsDocs.payments,
        fromMap: PaymentSettings.fromMap,
        toMap: (p) => p.toMap(),
        validate: validatePaymentSettings,
        onDirtyChanged: onDirtyChanged,
        builder: (context, d) {
          final p = d.value;
          Widget method(String title, String subtitle, bool value, PaymentSettings Function(PaymentSettings s, bool on) apply) =>
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(title),
                subtitle: Text(subtitle),
                value: value,
                onChanged: (v) => d.update((s) => apply(s, v)),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionCard(title: 'Always available', children: [
              method('Cash on delivery', 'Paid to the courier.', p.cashOnDelivery,
                  (s, v) => s.copyWith(cashOnDelivery: v)),
              method('Wallet / credits', 'Golden Gift balance, referral credits and redeemed gift cards.', p.wallet,
                  (s, v) => s.copyWith(wallet: v)),
            ]),
            const SizedBox(height: AppSpacing.md),
            SectionCard(title: 'Online gateways', children: [
              const SettingsNote(
                'Card, FastPay and ZainCash need gateway configuration, which arrives in Phase 9 (SRS §12 item 4). '
                'Leave them off until then — Checkout would offer a method that cannot complete a payment.',
                icon: Icons.warning_amber_outlined,
                color: AppColors.warning,
              ),
              const SizedBox(height: AppSpacing.sm),
              method('Card', 'Visa / Mastercard through the card gateway.', p.card, (s, v) => s.copyWith(card: v)),
              method('FastPay', 'FastPay e-wallet.', p.fastPay, (s, v) => s.copyWith(fastPay: v)),
              method('ZainCash', 'ZainCash e-wallet.', p.zainCash, (s, v) => s.copyWith(zainCash: v)),
            ]),
          ]);
        },
      );
}
