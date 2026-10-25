import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/promo_code_model.dart';

import '../../core/router/admin_routes.dart';
import '../orders/order_status_ui.dart' show OrderStatusChip;
import '../users/widgets/user_widgets.dart';
import 'data/promo_codes_data.dart';

Future<void> showPromoUsage(BuildContext context, PromoCodeModel promo) => showDialog<void>(
      context: context,
      builder: (_) => PromoUsageDialog(promo: promo),
    );

/// SRS §9 Promo codes "usage report": the counter, the orders that used the
/// code (latest 100) and their totals.
class PromoUsageDialog extends ConsumerWidget {
  const PromoUsageDialog({super.key, required this.promo});
  final PromoCodeModel promo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = AppColors.textMuted(context);
    final orders = ref.watch(promoUsageProvider(promo.code));

    Widget tile(String label, String value) => Container(
          width: 180,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(color: AppColors.soft(context), borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: muted)),
            Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.goldText(context))),
          ]),
        );

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, 0),
            child: Row(children: [
              Expanded(
                child: Text('Usage — ${promo.code}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ]),
          ),
          Expanded(
            child: orders.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text('Could not load the orders: $e\n\nThis report needs the orders (promoCode ASC, createdAt DESC) index.'),
                ),
              ),
              data: (list) {
                final totals = PromoUsageTotals.of(list);
                final summary = Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md, top: AppSpacing.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                      tile('Times used (counter)', promoUsesLabel(promo)),
                      tile('Orders', '${totals.orders}'),
                      tile('Discount given', CurrencyFormatter.format(totals.discount)),
                      tile('Revenue', CurrencyFormatter.format(totals.revenue)),
                    ]),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        'Discount and revenue (order totals) exclude cancelled, returned and refunded orders'
                            '${totals.excluded > 0 ? ' (${totals.excluded} excluded)' : ''}.',
                        if (list.length >= PromoAdminRepository.usageReportLimit)
                          'Only the latest ${PromoAdminRepository.usageReportLimit} orders are listed and summed.',
                      ].join(' '),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ]),
                );
                if (list.isEmpty) {
                  return ListView(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md), children: [
                    summary,
                    const Center(child: Text('No orders have used this code yet.')),
                  ]);
                }
                return ScrollableTable(
                  header: summary,
                  table: DataTable(
                    columnSpacing: AppSpacing.lg,
                    columns: const [
                      DataColumn(label: Text('Order')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Customer')),
                      DataColumn(label: Text('Subtotal'), numeric: true),
                      DataColumn(label: Text('Discount'), numeric: true),
                      DataColumn(label: Text('Total'), numeric: true),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: [
                      for (final o in list)
                        DataRow(key: ValueKey(o.id), cells: [
                          DataCell(SelectableText(o.orderNumber.isEmpty ? o.id : o.orderNumber)),
                          DataCell(Text(formatAdminDate(o.createdAt))),
                          DataCell(
                            Text(o.address?.name.isNotEmpty == true ? o.address!.name : o.userId,
                                style: TextStyle(color: AppColors.goldText(context), decoration: TextDecoration.underline)),
                            onTap: o.userId.isEmpty
                                ? null
                                : () {
                                    final router = GoRouter.of(context);
                                    Navigator.of(context).pop();
                                    router.go(AdminRoutes.user(o.userId));
                                  },
                          ),
                          DataCell(Text(CurrencyFormatter.format(o.subtotal))),
                          DataCell(Text(CurrencyFormatter.format(o.discount))),
                          DataCell(Text(CurrencyFormatter.format(o.total))),
                          DataCell(OrderStatusChip(o.status)),
                        ]),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
