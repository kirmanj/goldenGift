import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/router/admin_routes.dart';
import '../../core/widgets/admin_scaffold.dart';
import 'data/stores_admin_repository.dart';
import 'widgets/detail_widgets.dart';

Color storeStatusColor(StoreStatus s) => switch (s) {
      StoreStatus.pendingApproval => AppColors.warning,
      StoreStatus.active => AppColors.success,
      StoreStatus.suspended => AppColors.error,
    };

class StoreStatusChip extends StatelessWidget {
  const StoreStatusChip(this.status, {super.key});
  final StoreStatus status;

  @override
  Widget build(BuildContext context) => StatusPill(label: storeStatusLabel(status), color: storeStatusColor(status));
}

/// SRS §9 Stores / Partners: applications to review, active and suspended
/// partner stores; a row opens `/stores/:id`.
class StoresScreen extends ConsumerWidget {
  const StoresScreen({super.key});

  static const tabs = [StoreStatus.pendingApproval, StoreStatus.active, StoreStatus.suspended];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(storesByStatusProvider(StoreStatus.pendingApproval)).valueOrNull?.length;
    return AdminScaffold(
      title: 'Stores / Partners',
      selectedRoute: AdminRoutes.stores,
      body: DefaultTabController(
        length: tabs.length,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: pending == null || pending == 0 ? 'Pending applications' : 'Pending applications ($pending)'),
              const Tab(text: 'Active'),
              const Tab(text: 'Suspended'),
            ],
          ),
          const Divider(height: 1),
          Expanded(child: TabBarView(children: [for (final s in tabs) _StoreList(status: s)])),
        ]),
      ),
    );
  }
}

class _StoreList extends ConsumerWidget {
  const _StoreList({required this.status});
  final StoreStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = ref.watch(storesByStatusProvider(status));
    return stores.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => CenteredNote(icon: Icons.error_outline, text: 'Could not load stores: $e'),
      data: (list) => list.isEmpty
          ? CenteredNote(
              icon: Icons.storefront_outlined,
              text: switch (status) {
                StoreStatus.pendingApproval => 'No applications waiting for review.',
                StoreStatus.active => 'No active stores yet.',
                StoreStatus.suspended => 'No suspended stores.',
              },
            )
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 900;
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                itemCount: list.length + (wide ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  if (wide && i == 0) return const _HeaderRow();
                  final r = list[wide ? i - 1 : i];
                  return StoreRow(
                      key: ValueKey(r.store.id), record: r, wide: wide, onTap: () => context.go(AdminRoutes.store(r.store.id)));
                },
              );
            }),
    );
  }
}

const _logo = 40.0;
const _cityW = 130.0;
const _numW = 90.0;
const _statusW = 140.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted(context));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(children: [
        const SizedBox(width: _logo + AppSpacing.md),
        Expanded(flex: 3, child: Text('Store', style: style)),
        SizedBox(width: _cityW, child: Text('City', style: style)),
        Expanded(flex: 2, child: Text('Owner', style: style)),
        SizedBox(width: _numW, child: Text('Commission', style: style, textAlign: TextAlign.end)),
        SizedBox(width: _numW, child: Text('Products', style: style, textAlign: TextAlign.end)),
        SizedBox(width: _numW, child: Text('Orders', style: style, textAlign: TextAlign.end)),
        const SizedBox(width: AppSpacing.md),
        SizedBox(width: _statusW, child: Text('Status', style: style)),
      ]),
    );
  }
}

/// One store of the list: wide = table columns, narrow = list tile.
class StoreRow extends ConsumerWidget {
  const StoreRow({super.key, required this.record, required this.wide, required this.onTap});
  final StoreRecord record;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = record.store;
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final city = cities.where((c) => c.id == s.city).firstOrNull?.name.en ?? s.city ?? '—';
    final application = ref.watch(storeApplicationProvider(s.id)).valueOrNull;
    final owner = (application?.ownerName.isNotEmpty ?? false) ? application!.ownerName : (s.ownerUid ?? '—');
    final muted = TextStyle(color: AppColors.textMuted(context));
    final applied = record.createdAt == null ? null : DateFormat('MMM d, yyyy', 'en_US').format(record.createdAt!.toLocal());
    final name = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.name.en.isEmpty ? s.id : s.name.en,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(
        [s.id, if (s.status == StoreStatus.pendingApproval && applied != null) 'applied $applied'].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: muted.copyWith(fontSize: 12),
      ),
    ]);
    if (!wide) {
      return ListTile(
        onTap: onTap,
        leading: ImageThumb(url: s.logoUrl, size: _logo, openOnTap: false),
        title: name,
        subtitle: Text(
          [city, owner, commissionLabel(s.commissionPercent), '${s.productCount} products', '${s.ordersCount} orders'].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StoreStatusChip(s.status),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(children: [
          ImageThumb(url: s.logoUrl, size: _logo, openOnTap: false),
          const SizedBox(width: AppSpacing.md),
          Expanded(flex: 3, child: name),
          SizedBox(width: _cityW, child: Text(city, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(owner, maxLines: 1, overflow: TextOverflow.ellipsis)),
          SizedBox(width: _numW, child: Text(commissionLabel(s.commissionPercent), textAlign: TextAlign.end)),
          SizedBox(width: _numW, child: Text('${s.productCount}', textAlign: TextAlign.end)),
          SizedBox(width: _numW, child: Text('${s.ordersCount}', textAlign: TextAlign.end)),
          const SizedBox(width: AppSpacing.md),
          SizedBox(width: _statusW, child: Align(alignment: AlignmentDirectional.centerStart, child: StoreStatusChip(s.status))),
        ]),
      ),
    );
  }
}
