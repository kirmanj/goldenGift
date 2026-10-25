import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../stores/data/stores_admin_repository.dart';
import '../stores/stores_screen.dart' show StoreStatusChip;
import '../stores/widgets/detail_widgets.dart';
import '../stores/widgets/store_profile_form.dart';
import '../stores/widgets/store_sales_card.dart';

/// `/store-profile` (SRS §9 "Seller view"): a partner edits their own store's
/// name, description, logo, cover and phone; the commission is read-only.
/// AdminScaffold only lets an `active` store through.
class StoreProfileScreen extends ConsumerWidget {
  const StoreProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    final store = ref.watch(sellerStoreProvider);
    return AdminScaffold(
      title: 'Store profile',
      selectedRoute: AdminRoutes.storeProfile,
      body: session == null || !session.isSeller
          ? const CenteredNote(
              icon: Icons.storefront_outlined,
              text: 'Only partner accounts have a store profile — staff edit stores in Stores / Partners.',
            )
          : store.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => CenteredNote(icon: Icons.error_outline, text: 'Could not load your store: $e'),
              data: (s) => s == null
                  ? const CenteredNote(icon: Icons.search_off, text: 'Your store could not be found.')
                  : ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Wrap(spacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Text(s.name.en,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                              StoreStatusChip(s.status),
                            ]),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              [
                                'Commission ${commissionLabel(s.commissionPercent)}',
                                '${s.productCount} products',
                                '${s.ordersCount} orders',
                                if (s.ratingCount > 0) '★ ${s.ratingAvg.toStringAsFixed(1)} (${s.ratingCount})',
                              ].join(' · '),
                              style: TextStyle(color: AppColors.textMuted(context)),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            StoreProfileForm(key: ValueKey('seller:${s.id}'), store: s, commissionEditable: false),
                            const SizedBox(height: AppSpacing.md),
                            StoreSalesCard(store: s),
                          ]),
                        ),
                      ),
                    ]),
            ),
    );
  }
}
