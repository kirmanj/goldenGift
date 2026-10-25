import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import 'data/admin_orders_repository.dart';
import 'data/seller_orders.dart';
import 'order_detail_panel.dart';
import 'order_status_ui.dart';

/// SRS §9 Orders: filters (status, store, date, city, payment), live table,
/// detail drawer with status transitions and invoice print.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  OrderFilters _filters = const OrderFilters();
  int _limit = AdminOrdersRepository.pageSize;
  String? _selected;

  static const _panelBreakpoint = 1280.0;

  void _setFilters(OrderFilters f) => setState(() {
        _filters = f;
        _limit = AdminOrdersRepository.pageSize;
      });

  Future<void> _open(String id, bool sidePanel) async {
    if (sidePanel) {
      setState(() => _selected = id);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: OrderDetailPanel(orderId: id, onClose: () => Navigator.pop(context)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    // Sellers (Phase 8) only ever see their own store's orders.
    final filters = session?.role == AdminRole.seller ? _filters.copyWith(storeId: session!.storeId ?? '-') : _filters;
    final orders = ref.watch(adminOrdersProvider((filters, _limit)));
    final sidePanel = MediaQuery.sizeOf(context).width >= _panelBreakpoint;

    final list = Column(children: [
      _FilterBar(filters: _filters, onChanged: _setFilters, showStore: session?.role != AdminRole.seller),
      const Divider(height: 1),
      Expanded(
        child: orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('Could not load orders: $e\n\nA new filter combination may need a Firestore index '
                  '(see mobile/firestore.indexes.json).'),
            ),
          ),
          data: (list) => list.isEmpty
              ? const Center(child: Text('No orders match these filters.'))
              : ListView.separated(
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == list.length) {
                      return list.length < _limit
                          ? const SizedBox(height: AppSpacing.lg)
                          : Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Center(
                                child: OutlinedButton(
                                  onPressed: () => setState(() => _limit += AdminOrdersRepository.pageSize),
                                  child: const Text('Load more'),
                                ),
                              ),
                            );
                    }
                    final o = list[i];
                    return OrderRow(order: o, selected: o.id == _selected, onTap: () => _open(o.id, sidePanel));
                  },
                ),
        ),
      ),
    ]);

    return AdminScaffold(
      title: 'Orders',
      selectedRoute: AdminRoutes.orders,
      body: sidePanel && _selected != null
          ? Row(children: [
              Expanded(child: list),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 520,
                child: OrderDetailPanel(
                  key: ValueKey(_selected),
                  orderId: _selected!,
                  onClose: () => setState(() => _selected = null),
                ),
              ),
            ])
          : list,
    );
  }
}

class OrderRow extends ConsumerWidget {
  const OrderRow({super.key, required this.order, required this.onTap, this.selected = false});
  final OrderModel order;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final city = cities.where((c) => c.id == order.address?.city).firstOrNull?.name.en ?? order.address?.city ?? '';
    final fmt = DateFormat('MMM d, HH:mm', 'en_US');
    // Partners see only their own lines' count and total (SRS §9 Seller view).
    final session = ref.watch(adminSessionProvider);
    final view = session != null && session.isSeller ? sellerOrderView(order, session.storeId ?? '') : order;
    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.10),
      onTap: onTap,
      title: Row(children: [
        Expanded(
          child: Text(order.orderNumber.isEmpty ? order.id : order.orderNumber,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        if (awaitingOnlinePayment(order)) ...[const AwaitingPaymentChip(), const SizedBox(width: AppSpacing.xs)],
        OrderStatusChip(order.status),
      ]),
      subtitle: Text(
        [
          if (order.createdAt != null) fmt.format(order.createdAt!.toLocal()),
          order.address?.name ?? '',
          city,
          '${view.itemCount} item(s)',
          paymentMethodLabel(order.paymentMethod),
          if (order.isGift) 'Gift',
        ].where((s) => s.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(CurrencyFormatter.format(view.total), style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filters, required this.onChanged, required this.showStore});
  final OrderFilters filters;
  final ValueChanged<OrderFilters> onChanged;
  final bool showStore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final stores = showStore ? (ref.watch(orderStoreFilterProvider).valueOrNull ?? const []) : const [];
    final dateFmt = DateFormat('MMM d', 'en_US');
    final hasDates = filters.from != null || filters.to != null;

    Widget box<T>(String label, T? value, List<(T, String)> options, ValueChanged<T?> onSelect) => SizedBox(
          width: 190,
          child: DropdownButtonFormField<T?>(
            key: ValueKey('$label-$value'),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true),
            items: [
              DropdownMenuItem<T?>(value: null, child: Text('All ${label.toLowerCase()}')),
              for (final (v, l) in options) DropdownMenuItem<T?>(value: v, child: Text(l, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onSelect,
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
        box<OrderStatus>('Status', filters.status, [for (final s in OrderStatus.values) (s, orderStatusLabel(s))],
            (v) => onChanged(filters.copyWith(status: v, clearStatus: v == null))),
        box<String>('City', filters.cityId, [for (final c in cities) (c.id, c.name.en)],
            (v) => onChanged(filters.copyWith(cityId: v, clearCity: v == null))),
        box<PaymentMethod>('Payment', filters.paymentMethod,
            [for (final m in PaymentMethod.values) (m, paymentMethodLabel(m))],
            (v) => onChanged(filters.copyWith(paymentMethod: v, clearPayment: v == null))),
        if (showStore)
          box<String>('Store', filters.storeId, [for (final s in stores) (s.id, s.name.en)],
              (v) => onChanged(filters.copyWith(storeId: v, clearStore: v == null))),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_outlined),
          label: Text(hasDates
              ? '${filters.from == null ? '…' : dateFmt.format(filters.from!)} – ${filters.to == null ? '…' : dateFmt.format(filters.to!)}'
              : 'Any date'),
          onPressed: () async {
            final now = DateTime.now();
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime(now.year + 1),
              initialDateRange: filters.from != null && filters.to != null
                  ? DateTimeRange(start: filters.from!, end: filters.to!)
                  : null,
            );
            if (range != null) onChanged(filters.copyWith(from: range.start, to: range.end));
          },
        ),
        if (hasDates)
          IconButton(
            tooltip: 'Clear dates',
            onPressed: () => onChanged(filters.copyWith(clearDates: true)),
            icon: const Icon(Icons.clear),
          ),
        if (filters != const OrderFilters())
          TextButton(onPressed: () => onChanged(const OrderFilters()), child: const Text('Reset filters')),
      ]),
    );
  }
}
