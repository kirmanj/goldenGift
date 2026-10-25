import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/order_model.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/orders_repository.dart';
import '../widgets/order_card.dart';
import '../widgets/order_section.dart';

/// My Orders (SRS §5.12): Active / Completed / Cancelled tabs.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final appBar = GGAppBar(
      title: l10n.orders,
      showBack: true,
      onBack: () => popOrGo(context, AppRoutes.mainTab(2)),
    );

    if (!signedIn) {
      return Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: appBar,
        body: const GuestSignInCard(icon: Icons.receipt_long_rounded),
      );
    }

    final tabs = [
      (OrderTab.active, l10n.activeOrders),
      (OrderTab.completed, l10n.completedOrders),
      (OrderTab.cancelled, l10n.cancelledOrders),
    ];
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: appBar,
        body: Column(
          children: [
            TabBar(
              key: const ValueKey('orders-tabs'),
              indicatorColor: AppColors.gold(context),
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: AppColors.goldText(context),
              unselectedLabelColor: AppColors.textMuted(context),
              dividerColor: AppColors.line(context),
              labelStyle: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, fontFamily: font),
              unselectedLabelStyle: AppTextStyles.label.copyWith(fontFamily: font),
              tabs: [for (final (_, label) in tabs) Tab(height: 48, text: label)],
            ),
            Expanded(
              child: TabBarView(
                children: [for (final (tab, _) in tabs) _OrdersTab(tab: tab)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.tab});
  final OrderTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    return ref.watch(myOrdersProvider).when(
          loading: () => const SingleChildScrollView(
            physics: NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.md),
            child: SkeletonLoader.list(count: 4),
          ),
          error: (_, __) => CenteredScroll(child: ErrorState(onRetry: () => ref.invalidate(myOrdersProvider))),
          data: (all) {
            final orders = all.where((o) => o.status.tab == tab).toList();
            if (orders.isEmpty) {
              return CenteredScroll(
                key: ValueKey('orders-empty-${tab.name}'),
                child: EmptyState(
                  title: l10n.noOrdersTitle,
                  subtitle: l10n.noOrdersBody,
                  icon: Icons.receipt_long_outlined,
                  ctaLabel: tab == OrderTab.active ? l10n.continueShopping : null,
                  onCta: tab == OrderTab.active ? () => context.go(AppRoutes.mainTab(0)) : null,
                ),
              );
            }
            return ListView.separated(
              key: ValueKey('orders-list-${tab.name}'),
              padding:
                  EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.md, AppSpacing.screenHorizontal, bottom),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              itemBuilder: (context, i) => OrderCard(
                key: ValueKey('order-${orders[i].id}'),
                order: orders[i],
                onTap: () => unawaited(context.push(AppRoutes.order(orders[i].id))),
              ),
            );
          },
        );
  }
}
