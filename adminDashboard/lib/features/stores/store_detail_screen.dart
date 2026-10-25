import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/store_model.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import 'data/callable_errors.dart';
import 'data/stores_admin_repository.dart';
import 'stores_screen.dart';
import 'widgets/detail_widgets.dart';
import 'widgets/store_profile_form.dart';
import 'widgets/store_sales_card.dart';

/// `/stores/:id` (SRS §9 Stores / Partners): application review (approve
/// with commission / reject with reason → `reviewPartner`), suspend /
/// reactivate (`setStoreStatus`), profile editor and sales.
class StoreDetailScreen extends ConsumerWidget {
  const StoreDetailScreen({super.key, required this.storeId});
  final String storeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(adminStoreProvider(storeId));
    return AdminScaffold(
      title: 'Store',
      selectedRoute: AdminRoutes.stores,
      body: record.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => CenteredNote(icon: Icons.error_outline, text: 'Could not load the store: $e'),
        data: (r) => r == null
            ? CenteredNote(
                icon: Icons.search_off,
                text: 'Store “$storeId” doesn’t exist (a rejected application removes its store).',
                action: OutlinedButton(onPressed: () => context.go(AdminRoutes.stores), child: const Text('All stores')),
              )
            : _Body(record: r),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.record});
  final StoreRecord record;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  StoreModel get _store => widget.record.store;

  Future<void> _run(String functionName, Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, e is ArgumentError ? '${e.message}' : callableErrorMessage(functionName, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final pct = await showDialog<double>(
      context: context,
      builder: (_) => ApproveStoreDialog(store: _store),
    );
    if (pct == null || !mounted) return;
    await _run('reviewPartner', () => ref.read(storesAdminRepositoryProvider).approve(_store.id, pct),
        'Approved — ${_store.name.en} can now sign in to the dashboard.');
  }

  Future<void> _reject() async {
    final reason = await showReasonDialog(
      context,
      title: 'Reject this application?',
      message: 'The applicant is notified with this reason. The store is removed and the application archived.',
      label: 'Reason (sent to the applicant) *',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    var ok = false;
    await _run('reviewPartner', () async {
      await ref.read(storesAdminRepositoryProvider).reject(_store.id, reason);
      ok = true;
    }, 'Application rejected.');
    if (ok && mounted) context.go(AdminRoutes.stores);
  }

  Future<void> _setStatus(StoreStatus next) async {
    final suspend = next == StoreStatus.suspended;
    final reason = await showReasonDialog(
      context,
      title: suspend ? 'Suspend “${_store.name.en}”?' : 'Reactivate “${_store.name.en}”?',
      message: suspend
          ? 'Its products stay but are hidden in the app, and the partner sees a “suspended” page instead of the dashboard.'
          : 'Its products show in the app again and the partner can use the dashboard.',
      confirmLabel: suspend ? 'Suspend' : 'Reactivate',
      destructive: suspend,
    );
    if (reason == null || !mounted) return;
    await _run('setStoreStatus', () => ref.read(storesAdminRepositoryProvider).setStatus(_store.id, next, reason),
        suspend ? 'Store suspended.' : 'Store reactivated.');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final role = session?.role ?? AdminRole.content;
    final canReview = StoresAccess.canReview(role);
    final s = _store;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => context.go(AdminRoutes.stores),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('All stores'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _Header(record: widget.record),
              const SizedBox(height: AppSpacing.md),
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                if (canReview && s.status == StoreStatus.pendingApproval) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : _approve,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: _busy ? null : _reject,
                    icon: const Icon(Icons.block),
                    label: const Text('Reject'),
                  ),
                ],
                if (canReview && s.status == StoreStatus.active)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: _busy ? null : () => _setStatus(StoreStatus.suspended),
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Suspend'),
                  ),
                if (canReview && s.status == StoreStatus.suspended)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _setStatus(StoreStatus.active),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Reactivate'),
                  ),
                if (_busy) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              if (!canReview)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text('Your role can view this store but not approve or suspend it.',
                      style: TextStyle(color: AppColors.textMuted(context))),
                ),
              if (s.status == StoreStatus.pendingApproval) ...[
                const SizedBox(height: AppSpacing.md),
                _ApplicationCard(storeId: s.id),
              ],
              const SizedBox(height: AppSpacing.md),
              StoreProfileForm(
                key: ValueKey('profile:${s.id}'),
                store: s,
                commissionEditable: StoresAccess.canEditProfile(role),
                readOnly: !StoresAccess.canEditProfile(role),
              ),
              const SizedBox(height: AppSpacing.md),
              StoreSalesCard(store: s),
              const SizedBox(height: AppSpacing.xl),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.record});
  final StoreRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = record.store;
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final city = cities.where((c) => c.id == s.city).firstOrNull?.name.en ?? s.city;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ImageThumb(url: s.logoUrl, size: 72),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(s.name.en.isEmpty ? s.id : s.name.en,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                StoreStatusChip(s.status),
              ]),
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  s.id,
                  if (city != null) city,
                  'Commission ${commissionLabel(s.commissionPercent)}',
                  '${s.productCount} products',
                  '${s.ordersCount} orders',
                  if (s.ratingCount > 0) '★ ${s.ratingAvg.toStringAsFixed(1)} (${s.ratingCount})',
                ].join(' · '),
                style: TextStyle(color: AppColors.textMuted(context)),
              ),
              if (s.ownerUid != null)
                Row(children: [
                  Text('Owner account: ', style: TextStyle(color: AppColors.textMuted(context))),
                  Flexible(
                    child: TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.goldText(context)),
                      onPressed: () => context.go(AdminRoutes.user(s.ownerUid!)),
                      child: Text(s.ownerUid!, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.storeId});
  final String storeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(storeApplicationProvider(storeId));
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    return SectionCard(title: 'Application', children: [
      application.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load the application: $e'),
        data: (a) {
          if (a == null) {
            return Text('No application details were found for this store.',
                style: TextStyle(color: AppColors.textMuted(context)));
          }
          final city = cities.where((c) => c.id == a.city).firstOrNull?.name.en ?? a.city;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KeyValueRow('Store name', a.storeName),
            KeyValueRow('Owner', a.ownerName),
            KeyValueRow('Phone', a.phone, copy: a.phone),
            KeyValueRow('City', city),
            KeyValueRow('Sells', a.category),
            KeyValueRow('Instagram', a.instagram == null ? '' : '@${a.instagram}', copy: a.instagram),
            KeyValueRow('Submitted',
                a.submittedAt == null ? '' : DateFormat('yyyy-MM-dd HH:mm', 'en_US').format(a.submittedAt!.toLocal())),
            const SizedBox(height: AppSpacing.sm),
            Text('Sample photos (${a.samplePhotos.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            if (a.samplePhotos.isEmpty)
              Text('None sent.', style: TextStyle(color: AppColors.textMuted(context)))
            else
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                for (final url in a.samplePhotos) ImageThumb(url: url, size: 96),
              ]),
          ]);
        },
      ),
    ]);
  }
}

/// Approve: the commission is required (0–50 %); resolves to it.
class ApproveStoreDialog extends StatefulWidget {
  const ApproveStoreDialog({super.key, required this.store});
  final StoreModel store;

  @override
  State<ApproveStoreDialog> createState() => _ApproveStoreDialogState();
}

class _ApproveStoreDialogState extends State<ApproveStoreDialog> {
  final _form = GlobalKey<FormState>();
  late final _pct = TextEditingController(
    text: () {
      final v = widget.store.commissionPercent > 0 ? widget.store.commissionPercent : defaultCommissionPercent;
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
    }(),
  );

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Approve “${widget.store.name.en}”?'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('The store goes live, the owner gets the seller role for this store and is notified.'),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('approveCommission'),
                controller: _pct,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Commission % *', helperText: 'Golden Gift’s share of each sale, 0–50'),
                validator: (v) => validateCommission(double.tryParse(v?.trim() ?? '')),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) Navigator.pop(context, double.parse(_pct.text.trim()));
            },
            child: const Text('Approve'),
          ),
        ],
      );
}
