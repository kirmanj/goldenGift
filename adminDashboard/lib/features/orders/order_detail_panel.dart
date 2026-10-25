import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/session/admin_session.dart';
import '../../core/web/browser.dart';
import '../../core/widgets/form_widgets.dart';
import '../stores/data/callable_errors.dart';
import 'data/admin_orders_repository.dart';
import 'data/seller_orders.dart';
import 'invoice.dart';
import 'order_status_ui.dart';

/// Everything ops needs for one order (SRS §9 Orders): customer + address,
/// delivery slot, gift message, lines with personalization and photo
/// download, totals, timeline, status buttons and invoice print.
///
/// Partner accounts (SRS §9 "Seller view") see only their own lines (no other
/// store's prices, no order totals) and move only those lines through the
/// `updateOrderItems` function.
class OrderDetailPanel extends ConsumerWidget {
  const OrderDetailPanel({super.key, required this.orderId, this.onClose});
  final String orderId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(adminOrderProvider(orderId));
    return order.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load the order: $e')),
      data: (o) => o == null ? const Center(child: Text('This order no longer exists.')) : _Body(order: o, onClose: onClose),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.order, this.onClose});
  final OrderModel order;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final cityName = cities.where((c) => c.id == order.address?.city).firstOrNull?.name.en ?? order.address?.city ?? '';
    final sellerStore = session != null && session.isSeller ? (session.storeId ?? '') : null;
    final seller = sellerStore != null;
    final view = seller ? sellerOrderView(order, sellerStore) : order;
    final linesStatus = seller ? sellerLinesStatus(view.items) : null;
    final awaiting = awaitingOnlinePayment(order);
    final allowed = session == null
        ? const <OrderStatus>[]
        : seller
            ? sellerTransitions(linesStatus)
            : staffTransitions(session, order.status);
    // Until the online payment arrives only a cancellation is possible.
    final next = awaiting ? allowed.where(statusNeedsNote).toList() : allowed;
    final a = order.address;
    final fmt = DateFormat('yyyy-MM-dd HH:mm', 'en_US');
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(children: [
          Expanded(
            child: SelectableText(order.orderNumber.isEmpty ? order.id : order.orderNumber,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (awaiting) ...[const AwaitingPaymentChip(), const SizedBox(width: AppSpacing.xs)],
          OrderStatusChip(order.status),
          if (onClose != null) IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close)),
        ]),
        if (awaiting)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Waiting for the ${paymentMethodLabel(order.paymentMethod)} payment — don\'t prepare this order yet. '
              'It is cancelled automatically if it isn\'t paid in time.',
              style: const TextStyle(color: AppColors.warning),
            ),
          ),
        if (seller && linesStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(children: [
              Text('Your items: ', style: TextStyle(color: AppColors.textMuted(context))),
              OrderStatusChip(linesStatus),
            ]),
          ),
        Text(
          [
            if (order.createdAt != null) 'Placed ${fmt.format(order.createdAt!.toLocal())}',
            seller ? '${view.itemCount} of your item(s)' : '${order.itemCount} item(s)',
            if (order.orderType != OrderType.standard) order.orderType.name,
          ].join(' · '),
          style: TextStyle(color: AppColors.textMuted(context)),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          for (final s in next)
            statusNeedsNote(s)
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: () => _move(context, ref, session!, s),
                    child: Text(seller ? 'Your items: ${orderStatusLabel(s).toLowerCase()}' : orderStatusLabel(s)),
                  )
                : FilledButton(
                    onPressed: () => _move(context, ref, session!, s),
                    child: Text(seller
                        ? 'Mark your items ${orderStatusLabel(s).toLowerCase()}'
                        : 'Mark ${orderStatusLabel(s).toLowerCase()}')),
          OutlinedButton.icon(
            onPressed: () => printInvoice(seller
                ? invoiceHtml(sellerOrderView(order, sellerStore, packingSlip: true), cityName: cityName)
                : invoiceHtml(order, cityName: cityName)),
            icon: const Icon(Icons.print_outlined),
            label: Text(seller || order.hidePrices ? 'Print packing slip' : 'Print invoice'),
          ),
        ]),
        if (session != null && next.isEmpty && !(seller ? (linesStatus?.isFinal ?? true) : order.status.isFinal))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text('Your role can view this order but not change its status.',
                style: TextStyle(color: AppColors.textMuted(context))),
          ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(title: 'Customer & delivery', children: [
          _kv(context, 'Recipient', a == null ? '—' : '${a.name} · ${a.phone}', copy: a?.phone),
          _kv(context, 'Address', a == null ? '—' : '$cityName — ${a.oneLine}'),
          if (a != null && a.notes.isNotEmpty) _kv(context, 'Notes', a.notes),
          _kv(context, 'Delivery',
              '${order.deliveryDate == null ? '—' : AppDates.display(order.deliveryDate!)}${order.deliverySlot == null ? '' : ' · ${order.deliverySlot}'}'),
          if (!seller) _kv(context, 'Customer id', order.userId, copy: order.userId),
        ]),
        if (order.isGift) ...[
          const SizedBox(height: AppSpacing.md),
          SectionCard(title: 'Gift', children: [
            _kv(context, 'Prices on invoice', order.hidePrices ? 'Hidden' : 'Shown'),
            _kv(context, 'Message', (order.giftMessage?.isEmpty ?? true) ? '—' : order.giftMessage!),
          ]),
        ],
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: seller ? 'Your items' : 'Items',
          children: [
            if (seller && view.items.isEmpty) const Text('None of this order’s items are from your store.'),
            for (final item in view.items) _ItemTile(item: item),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (seller)
          SectionCard(title: 'Payment', children: [
            _kv(context, 'Method', paymentMethodLabel(order.paymentMethod)),
            _kv(context, 'Status', order.paymentStatus.name),
            const Divider(),
            _money(context, 'Your items total', view.total, bold: true),
          ])
        else
          SectionCard(title: 'Payment', children: [
            _kv(context, 'Method', paymentMethodLabel(order.paymentMethod)),
            _kv(context, 'Status', order.paymentStatus.name),
            if (order.paymentRef != null) _kv(context, 'Reference', order.paymentRef!, copy: order.paymentRef),
            const Divider(),
            _money(context, 'Subtotal', order.subtotal),
            if (order.discount > 0) _money(context, 'Discount${order.promoCode == null ? '' : ' (${order.promoCode})'}', -order.discount),
            _money(context, 'Delivery', order.deliveryFee),
            if (order.creditsUsed > 0) _money(context, 'Referral credits', -order.creditsUsed),
            if (order.walletUsed > 0) _money(context, 'Wallet', -order.walletUsed),
            _money(context, 'Total', order.total, bold: true),
          ]),
        const SizedBox(height: AppSpacing.md),
        SectionCard(title: 'Timeline', children: [_Timeline(orderId: order.id)]),
        if (order.cancelReason != null) ...[
          const SizedBox(height: AppSpacing.md),
          SectionCard(title: 'Cancellation', children: [Text(order.cancelReason!)]),
        ],
      ],
    );
  }

  Future<void> _move(BuildContext context, WidgetRef ref, AdminSession session, OrderStatus next) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _StatusNoteDialog(next: next),
    );
    if (note == null || !context.mounted) return;
    if (session.isSeller) {
      try {
        await ref.read(sellerOrdersRepositoryProvider).updateItems(orderId: order.id, status: next, note: note);
        if (context.mounted) showMessage(context, '${order.orderNumber}: your items → ${orderStatusLabel(next)}');
      } catch (e) {
        if (context.mounted) showMessage(context, callableErrorMessage('updateOrderItems', e, action: 'update your items'));
      }
      return;
    }
    try {
      await ref.read(adminOrdersRepositoryProvider).changeStatus(order: order, next: next, adminUid: session.uid, note: note);
      if (context.mounted) showMessage(context, '${order.orderNumber} → ${orderStatusLabel(next)}');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Could not update the status: $e');
    }
  }

  Widget _kv(BuildContext context, String k, String v, {String? copy}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: AppColors.textMuted(context)))),
          Expanded(child: SelectableText(v)),
          if (copy != null && copy.isNotEmpty)
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copy));
                showMessage(context, 'Copied');
              },
              icon: const Icon(Icons.copy),
            ),
        ]),
      );

  Widget _money(BuildContext context, String k, int v, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(children: [
        Expanded(child: Text(k, style: style)),
        Text(v < 0 ? '−${CurrencyFormatter.format(-v)}' : CurrencyFormatter.format(v), style: style),
      ]),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});
  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final l = item.line;
    final photos = [for (final s in l.selections) ...s.urls];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 56,
              height: 56,
              child: l.imageSnapshot == null
                  ? ColoredBox(color: AppColors.field(context), child: const Icon(Icons.image_outlined))
                  : Image.network(l.imageSnapshot!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.titleSnapshot.en, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${l.qty} × ${CurrencyFormatter.format(l.unitPrice)} = ${CurrencyFormatter.format(l.lineTotal)}'),
              for (final s in l.selections.where((s) => s.urls.isEmpty))
                Text('${s.label.en}: ${_value(s)}', style: TextStyle(color: AppColors.textMuted(context))),
            ]),
          ),
          if (item.status != OrderStatus.pending) OrderStatusChip(item.status),
        ]),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Text('Customer photos (${photos.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                for (final url in photos) {
                  openInNewTab(url);
                }
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Open all'),
            ),
          ]),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            for (final url in photos)
              InkWell(
                onTap: () => openInNewTab(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Image.network(url, width: 72, height: 72, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72, child: Icon(Icons.broken_image_outlined))),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  static String _value(CartSelection s) =>
      s.valueLabel?.en ?? s.text ?? (s.date != null ? AppDates.display(s.date!) : null) ?? s.hex ?? '';
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(adminOrderHistoryProvider(orderId));
    final fmt = DateFormat('yyyy-MM-dd HH:mm', 'en_US');
    return history.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Could not load the timeline: $e'),
      data: (entries) => entries.isEmpty
          ? Text('No history yet (written by the onOrderStatusChange function).',
              style: TextStyle(color: AppColors.textMuted(context)))
          : Column(children: [
              for (final e in entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.circle, size: 12, color: orderStatusColor(e.status)),
                  title: Text(orderStatusLabel(e.status)),
                  subtitle: Text([
                    if (e.at != null) fmt.format(e.at!.toLocal()),
                    if (e.byRole != null) 'by ${e.byRole}',
                    if (e.note != null) '“${e.note}”',
                  ].join(' · ')),
                ),
            ]),
    );
  }
}

/// Confirms a status change; cancellations / returns / refunds need a reason
/// (it is shown to the customer).
class _StatusNoteDialog extends StatefulWidget {
  const _StatusNoteDialog({required this.next});
  final OrderStatus next;

  @override
  State<_StatusNoteDialog> createState() => _StatusNoteDialogState();
}

class _StatusNoteDialogState extends State<_StatusNoteDialog> {
  final _note = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final required = statusNeedsNote(widget.next);
    return AlertDialog(
      title: Text('Move to “${orderStatusLabel(widget.next)}”?'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: TextFormField(
            controller: _note,
            autofocus: true,
            maxLength: 300,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: required ? 'Reason (shown to the customer) *' : 'Note for the customer (optional)',
            ),
            validator: (v) => required && (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: required ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () {
            if (_form.currentState!.validate()) Navigator.pop(context, _note.text.trim());
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
