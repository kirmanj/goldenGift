import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:golden_gift/models/wallet_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../categories/categories_screen.dart' show InfoTag;
import '../orders/order_status_ui.dart' show OrderStatusChip;
import '../referrals/referral_ui.dart';
import 'block_user_dialog.dart';
import 'data/users_admin_repository.dart';
import 'wallet_adjust_dialog.dart';
import 'widgets/user_widgets.dart';

/// `/users/:id` (SRS §9 Users): profile, wallet + transactions, orders,
/// addresses, referrals made; Block / Unblock and Adjust wallet.
class UserDetailScreen extends ConsumerWidget {
  const UserDetailScreen({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    return AdminScaffold(
      title: 'User',
      selectedRoute: AdminRoutes.users,
      body: session == null
          ? const SizedBox.shrink()
          : !UsersAccess.canView(session.role)
              ? RoleLockedNotice(module: 'Users', role: session.role, who: 'super admins, ops and finance')
              : ref.watch(adminUserProvider(uid)).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Could not load the user: $e')),
                    data: (record) => record == null
                        ? Center(child: Text('No user with id $uid.'))
                        : _Body(record: record, session: session),
                  ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.record, required this.session});
  final AdminUserRecord record;
  final AdminSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = record.user;
    final profile = _ProfileCard(record: record);
    final wallet = _WalletCard(uid: u.uid);
    final orders = _OrdersCard(uid: u.uid);
    final addresses = _AddressesCard(uid: u.uid);
    final referrals = _ReferralsCard(uid: u.uid);
    const gap = SizedBox(height: AppSpacing.md, width: AppSpacing.md);

    return LayoutBuilder(builder: (context, c) {
      final header = _Header(user: u, session: session);
      if (c.maxWidth < 1100) {
        return ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
          header, gap, profile, gap, wallet, gap, orders, gap, addresses, gap, referrals,
        ]);
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          gap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [profile, gap, addresses])),
            gap,
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [wallet, gap, orders, gap, referrals])),
          ]),
        ]),
      );
    });
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.user, required this.session});
  final UserModel user;
  final AdminSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = AppColors.textMuted(context);
    final canBlock = UsersAccess.canBlock(session.role);
    final canAdjust = UsersAccess.canAdjustWallet(session.role);
    final walletAsync = ref.watch(adminWalletProvider(user.uid));
    final wallet = walletAsync.valueOrNull;
    final name = userDisplayName(user);

    final notes = <String>[
      if (!canBlock) 'Only super admins and ops can block users.',
      if (!canAdjust) 'Only super admins and finance can adjust wallets.',
      if (user.isDeleted) 'This account was deleted (anonymized) — it is read-only.',
      if (canAdjust && !user.isDeleted && walletAsync.hasValue && wallet == null)
        'No wallet yet — onUserCreate creates it after sign-up.',
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(tooltip: 'All users', onPressed: () => context.go(AdminRoutes.users), icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            UserStateChips(user: user),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpacing.sm),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
        if (canBlock)
          user.isBlocked
              ? OutlinedButton.icon(
                  onPressed: user.isDeleted ? null : () => _toggleBlock(context),
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Unblock'),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: user.isDeleted ? null : () => _toggleBlock(context),
                  icon: const Icon(Icons.block),
                  label: const Text('Block'),
                ),
        if (canAdjust)
          FilledButton.icon(
            onPressed: user.isDeleted || wallet == null ? null : () => _adjust(context, wallet),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Adjust wallet'),
          ),
      ]),
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(n, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ),
    ]);
  }

  Future<void> _toggleBlock(BuildContext context) async {
    final blocked = await showBlockUserDialog(context,
        uid: user.uid, userName: userDisplayName(user), currentlyBlocked: user.isBlocked);
    if (blocked == null || !context.mounted) return;
    showMessage(context, blocked ? 'User blocked and signed out of every device.' : 'User unblocked.');
  }

  Future<void> _adjust(BuildContext context, WalletModel wallet) async {
    final result = await showWalletAdjustDialog(context, uid: user.uid, userName: userDisplayName(user), wallet: wallet);
    if (result == null || !context.mounted) return;
    showMessage(context,
        'Wallet adjusted. Balance ${CurrencyFormatter.format(result.balance)} · credits ${CurrencyFormatter.format(result.credits)}.');
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.record});
  final AdminUserRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = record.user;
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final city = u.city == null ? '—' : (cities.where((c) => c.id == u.city).firstOrNull?.name.en ?? u.city!);
    String yesNo(bool v) => v ? 'Yes' : 'No';
    return SectionCard(title: 'Profile', children: [
      KeyValueRow('User id', u.uid, copy: u.uid),
      KeyValueRow('Name', userDisplayName(u)),
      KeyValueRow('Phone', userPhone(u), ltr: true, copy: u.phone.isEmpty ? null : '${u.countryCode}${u.phone}'),
      KeyValueRow('Email', u.email ?? '—', copy: u.email),
      KeyValueRow('City', city),
      KeyValueRow('Gender', u.gender ?? '—'),
      KeyValueRow('Birthday', u.birthday == null ? '—' : AppDates.display(u.birthday!)),
      KeyValueRow('Language', u.locale),
      KeyValueRow('Role', u.role.name + (u.storeIds.isEmpty ? '' : ' · stores ${u.storeIds.join(', ')}')),
      KeyValueRow('Profile completed', yesNo(u.profileCompleted)),
      KeyValueRow('Notifications', u.notificationsEnabled ? 'On (${u.fcmTokens.length} device token(s))' : 'Off'),
      KeyValueRow('Referral code', u.referralCode ?? '—', copy: u.referralCode),
      KeyValueRow('Code entered', u.referralCodeEntered ?? '—'),
      KeyValueRow('Referred by', u.referredBy ?? '—',
          child: u.referredBy == null ? null : UserLink(uid: u.referredBy!)),
      KeyValueRow('Device id', u.deviceId ?? '—', copy: u.deviceId),
      KeyValueRow('Orders', '${u.totalOrders} · ${CurrencyFormatter.format(u.totalSpent)} spent'),
      KeyValueRow('Created', formatAdminDate(u.createdAt)),
      KeyValueRow('Last seen', formatAdminDate(u.lastSeenAt)),
      KeyValueRow('Blocked', yesNo(u.isBlocked)),
      if (u.isDeleted) KeyValueRow('Deleted', formatAdminDate(record.deletedAt)),
    ]);
  }
}

/// A user's name that opens `/users/:id`.
class UserLink extends ConsumerWidget {
  const UserLink({super.key, required this.uid, this.fallbackName});
  final String uid;
  final String? fallbackName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(adminUserLookupProvider(uid));
    final name = user.valueOrNull == null ? (fallbackName ?? uid) : userDisplayName(user.valueOrNull, fallback: fallbackName);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        onTap: uid.isEmpty ? null : () => context.go(AdminRoutes.user(uid)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.goldText(context), decoration: TextDecoration.underline, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _WalletCard extends ConsumerWidget {
  const _WalletCard({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(adminWalletProvider(uid));
    final txns = ref.watch(adminWalletTxnsProvider(uid));
    final muted = AppColors.textMuted(context);
    Widget tile(String label, int value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: AppColors.soft(context), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: muted)),
              Text(CurrencyFormatter.format(value),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.goldText(context))),
            ]),
          ),
        );
    return SectionCard(title: 'Wallet', children: [
      wallet.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load the wallet: $e'),
        data: (w) => w == null
            ? Text('No wallet yet.', style: TextStyle(color: muted))
            : Row(children: [
                tile('Balance (real money)', w.balance),
                const SizedBox(width: AppSpacing.sm),
                tile('Credits (promotional)', w.credits),
              ]),
      ),
      const SizedBox(height: AppSpacing.md),
      Text('Last ${UsersAdminRepository.txnLimit} transactions', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      txns.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load transactions: $e'),
        data: (list) => list.isEmpty
            ? Text('No transactions yet.', style: TextStyle(color: muted))
            : Column(children: [for (final t in list) _TxnTile(txn: t)]),
      ),
    ]);
  }
}

class _TxnTile extends ConsumerWidget {
  const _TxnTile({required this.txn});
  final WalletTxn txn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = txn;
    final muted = AppColors.textMuted(context);
    final by = t.byUid == null ? null : (ref.watch(adminNameProvider(t.byUid!)).valueOrNull ?? t.byUid);
    final details = [
      formatAdminDate(t.createdAt),
      bucketLabel(t.bucket),
      'balance after ${CurrencyFormatter.format(t.balanceAfter)}',
      'credits after ${CurrencyFormatter.format(t.creditsAfter)}',
      if (by != null) 'by $by',
      if (t.orderId != null) 'order ${t.orderId}',
    ].join(' · ');
    final text = [if (t.title.en.isNotEmpty) t.title.en, if (t.reason != null) '“${t.reason}”'].join(' — ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(walletTxnTypeLabel(t.type) + (text.isEmpty ? '' : ' · $text'),
                style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(details, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
          ]),
        ),
        const SizedBox(width: AppSpacing.sm),
        SignedAmount(t.amount, format: CurrencyFormatter.format),
      ]),
    );
  }
}

class _OrdersCard extends ConsumerWidget {
  const _OrdersCard({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(adminUserOrdersProvider(uid));
    final muted = AppColors.textMuted(context);
    return SectionCard(title: 'Orders', children: [
      orders.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load orders: $e'),
        data: (list) => list.isEmpty
            ? Text('No orders yet.', style: TextStyle(color: muted))
            : Column(children: [
                for (final o in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SelectableText(o.orderNumber.isEmpty ? o.id : o.orderNumber,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(formatAdminDate(o.createdAt), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
                        ]),
                      ),
                      OrderStatusChip(o.status),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 120,
                        child: Text(CurrencyFormatter.format(o.total),
                            textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                if (list.length >= UsersAdminRepository.orderLimit)
                  Text('Showing the latest ${UsersAdminRepository.orderLimit} orders.', style: TextStyle(color: muted)),
              ]),
      ),
    ]);
  }
}

class _AddressesCard extends ConsumerWidget {
  const _AddressesCard({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(adminUserAddressesProvider(uid));
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final muted = AppColors.textMuted(context);
    return SectionCard(title: 'Saved addresses', children: [
      addresses.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load addresses: $e'),
        data: (list) => list.isEmpty
            ? Text('No saved addresses.', style: TextStyle(color: muted))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final a in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(a.label.isEmpty ? 'Address' : a.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (a.isDefault) const InfoTag('Default', gold: true),
                      ]),
                      Wrap(children: [
                        Text('${a.name} · ', style: TextStyle(color: muted)),
                        LtrText(a.phone, style: TextStyle(color: muted)),
                      ]),
                      Text('${cities.where((c) => c.id == a.city).firstOrNull?.name.en ?? a.city} — ${a.oneLine}'),
                      if (a.notes.isNotEmpty) Text(a.notes, style: TextStyle(color: muted)),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

class _ReferralsCard extends ConsumerWidget {
  const _ReferralsCard({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referrals = ref.watch(adminUserReferralsProvider(uid));
    final muted = AppColors.textMuted(context);
    return SectionCard(title: 'Referrals made', children: [
      referrals.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load referrals: $e'),
        data: (list) => list.isEmpty
            ? Text('This user has not referred anyone.', style: TextStyle(color: muted))
            : Column(children: [
                for (final r in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          UserLink(uid: r.referredUid, fallbackName: r.referredName),
                          Text(
                            [
                              formatAdminDate(r.createdAt),
                              'join bonus ${r.joinBonusPaid ? 'paid' : 'unpaid'}',
                              'order bonus ${r.orderBonusPaid ? 'paid' : 'unpaid'}',
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
                          ),
                          if (r.flags.isNotEmpty) ReferralFlagChips(flags: [for (final f in r.flags) ReferralFlag(f)]),
                        ]),
                      ),
                      ReferralStatusChip(r.status),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}
