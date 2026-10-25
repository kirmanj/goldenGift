import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/store_model.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/widgets/form_widgets.dart';
import '../../orders/order_detail_panel.dart';
import '../../orders/order_status_ui.dart';
import '../data/stores_admin_repository.dart';

/// Opens the order drawer as a dialog (the panel limits itself to the
/// seller's lines for partner accounts).
Future<void> showOrderDialog(BuildContext context, String orderId) => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: OrderDetailPanel(orderId: orderId, onClose: () => Navigator.pop(context)),
        ),
      ),
    );

/// "View sales" (SRS §9 Stores): the newest orders containing the store,
/// totals of ONLY this store's lines, and the commission due (estimate).
class StoreSalesCard extends ConsumerWidget {
  const StoreSalesCard({super.key, required this.store});
  final StoreModel store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(storeOrdersProvider(store.id));
    return SectionCard(
      title: 'Sales',
      children: [
        orders.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load the sales: $e'),
          data: (list) {
            final sales = StoreSales.of(list, store.id, store.commissionPercent);
            final fmt = DateFormat('MMM d, yyyy', 'en_US');
            final muted = TextStyle(color: AppColors.textMuted(context));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
                _Metric(label: 'Orders', value: '${sales.orderCount}'),
                _Metric(label: 'Items sold', value: '${sales.itemCount}'),
                _Metric(label: 'Sales (this store’s lines)', value: CurrencyFormatter.format(sales.total), gold: true),
                _Metric(
                  label: 'Commission due (${commissionLabel(store.commissionPercent)}) · estimate',
                  value: CurrencyFormatter.format(sales.commissionDue),
                ),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'From the newest ${StoresAdminRepository.salesOrders} orders containing this store. Cancelled, returned '
                'and refunded lines are not counted; other partners’ items in the same order are ignored.',
                style: muted,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text('No orders yet.', style: muted),
                )
              else
                for (final o in list)
                  _SalesRow(order: o, storeId: store.id, date: o.createdAt == null ? '' : fmt.format(o.createdAt!.toLocal())),
            ]);
          },
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.gold = false});
  final String label;
  final String value;
  final bool gold;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.soft(context),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context))),
          const SizedBox(height: AppSpacing.xxs),
          Text(value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: gold ? AppColors.goldText(context) : null,
                  )),
        ]),
      );
}

class _SalesRow extends StatelessWidget {
  const _SalesRow({required this.order, required this.storeId, required this.date});
  final OrderModel order;
  final String storeId;
  final String date;

  @override
  Widget build(BuildContext context) {
    final lines = storeLines(order, storeId);
    final qty = lines.fold(0, (n, l) => n + l.line.qty);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => showOrderDialog(context, order.id),
      title: Row(children: [
        Expanded(
          child: Text(order.orderNumber.isEmpty ? order.id : order.orderNumber,
              style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
        ),
        OrderStatusChip(order.status),
      ]),
      subtitle: Text([date, '$qty item(s) from this store'].where((s) => s.isNotEmpty).join(' · ')),
      trailing: Text(CurrencyFormatter.format(storeSalesTotal(order, storeId)),
          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.goldText(context))),
    );
  }
}
