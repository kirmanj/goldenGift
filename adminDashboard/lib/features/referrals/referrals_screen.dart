import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/referral_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../users/data/users_admin_repository.dart' show adminUserLookupProvider;
import '../users/user_detail_screen.dart' show UserLink;
import '../users/widgets/user_widgets.dart';
import 'data/referrals_admin_data.dart';
import 'referral_ui.dart';

/// SRS §9 Referrals: list (newest first, by status), fraud flags, the
/// current `app_settings/referral` values with a link to edit them.
class ReferralsScreen extends ConsumerStatefulWidget {
  const ReferralsScreen({super.key});

  @override
  ConsumerState<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends ConsumerState<ReferralsScreen> {
  ReferralStatus? _status;
  int _limit = ReferralsAdminRepository.pageSize;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    return AdminScaffold(
      title: 'Referrals',
      selectedRoute: AdminRoutes.referrals,
      actions: [
        IconButton(
          tooltip: 'Refresh totals',
          onPressed: () => ref.invalidate(referralSummaryProvider),
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: session == null
          ? const SizedBox.shrink()
          : !ReferralAccess.canView(session.role)
              ? RoleLockedNotice(module: 'Referrals', role: session.role, who: 'super admins, ops and finance')
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final referrals = ref.watch(adminReferralsProvider((_status, _limit)));
    final muted = AppColors.textMuted(context);
    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: AppSpacing.md),
      const _SettingsCard(),
      const SizedBox(height: AppSpacing.md),
      const _SummaryTiles(),
      const SizedBox(height: AppSpacing.md),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
        ChoiceChip(
          label: const Text('All'),
          selected: _status == null,
          onSelected: (_) => setState(() {
            _status = null;
            _limit = ReferralsAdminRepository.pageSize;
          }),
        ),
        for (final s in ReferralStatus.values)
          ChoiceChip(
            label: Text(referralStatusLabel(s)),
            selected: _status == s,
            onSelected: (_) => setState(() {
              _status = s;
              _limit = ReferralsAdminRepository.pageSize;
            }),
          ),
      ]),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Flags come from the referral functions (same device, monthly cap, self-referral, blocked); '
        '"detected" flags are worked out here from both users\' documents.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
      ),
      const SizedBox(height: AppSpacing.sm),
    ]);

    return referrals.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text('Could not load referrals: $e\n\nFiltering by status needs the referrals (status ASC, createdAt DESC) index.'),
        ),
      ),
      data: (list) => list.isEmpty
          ? ListView(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md), children: [
              header,
              const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: Text('No referrals match.'))),
            ])
          : ScrollableTable(
              header: header,
              footer: LoadMoreButton(
                visible: list.length >= _limit,
                onPressed: () => setState(() => _limit += ReferralsAdminRepository.pageSize),
              ),
              table: DataTable(
                columnSpacing: AppSpacing.lg,
                dataRowMaxHeight: 64,
                columns: const [
                  DataColumn(label: Text('Referrer')),
                  DataColumn(label: Text('Friend')),
                  DataColumn(label: Text('Code')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Join bonus')),
                  DataColumn(label: Text('Order bonus')),
                  DataColumn(label: Text('First order')),
                  DataColumn(label: Text('Created')),
                  DataColumn(label: Text('Completed')),
                  DataColumn(label: Text('Flags')),
                ],
                rows: [for (final r in list) _row(r)],
              ),
            ),
    );
  }

  DataRow _row(ReferralModel r) => DataRow(key: ValueKey(r.id), cells: [
        DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: UserLink(uid: r.referrerUid))),
        DataCell(ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: UserLink(uid: r.referredUid, fallbackName: r.referredName),
        )),
        DataCell(SelectableText(r.code)),
        DataCell(ReferralStatusChip(r.status)),
        DataCell(PaidMark(r.joinBonusPaid, label: 'Join bonus')),
        DataCell(PaidMark(r.orderBonusPaid, label: 'Order bonus')),
        DataCell(SelectableText(r.firstOrderId ?? '—')),
        DataCell(Text(formatAdminDate(r.createdAt))),
        DataCell(Text(formatAdminDate(r.completedAt))),
        DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: _FlagsCell(referral: r))),
      ]);
}

/// Stored + detected flags; loads both users once for the visible rows only.
class _FlagsCell extends ConsumerWidget {
  const _FlagsCell({required this.referral});
  final ReferralModel referral;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referrer = ref.watch(adminUserLookupProvider(referral.referrerUid)).valueOrNull;
    final referred = ref.watch(adminUserLookupProvider(referral.referredUid)).valueOrNull;
    return ReferralFlagChips(flags: referralFlags(referral, referrer: referrer, referred: referred));
  }
}

class _SettingsCard extends ConsumerWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(referralSettingsProvider);
    return SectionCard(
      title: 'Referral settings',
      trailing: TextButton.icon(
        onPressed: () => context.go(AdminRoutes.settings),
        icon: const Icon(Icons.settings_outlined),
        label: const Text('Edit in Settings'),
      ),
      children: [
        settings.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load app_settings/referral: $e'),
          data: (s) => Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.sm, children: [
            _Setting('Join bonus (friend)', CurrencyFormatter.format(s.joinBonus)),
            _Setting('Order bonus (referrer)', CurrencyFormatter.format(s.orderBonus)),
            _Setting('Max referrals / month', s.maxReferralsPerMonth == 0 ? 'No limit' : '${s.maxReferralsPerMonth}'),
            _Setting('Credits expire', s.creditsExpiryDays == 0 ? 'Never' : 'After ${s.creditsExpiryDays} days'),
          ]),
        ),
      ],
    );
  }
}

class _Setting extends StatelessWidget {
  const _Setting(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: AppColors.textMuted(context))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);
}

class _SummaryTiles extends ConsumerWidget {
  const _SummaryTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(referralSummaryProvider);
    final settings = ref.watch(referralSettingsProvider).valueOrNull ?? const ReferralSettings();
    final muted = AppColors.textMuted(context);
    Widget tile(String label, String value, {String? hint, Color? color}) => Container(
          width: 190,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.line(context)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: muted)),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700, color: color ?? AppColors.goldText(context))),
            if (hint != null) Text(hint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
          ]),
        );
    return summary.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Could not count referrals: $e'),
      data: (s) => Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
        tile('Total', '${s.total}'),
        tile('Pending', '${s.pending}', color: AppColors.info),
        tile('Completed', '${s.completed}', color: AppColors.success),
        tile('Cancelled', '${s.cancelled}', color: AppColors.error),
        tile('Credits paid (estimate)', CurrencyFormatter.format(s.creditsPaidEstimate(settings)),
            hint: '${s.joinBonusesPaid} join + ${s.orderBonusesPaid} order bonuses × today\'s amounts'),
      ]),
    );
  }
}
