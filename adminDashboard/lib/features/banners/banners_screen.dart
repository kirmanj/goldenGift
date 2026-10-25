import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/banner_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../categories/categories_data.dart';
import 'banner_editor_dialog.dart';
import 'banner_widgets.dart';
import 'banners_data.dart';

/// SRS §9 Banners: CRUD per Home placement, ordering, scheduling, action targets.
class BannersScreen extends ConsumerStatefulWidget {
  const BannersScreen({super.key});

  @override
  ConsumerState<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends ConsumerState<BannersScreen> {
  /// Order shown for a placement while its reorder is saving.
  final Map<BannerPlacement, List<BannerModel>> _pending = {};

  Future<void> _edit(List<BannerModel> all, {BannerModel? banner, BannerPlacement? placement}) async {
    final saved = await showBannerEditor(context, banner: banner, placement: placement, all: all);
    if (saved && mounted) showMessage(context, banner == null ? 'Banner created' : 'Banner saved');
  }

  Future<void> _delete(BannerModel b) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this banner?',
      message: 'It disappears from ${placementLabel(b.placement)} immediately. Uploaded artwork stays in Storage.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(bannerAdminRepositoryProvider).delete(b);
      if (mounted) showMessage(context, 'Banner deleted');
    } catch (e) {
      if (mounted) showMessage(context, 'Could not delete: $e');
    }
  }

  Future<void> _move(BannerPlacement placement, List<BannerModel> group, int index, int delta) async {
    final target = index + delta;
    if (target < 0 || target >= group.length) return;
    final moved = moveItem(group, index, delta > 0 ? target + 1 : target);
    setState(() => _pending[placement] = moved);
    try {
      await ref.read(bannerAdminRepositoryProvider).reorder(placement, moved);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save the new order: $e');
    } finally {
      if (mounted) setState(() => _pending.remove(placement));
    }
  }

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(adminBannersProvider);
    final loaded = banners.valueOrNull;
    return AdminScaffold(
      title: 'Banners',
      selectedRoute: AdminRoutes.banners,
      floatingActionButton: loaded == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(loaded),
              icon: const Icon(Icons.add),
              label: const Text('New banner'),
            ),
      body: banners.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load banners: $e')),
        data: (all) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 88),
              children: [
                for (final p in BannerPlacement.values) ...[
                  _PlacementSection(
                    placement: p,
                    banners: _pending[p] ?? all.where((b) => b.placement == p).toList(),
                    onAdd: () => _edit(all, placement: p),
                    onEdit: (b) => _edit(all, banner: b),
                    onDelete: _delete,
                    onMove: (group, i, delta) => _move(p, group, i, delta),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlacementSection extends StatelessWidget {
  const _PlacementSection({
    required this.placement,
    required this.banners,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onMove,
  });

  final BannerPlacement placement;
  final List<BannerModel> banners;
  final VoidCallback onAdd;
  final ValueChanged<BannerModel> onEdit;
  final ValueChanged<BannerModel> onDelete;
  final void Function(List<BannerModel> group, int index, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final live = banners.where((b) => bannerStatus(b, now) == BannerStatus.live).length;
    final muted = AppColors.textMuted(context);
    return SectionCard(
      title: placementLabel(placement),
      trailing: TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add')),
      children: [
        Text('${placementHint(placement)}  ·  $live live of ${banners.length}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: AppSpacing.sm),
        if (banners.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('No banners — the app hides this section.', style: TextStyle(color: muted)),
          ),
        for (var i = 0; i < banners.length; i++) ...[
          if (i > 0) const Divider(height: AppSpacing.md),
          _BannerRow(
            key: ValueKey(banners[i].id),
            banner: banners[i],
            canMoveUp: i > 0,
            canMoveDown: i < banners.length - 1,
            onUp: () => onMove(banners, i, -1),
            onDown: () => onMove(banners, i, 1),
            onEdit: () => onEdit(banners[i]),
            onDelete: () => onDelete(banners[i]),
          ),
        ],
      ],
    );
  }
}

class _BannerRow extends ConsumerWidget {
  const _BannerRow({
    super.key,
    required this.banner,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onUp,
    required this.onDown,
    required this.onEdit,
    required this.onDelete,
  });

  final BannerModel banner;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _target(WidgetRef ref) {
    final b = banner;
    switch (b.actionType) {
      case BannerActionType.category:
        final categories = ref.watch(adminCategoriesProvider).valueOrNull ?? const [];
        final match = categories.where((c) => c.id == b.actionValue).firstOrNull;
        return 'Opens category · ${match?.title.en ?? '${b.actionValue} (missing)'}';
      case BannerActionType.product:
        final title = ref.watch(productTitleProvider(b.actionValue));
        return 'Opens product · ${title.when(
          loading: () => b.actionValue,
          error: (_, __) => b.actionValue,
          data: (t) => t ?? '${b.actionValue} (missing)',
        )}';
      case BannerActionType.url:
        return 'Opens link · ${b.actionValue}';
      case BannerActionType.route:
        return 'Opens screen · ${routeLabel(b.actionValue)}';
    }
  }

  String _schedule() {
    final b = banner;
    if (b.startAt == null && b.endAt == null) return 'No schedule — always on while active';
    final from = b.startAt == null ? 'now' : bannerDateFormat.format(b.startAt!);
    final to = b.endAt == null ? 'no end' : bannerDateFormat.format(b.endAt!);
    return '$from → $to';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = AppColors.textMuted(context);
    final languages = ['EN', if (banner.imageUrlAr != null) 'AR', if (banner.imageUrlKu != null) 'KU'].join(' · ');
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      BannerThumb(url: banner.imageUrl),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            BannerStatusBadge(status: bannerStatus(banner, DateTime.now())),
            Text('Artwork: $languages', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text(_target(ref),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Text(_schedule(), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ]),
      ),
      IconButton(tooltip: 'Move up', onPressed: canMoveUp ? onUp : null, icon: const Icon(Icons.arrow_upward)),
      IconButton(tooltip: 'Move down', onPressed: canMoveDown ? onDown : null, icon: const Icon(Icons.arrow_downward)),
      IconButton(tooltip: 'Edit', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
      IconButton(tooltip: 'Delete', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
    ]);
  }
}
