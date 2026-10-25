import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/reel_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../stores/widgets/detail_widgets.dart' show CenteredNote;
import '../users/widgets/user_widgets.dart' show RoleLockedNotice;
import 'data/reels_admin_repository.dart';
import 'reel_editor_dialog.dart';
import 'reel_widgets.dart';

/// SRS §9 Reels (Phase 11): the app's Reels-tab videos, newest first, as a
/// grid of 9:16 posters with status Active / Hidden / Product unavailable,
/// All / Active / Hidden filter chips, **New reel**, and per reel Edit,
/// Activate / Hide and Delete. Super admins, ops and content only.
class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen> {
  ReelFilter _filter = ReelFilter.all;
  int _limit = ReelsAdminRepository.pageSize;
  final _busy = <String>{};

  Future<void> _edit({ReelModel? reel}) async {
    final saved = await showReelEditor(context, reel: reel);
    if (saved && mounted) showMessage(context, reel == null ? 'Reel created' : 'Reel saved');
  }

  Future<void> _run(ReelModel reel, Future<String?> Function(String uid) action, String done) async {
    final uid = ref.read(adminSessionProvider)?.uid;
    if (uid == null) {
      showMessage(context, 'Your session has ended — sign in again.');
      return;
    }
    setState(() => _busy.add(reel.id));
    try {
      final warning = await action(uid);
      if (mounted) showMessage(context, warning == null ? done : '$done. $warning');
    } catch (e) {
      if (mounted) showMessage(context, 'Could not update the reel: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(reel.id));
    }
  }

  Future<void> _onAction(ReelModel reel, ReelCardAction action) async {
    final repo = ref.read(reelsAdminRepositoryProvider);
    switch (action) {
      case ReelCardAction.edit:
        await _edit(reel: reel);
      case ReelCardAction.toggleActive:
        final activate = !reel.isActive;
        await _run(reel, (uid) async {
          await repo.setActive(reel.id, activate, adminUid: uid);
          return null;
        }, activate ? 'Reel activated' : 'Reel hidden');
      case ReelCardAction.delete:
        final ok = await confirmAction(
          context,
          title: 'Delete this reel?',
          message: 'It disappears from the app’s Reels tab immediately, and its video and poster are deleted '
              'from Storage. To take it down for now, use Hide instead.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (!ok || !mounted) return;
        await _run(reel, (uid) => repo.delete(reel.id, adminUid: uid), 'Reel deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final allowed = session != null && ReelsAccess.canManage(session.role);
    return AdminScaffold(
      title: 'Reels',
      selectedRoute: AdminRoutes.reels,
      floatingActionButton: allowed
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('New reel'),
            )
          : null,
      body: session == null
          ? const SizedBox.shrink()
          : !allowed
              ? RoleLockedNotice(module: 'Reels', role: session.role, who: ReelsAccess.who)
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final reels = ref.watch(adminReelsProvider(_limit));
    final all = reels.valueOrNull ?? const <ReelModel>[];
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context));
    final chips = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final f in ReelFilter.values)
          ChoiceChip(
            key: ValueKey('reelFilter-${f.name}'),
            label: Text(reels.hasValue ? '${f.label} (${all.where(f.matches).length})' : f.label),
            selected: _filter == f,
            onSelected: (_) => setState(() => _filter = f),
          ),
        Text('Newest first · a reel shows in the app only while it is active and its product is active.', style: muted),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      chips,
      Expanded(
        child: reels.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => CenteredNote(
            icon: Icons.error_outline,
            text: 'Could not load reels: $e',
            action: OutlinedButton(
              onPressed: () => ref.invalidate(adminReelsProvider(_limit)),
              child: const Text('Retry'),
            ),
          ),
          data: (list) {
            final shown = list.where(_filter.matches).toList();
            if (shown.isEmpty) {
              return CenteredNote(
                icon: Icons.slow_motion_video_outlined,
                text: list.isEmpty
                    ? 'No reels yet — add the first product video with New reel.'
                    : 'No ${_filter.label.toLowerCase()} reels.',
              );
            }
            final more = list.length >= _limit;
            return CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 9 / 16,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => ReelCard(
                    key: ValueKey(shown[i].id),
                    reel: shown[i],
                    busy: _busy.contains(shown[i].id),
                    onAction: (a) => _onAction(shown[i], a),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 2),
                  child: Column(children: [
                    Text('${shown.length} shown', style: muted),
                    if (more)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: OutlinedButton(
                          onPressed: () => setState(() => _limit += ReelsAdminRepository.pageSize),
                          child: const Text('Load more'),
                        ),
                      ),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}
