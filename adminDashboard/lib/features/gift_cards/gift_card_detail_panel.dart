import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/form_widgets.dart';
import '../stores/widgets/detail_widgets.dart';
import '../stores/widgets/store_sales_card.dart' show showOrderDialog;
import 'data/gift_cards_admin_repository.dart';
import 'gift_card_ui.dart';

String formatCardDate(DateTime? d) => d == null ? '—' : DateFormat('yyyy-MM-dd HH:mm', 'en_US').format(d.toLocal());

/// Issued-card drawer: everything about one card, plus Disable.
class GiftCardDetailPanel extends ConsumerWidget {
  const GiftCardDetailPanel({super.key, required this.cardId, this.onClose});
  final String cardId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(adminGiftCardProvider(cardId));
    return card.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load the card: $e')),
      data: (c) => c == null ? const Center(child: Text('This card no longer exists.')) : _Body(card: c, onClose: onClose),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.card, this.onClose});
  final AdminGiftCard card;
  final VoidCallback? onClose;

  Future<void> _disable(BuildContext context, WidgetRef ref, AdminSession session) async {
    final reason = await showReasonDialog(
      context,
      title: 'Disable ${card.card.formattedCode}?',
      message: 'The card can no longer be redeemed. Its balance (${CurrencyFormatter.format(card.card.balance)}) is not refunded automatically.',
      confirmLabel: 'Disable',
      destructive: true,
      maxLength: 300,
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(giftCardsAdminRepositoryProvider).disableCard(card, reason: reason, adminUid: session.uid);
      if (context.mounted) showMessage(context, 'Card disabled');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Could not disable the card: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    final templates = ref.watch(adminGiftCardTemplatesProvider).valueOrNull ?? const [];
    final c = card.card;
    final template = templates.where((t) => t.id == c.templateId).firstOrNull;
    final templateName = c.templateName.en.isNotEmpty ? c.templateName.en : (template?.name.en ?? c.templateId);
    final theme = Theme.of(context);
    final canDisable = session != null && GiftCardsAccess.canDisable(session.role) && canDisableCard(c.status);
    Widget link(String text, VoidCallback onTap) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.goldText(context), padding: EdgeInsets.zero),
            onPressed: onTap,
            child: Text(text, overflow: TextOverflow.ellipsis),
          ),
        );
    return ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
      Row(children: [
        Expanded(
          child: SelectableText(c.formattedCode,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        ),
        GiftCardStatusChip(c.status),
        if (onClose != null) IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close)),
      ]),
      const SizedBox(height: AppSpacing.md),
      Center(
        child: GiftCardPreview(
          name: templateName,
          amount: c.amount,
          gradientStart: c.gradientStart ?? template?.gradientStart,
          gradientEnd: c.gradientEnd ?? template?.gradientEnd,
          artworkUrl: c.photoUrl ?? template?.artworkUrl,
          code: c.formattedCode,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      if (canDisable)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: () => _disable(context, ref, session),
            icon: const Icon(Icons.block),
            label: const Text('Disable card'),
          ),
        ),
      const SizedBox(height: AppSpacing.md),
      SectionCard(title: 'Card', children: [
        KeyValueRow('Code', c.formattedCode, copy: c.formattedCode),
        KeyValueRow('Template', templateName),
        KeyValueRow('Amount', CurrencyFormatter.format(c.amount)),
        KeyValueRow('Balance', CurrencyFormatter.format(c.balance)),
        KeyValueRow('Status', giftCardStatusLabel(c.status)),
        if (card.disabledReason != null) KeyValueRow('Disabled because', card.disabledReason!),
        KeyValueRow('Message', c.message),
      ]),
      const SizedBox(height: AppSpacing.md),
      SectionCard(title: 'People', children: [
        KeyValueRow('Purchaser', c.purchaserUid,
            child: c.purchaserUid.isEmpty ? const Text('— (issued by an admin)') : link(c.purchaserUid, () => context.go(AdminRoutes.user(c.purchaserUid)))),
        KeyValueRow('Recipient', c.recipientName),
        KeyValueRow('Phone', c.recipientPhone ?? '', copy: c.recipientPhone),
        KeyValueRow('Email', c.recipientEmail ?? '', copy: c.recipientEmail),
        if (c.recipientUid != null)
          KeyValueRow('Recipient account', c.recipientUid!, child: link(c.recipientUid!, () => context.go(AdminRoutes.user(c.recipientUid!)))),
      ]),
      const SizedBox(height: AppSpacing.md),
      SectionCard(title: 'Dates', children: [
        KeyValueRow('Created', formatCardDate(card.createdAt)),
        if (c.scheduledAt != null) KeyValueRow('Scheduled', formatCardDate(c.scheduledAt)),
        KeyValueRow('Sent', formatCardDate(c.sentAt)),
        KeyValueRow('Expires', formatCardDate(c.expiresAt)),
        KeyValueRow('Redeemed', formatCardDate(c.redeemedAt)),
        if (card.disabledAt != null) KeyValueRow('Disabled', formatCardDate(card.disabledAt)),
      ]),
      if (c.orderId != null) ...[
        const SizedBox(height: AppSpacing.md),
        SectionCard(title: 'Order', children: [
          KeyValueRow('Order', c.orderId!, child: link('Open order ${c.orderId}', () => showOrderDialog(context, c.orderId!))),
        ]),
      ],
    ]);
  }
}
