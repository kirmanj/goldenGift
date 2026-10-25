import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/promo_code_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../categories/categories_screen.dart' show InfoTag;
import '../users/widgets/user_widgets.dart';
import 'data/promo_codes_data.dart';
import 'promo_editor_dialog.dart';
import 'promo_usage_dialog.dart';

/// SRS §9 Promo codes: CRUD with every §6.9 rule, usage report.
class PromoCodesScreen extends ConsumerStatefulWidget {
  const PromoCodesScreen({super.key});

  @override
  ConsumerState<PromoCodesScreen> createState() => _PromoCodesScreenState();
}

class _PromoCodesScreenState extends ConsumerState<PromoCodesScreen> {
  PromoStatus? _status;
  String _query = '';

  Future<void> _edit(PromoCodeModel? promo, List<PromoCodeModel> all) async {
    final saved = await showPromoEditor(context, promo: promo, all: all);
    if (saved && mounted) showMessage(context, promo == null ? 'Promo code created' : 'Promo code saved');
  }

  Future<void> _toggle(PromoCodeModel p) async {
    try {
      await ref.read(promoAdminRepositoryProvider).setActive(p, !p.isActive);
      if (mounted) showMessage(context, p.isActive ? '${p.code} deactivated' : '${p.code} activated');
    } catch (e) {
      if (mounted) showMessage(context, 'Could not update ${p.code}: $e');
    }
  }

  Future<void> _offerDeactivate(PromoCodeModel p, int used) async {
    final ok = await confirmAction(
      context,
      title: '${p.code} has been used',
      message: 'It was used $used time(s), so it cannot be deleted — its orders refer to it. '
          '${p.isActive ? 'Deactivate it instead? Customers will no longer be able to apply it.' : 'It is already inactive.'}',
      confirmLabel: p.isActive ? 'Deactivate' : 'OK',
    );
    if (ok && p.isActive && mounted) await _toggle(p);
  }

  Future<void> _delete(PromoCodeModel p) async {
    if (p.usageCount > 0) return _offerDeactivate(p, p.usageCount);
    final ok = await confirmAction(
      context,
      title: 'Delete ${p.code}?',
      message: 'The code has never been used. Customers who saved it will get "code not found".',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(promoAdminRepositoryProvider).delete(p);
      if (mounted) showMessage(context, '${p.code} deleted');
    } on PromoInUseException catch (e) {
      if (mounted) await _offerDeactivate(p, e.usageCount);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final promos = ref.watch(adminPromoCodesProvider);
    final loaded = promos.valueOrNull;
    final canEdit = session != null && PromoAccess.canEdit(session.role);
    return AdminScaffold(
      title: 'Promo codes',
      selectedRoute: AdminRoutes.promoCodes,
      floatingActionButton: loaded == null || !canEdit
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(null, loaded),
              icon: const Icon(Icons.add),
              label: const Text('New promo code'),
            ),
      body: session == null
          ? const SizedBox.shrink()
          : !PromoAccess.canView(session.role)
              ? RoleLockedNotice(module: 'Promo codes', role: session.role, who: 'super admins, ops, content and finance')
              : promos.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Could not load promo codes: $e')),
                  data: (list) => _body(context, list, canEdit),
                ),
    );
  }

  Widget _body(BuildContext context, List<PromoCodeModel> all, bool canEdit) {
    final now = DateTime.now();
    final q = _query.trim().toLowerCase();
    final visible = all
        .where((p) => _status == null || promoStatus(p, now) == _status)
        .where((p) => q.isEmpty || p.code.toLowerCase().contains(q) || p.title.all.any((t) => t.toLowerCase().contains(q)))
        .toList();
    final muted = AppColors.textMuted(context);

    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 260,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search code or title'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          ChoiceChip(label: const Text('All'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
          for (final s in PromoStatus.values)
            ChoiceChip(label: Text(s.label), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
          Text('${visible.length} of ${all.length}', style: TextStyle(color: muted)),
        ]),
      ),
      if (!canEdit)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text('Read-only: your role can view codes and usage reports but not change them.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
        ),
    ]);

    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          Expanded(
            child: Center(child: Text(all.isEmpty ? 'No promo codes yet${canEdit ? ' — create the first one.' : '.'}' : 'No codes match.')),
          ),
        ]),
      );
    }

    return ScrollableTable(
      header: header,
      footer: const SizedBox(height: 72),
      table: DataTable(
        columnSpacing: AppSpacing.lg,
        dataRowMaxHeight: 64,
        columns: const [
          DataColumn(label: Text('Code')),
          DataColumn(label: Text('Title')),
          DataColumn(label: Text('Discount')),
          DataColumn(label: Text('Uses'), numeric: true),
          DataColumn(label: Text('Per customer'), numeric: true),
          DataColumn(label: Text('Min order'), numeric: true),
          DataColumn(label: Text('Expires')),
          DataColumn(label: Text('Rules')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final p in visible)
            DataRow(key: ValueKey(p.code), cells: [
              DataCell(SelectableText(p.code, style: const TextStyle(fontWeight: FontWeight.w700))),
              DataCell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(p.title.en, maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(Text('${p.type == PromoType.percent ? 'Percent' : 'Fixed'} · ${promoDiscountLabel(p)}')),
              DataCell(Text(promoUsesLabel(p))),
              DataCell(Text(p.perUserLimit == 0 ? 'Unlimited' : '${p.perUserLimit}')),
              DataCell(Text(p.minOrder == null || p.minOrder == 0 ? '—' : CurrencyFormatter.format(p.minOrder!))),
              DataCell(Text(formatAdminDate(p.expiresAt))),
              DataCell(Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
                InfoTag(p.isPublic ? 'Public' : 'Private', gold: p.isPublic),
                InfoTag(p.isActive ? 'Active' : 'Off', color: p.isActive ? AppColors.success : AppColors.warning),
                if (p.firstOrderOnly) const InfoTag('First order'),
                if (p.isRestricted) const InfoTag('Restricted', color: AppColors.info),
              ])),
              DataCell(PromoStatusBadge(status: promoStatus(p, now))),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Usage report',
                  onPressed: () => showPromoUsage(context, p),
                  icon: const Icon(Icons.query_stats_outlined),
                ),
                if (canEdit) ...[
                  IconButton(tooltip: 'Edit', onPressed: () => _edit(p, all), icon: const Icon(Icons.edit_outlined)),
                  IconButton(
                    tooltip: p.isActive ? 'Deactivate' : 'Activate',
                    onPressed: () => _toggle(p),
                    icon: Icon(p.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline),
                  ),
                  IconButton(tooltip: 'Delete', onPressed: () => _delete(p), icon: const Icon(Icons.delete_outline)),
                ],
              ])),
            ]),
        ],
      ),
    );
  }
}

/// Live / Inactive / Used up / Expired pill.
class PromoStatusBadge extends StatelessWidget {
  const PromoStatusBadge({super.key, required this.status});
  final PromoStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PromoStatus.live => AppColors.success,
      PromoStatus.inactive => AppColors.textMuted(context),
      PromoStatus.usedUp => AppColors.warning,
      PromoStatus.expired => AppColors.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(status.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}
