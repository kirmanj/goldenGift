import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/providers/theme_provider.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import '../../features/auth/login_screen.dart';
import '../../features/seller/seller_store_gate.dart';
import '../router/admin_routes.dart';
import '../session/admin_session.dart';

/// One entry of the left navigation (SRS §9 modules).
class AdminNavItem {
  const AdminNavItem(this.route, this.label, this.icon,
      {this.sellerVisible = false, this.sellerOnly = false, this.staffRoles});
  final String route;
  final String label;
  final IconData icon;

  /// Staff roles that see the entry; null = every staff role. The page itself
  /// still checks the role (RoleLockedNotice) for a typed-in URL.
  final Set<AdminRole>? staffRoles;

  /// Shown to seller accounts (Phase 8 restricted view).
  final bool sellerVisible;

  /// Shown ONLY to seller accounts (their own store profile).
  final bool sellerOnly;
}

const adminNavItems = [
  AdminNavItem(AdminRoutes.dashboard, 'Dashboard', Icons.space_dashboard_outlined, sellerVisible: true),
  AdminNavItem(AdminRoutes.orders, 'Orders', Icons.receipt_long_outlined, sellerVisible: true),
  AdminNavItem(AdminRoutes.products, 'Products', Icons.inventory_2_outlined, sellerVisible: true),
  AdminNavItem(AdminRoutes.storeProfile, 'Store profile', Icons.store_outlined, sellerVisible: true, sellerOnly: true),
  AdminNavItem(AdminRoutes.categories, 'Categories', Icons.category_outlined),
  AdminNavItem(AdminRoutes.stores, 'Stores / Partners', Icons.storefront_outlined),
  AdminNavItem(AdminRoutes.users, 'Users', Icons.people_outline),
  AdminNavItem(AdminRoutes.banners, 'Banners', Icons.view_carousel_outlined),
  AdminNavItem(AdminRoutes.reels, 'Reels', Icons.slow_motion_video_outlined,
      staffRoles: {AdminRole.superAdmin, AdminRole.ops, AdminRole.content}),
  AdminNavItem(AdminRoutes.promoCodes, 'Promo codes', Icons.local_offer_outlined),
  AdminNavItem(AdminRoutes.giftCards, 'Gift cards', Icons.card_giftcard_outlined),
  AdminNavItem(AdminRoutes.specialRequests, 'Special requests', Icons.lightbulb_outline),
  AdminNavItem(AdminRoutes.referrals, 'Referrals', Icons.group_add_outlined),
  AdminNavItem(AdminRoutes.reviews, 'Reviews', Icons.reviews_outlined),
  AdminNavItem(AdminRoutes.secretSanta, 'Secret Santa', Icons.redeem_outlined),
  AdminNavItem(AdminRoutes.notifications, 'Notifications', Icons.campaign_outlined),
  AdminNavItem(AdminRoutes.settings, 'Settings', Icons.settings_outlined),
  AdminNavItem(AdminRoutes.auditLog, 'Audit log', Icons.history_outlined),
];

/// Page frame for every dashboard screen: gates on the admin session, then
/// shows the left navigation (a drawer on narrow windows) and a top bar.
class AdminScaffold extends ConsumerWidget {
  const AdminScaffold({
    super.key,
    required this.title,
    required this.selectedRoute,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String title;
  final String selectedRoute;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  static const wideBreakpoint = 1000.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(adminAuthProvider);
    return auth.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Could not check your access: $e'))),
      data: (state) => switch (state) {
        AdminSignedOut() => const LoginScreen(),
        AdminNotAuthorized(:final email) => _NotAuthorized(email: email),
        AdminSession session => session.isSeller ? _sellerFrame(context, ref, session) : _frame(context, ref, session),
      },
    );
  }

  /// Partners (SRS §9 "Seller view"): only while their store is `active`, and
  /// only the seller modules; otherwise a pending / suspended page.
  Widget _sellerFrame(BuildContext context, WidgetRef ref, AdminSession session) {
    final store = ref.watch(sellerStoreProvider);
    return store.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => SellerStoreGate(session: session),
      data: (s) {
        if (s == null || !s.isActive) return SellerStoreGate(session: session, store: s);
        final allowed = adminNavItems.any((i) => i.sellerVisible && i.route == selectedRoute);
        return allowed ? _frame(context, ref, session) : _frame(context, ref, session, restricted: true);
      },
    );
  }

  Widget _frame(BuildContext context, WidgetRef ref, AdminSession session, {bool restricted = false}) {
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final items = session.role == AdminRole.seller
        ? adminNavItems.where((i) => i.sellerVisible).toList()
        : adminNavItems
            .where((i) => !i.sellerOnly && (i.staffRoles == null || i.staffRoles!.contains(session.role)))
            .toList();
    final body = restricted ? const SellerModuleUnavailable() : this.body;
    final floatingActionButton = restricted ? null : this.floatingActionButton;
    final actions = restricted ? const <Widget>[] : this.actions;
    final nav = _NavList(items: items, selected: selectedRoute);
    final themeMode = ref.watch(themeModeProvider);
    final appBar = AppBar(
      title: Text(title),
      centerTitle: false,
      actions: [
        ...actions,
        IconButton(
          tooltip: themeMode == ThemeMode.dark ? 'Light mode' : 'Dark mode',
          icon: Icon(themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: () => ref
              .read(themeModeProvider.notifier)
              .setMode(themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
        ),
        PopupMenuButton<String>(
          tooltip: session.email,
          icon: const Icon(Icons.account_circle_outlined),
          itemBuilder: (_) => [
            PopupMenuItem(enabled: false, child: Text('${session.name}\n${session.email}')),
            const PopupMenuItem(value: 'logout', child: Text('Log out')),
          ],
          onSelected: (v) {
            if (v == 'logout') ref.read(firebaseAuthProvider).signOut();
          },
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
    if (!wide) {
      return Scaffold(
        appBar: appBar,
        drawer: Drawer(child: SafeArea(child: nav)),
        body: body,
        floatingActionButton: floatingActionButton,
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 248, child: Material(color: Theme.of(context).colorScheme.surface, child: SafeArea(child: nav))),
          VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          Expanded(child: Scaffold(appBar: appBar, body: body, floatingActionButton: floatingActionButton)),
        ],
      ),
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.items, required this.selected});
  final List<AdminNavItem> items;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.md),
          child: Row(children: [
            Icon(Icons.card_giftcard, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text('Golden Gift Admin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        for (final item in items)
          ListTile(
            dense: true,
            selected: item.route == selected,
            selectedTileColor: scheme.primary.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            leading: Icon(item.icon),
            title: Text(item.label),
            onTap: () {
              if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.of(context).pop();
              context.go(item.route);
            },
          ),
      ],
    );
  }
}

class _NotAuthorized extends ConsumerWidget {
  const _NotAuthorized({this.email});
  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline, size: 40),
                  const SizedBox(height: AppSpacing.md),
                  Text('${email ?? 'This account'} is not an admin.', textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Ask a super admin to grant access, then sign in again.', textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: () => ref.read(firebaseAuthProvider).signOut(),
                    child: const Text('Sign out'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
