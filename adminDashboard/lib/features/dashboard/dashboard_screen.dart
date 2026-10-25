import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../seller/data/seller_kpis.dart';
import 'data/dashboard_kpis.dart';
import 'widgets/dashboard_widgets.dart';

/// Server-side count of a collection (aggregate query: 1 read per 1000 docs).
final _countProvider = FutureProvider.autoDispose.family<int, String>((ref, collection) async {
  final snap = await ref.watch(firestoreProvider).collection(collection).count().get();
  return snap.count ?? 0;
});

/// SRS §9 Dashboard. Staff get today's KPIs (Iraq day: orders, revenue,
/// pending orders, new users, AI searches), orders per day for 14 days, top
/// products, the low-stock list and catalogue counts; every block loads on
/// its own (skeleton, inline error with retry). Partner accounts get their
/// own store's KPIs instead (SRS §9 Seller view).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    if (session != null && session.isSeller) {
      return AdminScaffold(
        title: 'Dashboard',
        selectedRoute: AdminRoutes.dashboard,
        body: SellerDashboardBody(storeId: session.storeId ?? ''),
      );
    }
    return AdminScaffold(
      title: 'Dashboard',
      selectedRoute: AdminRoutes.dashboard,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => refreshStaffDashboard(ref),
        ),
      ],
      body: const StaffDashboardBody(),
    );
  }
}

/// Re-runs every query of the staff dashboard.
void refreshStaffDashboard(WidgetRef ref) {
  for (final p in [
    kpiOrdersTodayProvider,
    kpiRevenueTodayProvider,
    kpiPendingOrdersProvider,
    kpiNewUsersProvider,
    kpiAiSearchesProvider,
    ordersPerDayProvider,
    topProductsProvider,
    lowStockProvider,
  ]) {
    ref.invalidate(p);
  }
  ref.invalidate(_countProvider);
}

class StaffDashboardBody extends ConsumerWidget {
  const StaffDashboardBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(dashboardClockProvider)();
    final today = IraqDay.of(now);
    final number = NumberFormat.decimalPattern('en_US');
    String n(int v) => number.format(v);
    final muted = TextStyle(color: AppColors.textMuted(context));

    final kpis = [
      KpiTile(
        label: 'Orders today',
        icon: Icons.today_outlined,
        value: ref.watch(kpiOrdersTodayProvider).whenData(n),
        onRetry: () => ref.invalidate(kpiOrdersTodayProvider),
        caption: 'All statuses',
        onTap: () => context.go(AdminRoutes.orders),
      ),
      KpiTile(
        label: 'Revenue today',
        icon: Icons.payments_outlined,
        value: ref.watch(kpiRevenueTodayProvider).whenData(CurrencyFormatter.format),
        onRetry: () => ref.invalidate(kpiRevenueTodayProvider),
        caption: 'Without cancelled / returned / refunded',
        onTap: () => context.go(AdminRoutes.orders),
      ),
      KpiTile(
        label: 'Pending orders',
        icon: Icons.pending_actions_outlined,
        value: ref.watch(kpiPendingOrdersProvider).whenData(n),
        onRetry: () => ref.invalidate(kpiPendingOrdersProvider),
        caption: 'Waiting for confirmation',
        onTap: () => context.go(AdminRoutes.orders),
      ),
      KpiTile(
        label: 'New users today',
        icon: Icons.person_add_alt_outlined,
        value: ref.watch(kpiNewUsersProvider).whenData(n),
        onRetry: () => ref.invalidate(kpiNewUsersProvider),
        caption: 'Accounts created',
        onTap: () => context.go(AdminRoutes.users),
      ),
      KpiTile(
        label: 'AI searches today',
        icon: Icons.auto_awesome_outlined,
        value: ref.watch(kpiAiSearchesProvider).whenData(n),
        onRetry: () => ref.invalidate(kpiAiSearchesProvider),
        caption: 'AI Gift Search queries',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Today · ${DateFormat('EEE, MMM d', 'en_US').format(today.date)} · Iraq time (UTC+3)', style: muted),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: kpis),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(builder: (context, c) {
          const chart = _OrdersChartCard();
          const top = _TopProductsCard();
          if (c.maxWidth < 1000) {
            return const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              chart,
              SizedBox(height: AppSpacing.md),
              top,
            ]);
          }
          return const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: chart),
            SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: top),
          ]);
        }),
        const SizedBox(height: AppSpacing.md),
        const _LowStockCard(),
        const SizedBox(height: AppSpacing.lg),
        Text('Catalogue', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        const _CatalogueCounts(),
      ],
    );
  }
}

class _OrdersChartCard extends ConsumerWidget {
  const _OrdersChartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(ordersPerDayProvider);
    final total = days.valueOrNull?.fold<int>(0, (n, d) => n + d.count);
    return SectionCard(
      title: 'Orders per day · last ${DashboardRepository.chartDays} days',
      trailing: total == null ? null : Text('$total total', style: TextStyle(color: AppColors.textMuted(context))),
      children: [
        if (days.isLoading || !(days.hasValue || days.hasError))
          const SkeletonBox(height: OrdersPerDayChart.height)
        else if (days.hasError)
          SizedBox(
            height: OrdersPerDayChart.height,
            child: Center(child: InlineError(onRetry: () => ref.invalidate(ordersPerDayProvider))),
          )
        else
          OrdersPerDayChart(days: days.requireValue),
      ],
    );
  }
}

/// Loading / error / list frame shared by the two product lists.
Widget _productList(
  BuildContext context,
  AsyncValue<List<ProductModel>> value, {
  required VoidCallback onRetry,
  required String empty,
  required Widget Function(int index, ProductModel p) row,
}) {
  if (value.isLoading || !(value.hasValue || value.hasError)) {
    return Column(children: [
      for (var i = 0; i < 4; i++)
        const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: SkeletonBox(height: 20)),
    ]);
  }
  if (value.hasError) return InlineError(onRetry: onRetry);
  final list = value.requireValue;
  if (list.isEmpty) return Text(empty, style: TextStyle(color: AppColors.textMuted(context)));
  return Column(children: [for (var i = 0; i < list.length; i++) row(i, list[i])]);
}

class _TopProductsCard extends ConsumerWidget {
  const _TopProductsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final number = NumberFormat.decimalPattern('en_US');
    return SectionCard(
      title: 'Top products',
      children: [
        _productList(
          context,
          ref.watch(topProductsProvider),
          onRetry: () => ref.invalidate(topProductsProvider),
          empty: 'No sales yet.',
          row: (i, p) => _ProductLine(
            product: p,
            leading: '${i + 1}',
            trailing: '${number.format(p.salesCount)} sold',
          ),
        ),
      ],
    );
  }
}

class _LowStockCard extends ConsumerWidget {
  const _LowStockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Low stock (≤ ${DashboardRepository.lowStockThreshold})',
        trailing: Text('Unlimited-stock products are not listed',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context))),
        children: [
          _productList(
            context,
            ref.watch(lowStockProvider),
            onRetry: () => ref.invalidate(lowStockProvider),
            empty: 'No products are low on stock.',
            row: (_, p) => _ProductLine(
              product: p,
              trailing: (p.stock ?? 0) <= 0 ? 'Out of stock' : '${p.stock} left',
              trailingIsWarning: (p.stock ?? 0) <= 0,
              note: p.isActive ? null : 'inactive',
            ),
          ),
        ],
      );
}

class _ProductLine extends StatelessWidget {
  const _ProductLine(
      {required this.product, required this.trailing, this.leading, this.trailingIsWarning = false, this.note});
  final ProductModel product;
  final String trailing;
  final String? leading;
  final bool trailingIsWarning;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 12);
    return InkWell(
      onTap: () => context.go(AdminRoutes.product(p.id)),
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(children: [
          if (leading != null)
            SizedBox(width: 28, child: Text(leading!, style: muted.copyWith(fontWeight: FontWeight.w700))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title.en.isEmpty ? p.id : p.title.en,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                [
                  p.id,
                  if (p.availability == ProductAvailability.outOfStock) 'marked out of stock',
                  if (note != null) note!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ]),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(CurrencyFormatter.format(p.price),
              style: TextStyle(color: AppColors.goldText(context), fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 92,
            child: Text(
              trailing,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: trailingIsWarning ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CatalogueCounts extends ConsumerWidget {
  const _CatalogueCounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final number = NumberFormat.decimalPattern('en_US');
    final tiles = [
      ('Products', FirestorePaths.products, Icons.inventory_2_outlined, AdminRoutes.products),
      ('Categories', FirestorePaths.categories, Icons.category_outlined, AdminRoutes.categories),
      ('Banners', FirestorePaths.banners, Icons.view_carousel_outlined, AdminRoutes.banners),
      ('Customers', FirestorePaths.users, Icons.people_outline, AdminRoutes.users),
    ];
    return Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
      for (final (label, collection, icon, route) in tiles)
        KpiTile(
          label: label,
          icon: icon,
          value: ref.watch(_countProvider(collection)).whenData(number.format),
          onRetry: () => ref.invalidate(_countProvider(collection)),
          onTap: () => context.go(route),
        ),
    ]);
  }
}

/// A partner's own KPIs: orders today, waiting for confirmation, in
/// progress, revenue of their lines (last 30 days) and their product count.
class SellerDashboardBody extends ConsumerWidget {
  const SellerDashboardBody({super.key, required this.storeId});
  final String storeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(sellerRecentOrdersProvider(storeId));
    final products = ref.watch(sellerProductCountProvider(storeId));
    final kpis = orders.whenData((list) => SellerKpis.of(list, storeId, DateTime.now()));
    String value(int Function(SellerKpis k) pick, {bool money = false}) => kpis.when(
          data: (k) => money ? CurrencyFormatter.format(pick(k)) : '${pick(k)}',
          loading: () => '…',
          error: (_, __) => '—',
        );
    final tiles = [
      ('Orders today', value((k) => k.ordersToday), Icons.today_outlined, AdminRoutes.orders),
      ('To confirm', value((k) => k.pending), Icons.pending_actions_outlined, AdminRoutes.orders),
      ('In progress', value((k) => k.inProgress), Icons.local_shipping_outlined, AdminRoutes.orders),
      (
        'Revenue · ${SellerKpis.windowDays} days',
        value((k) => k.revenue, money: true),
        Icons.payments_outlined,
        AdminRoutes.orders
      ),
      (
        'Products',
        products.when(data: (n) => '$n', loading: () => '…', error: (_, __) => '—'),
        Icons.inventory_2_outlined,
        AdminRoutes.products,
      ),
    ];
    return ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: [
      Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
        for (final (label, v, icon, route) in tiles)
          SizedBox(
            width: 220,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => context.go(route),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(children: [
                    Icon(icon, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(v,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: AppSpacing.md),
      Text(
        'Counts only your own items. Revenue excludes cancelled, returned and refunded items; '
        'orders older than ${SellerKpis.windowDays} days are not included.',
        style: TextStyle(color: AppColors.textMuted(context)),
      ),
      if (orders.hasError)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text('Could not load your orders: ${orders.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
    ]);
  }
}
