import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/firestore_parse.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/order_model.dart';
import 'order_section.dart';

/// "Refunded to your wallet: 8,000 IQD" under the totals of a cancelled /
/// refunded order (money returned by `cancelOrder` / refunds, SRS §5.12,
/// §5.18), with credits and balance apart when both were returned; opens
/// My Wallet.
class OrderRefundRow extends StatelessWidget {
  const OrderRefundRow({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = l10n.orderRefundedToWallet(CurrencyFormatter.format(order.refundedTotal));
    final both = order.refundedCredits > 0 && order.refundedBalance > 0;
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: AppColors.soft(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('order-refund'),
          onTap: () => unawaited(context.push(AppRoutes.wallet)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.sm + AppSpacing.xs, AppSpacing.sm,
                  AppSpacing.xs, AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 20, color: AppColors.gold(context)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            title,
                            key: const ValueKey('order-refund-total'),
                            style: AppTextStyles.label.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.goldText(context),
                            ),
                          ),
                        ),
                      ),
                      // chevron_right mirrors automatically in RTL.
                      Icon(Icons.chevron_right_rounded, color: AppColors.goldText(context)),
                    ],
                  ),
                  if (both)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: AppSpacing.lg + AppSpacing.xs, end: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AmountRow(
                            key: const ValueKey('order-refund-credits'),
                            label: l10n.walletCredits,
                            amount: order.refundedCredits,
                          ),
                          AmountRow(
                            key: const ValueKey('order-refund-balance'),
                            label: l10n.walletBalance,
                            amount: order.refundedBalance,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Who a gift-card order goes to — `orders/{id}.giftCard` (written by
/// `purchaseGiftCard`), read raw because [OrderModel] doesn't carry it.
class GiftCardRecipient {
  const GiftCardRecipient({required this.name, this.phone, this.email});
  final String name;
  final String? phone;
  final String? email;

  static GiftCardRecipient? fromOrderData(Map<String, dynamic>? data) {
    final card = FirestoreParse.map(data?['giftCard']);
    final name = FirestoreParse.stringOrNull(card['recipientName'])?.trim() ?? '';
    if (name.isEmpty) return null;
    return GiftCardRecipient(
      name: name,
      phone: FirestoreParse.stringOrNull(card['recipientPhone']),
      email: FirestoreParse.stringOrNull(card['recipientEmail']),
    );
  }
}

/// Same document as the order stream (the SDK shares the listener).
final orderGiftCardRecipientProvider = StreamProvider.autoDispose.family<GiftCardRecipient?, String>(
  (ref, orderId) => ref
      .watch(firestoreProvider)
      .doc(FirestorePaths.orderDoc(orderId))
      .snapshots()
      .map((s) => GiftCardRecipient.fromOrderData(s.data())),
);

/// Gift-card orders: the recipient instead of a delivery address. Hidden
/// until (or unless) the order names one.
class GiftCardRecipientSection extends ConsumerWidget {
  const GiftCardRecipientSection({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipient = ref.watch(orderGiftCardRecipientProvider(orderId)).valueOrNull;
    if (recipient == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final contact = [recipient.phone, recipient.email].whereType<String>().where((v) => v.trim().isNotEmpty);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: OrderSection(
        key: const ValueKey('order-gift-recipient'),
        title: l10n.giftCardRecipientTitle,
        icon: Icons.card_giftcard_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(recipient.name, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
            for (final c in contact)
              Text(
                c,
                textDirection: TextDirection.ltr,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
              ),
          ],
        ),
      ),
    );
  }
}
