import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/secret_santa_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../reviews/review_ui.dart' show LinkText;
import '../stores/widgets/detail_widgets.dart';
import '../users/data/users_admin_repository.dart' show adminUserLookupProvider;
import 'data/secret_santa_admin_repository.dart';
import 'secret_santa_ui.dart';

/// One Secret Santa group, read-only (SRS §9): details, members (name, phone,
/// joined, wish note) and whether each has drawn an assignment. Who drew whom
/// stays hidden unless a super admin presses "Reveal assignments", which is
/// written to the audit log before anything is shown.
class SecretSantaGroupScreen extends ConsumerWidget {
  const SecretSantaGroupScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(adminSecretSantaGroupProvider(groupId));
    return AdminScaffold(
      title: 'Secret Santa group',
      selectedRoute: AdminRoutes.secretSanta,
      body: group.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => CenteredNote(icon: Icons.error_outline, text: 'Could not load the group: $e'),
        data: (g) => g == null
            ? CenteredNote(
                icon: Icons.redeem_outlined,
                text: 'This group no longer exists.',
                action: OutlinedButton(
                    onPressed: () => context.go(AdminRoutes.secretSanta), child: const Text('Back to groups')),
              )
            : _Body(group: g),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.group});
  final SecretSantaGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = group;
    final organiser = ref.watch(adminUserLookupProvider(g.organiserUid)).valueOrNull;
    final members = ref.watch(adminSecretSantaMembersProvider(g.id));
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(children: [
          IconButton(
            tooltip: 'Back to groups',
            onPressed: () => context.go(AdminRoutes.secretSanta),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(g.name.isEmpty ? '(unnamed group)' : g.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          SecretSantaTypePill(g.type),
          const SizedBox(width: AppSpacing.xs),
          SecretSantaStatusPill(g.status),
        ]),
        const SizedBox(height: AppSpacing.md),
        SectionCard(title: 'Group', children: [
          KeyValueRow('Invite code', g.inviteCode, copy: g.inviteCode),
          KeyValueRow('Organiser', organiser?.name ?? g.organiserUid,
              child: g.organiserUid.isEmpty
                  ? null
                  : LinkText(
                      [
                        if (organiser != null && organiser.name.isNotEmpty) organiser.name,
                        if (organiser != null && organiser.phone.isNotEmpty) organiser.phone,
                        if (organiser == null || organiser.name.isEmpty) g.organiserUid,
                      ].join(' · '),
                      onTap: () => context.go(AdminRoutes.user(g.organiserUid)),
                    )),
          KeyValueRow('Budget', g.budget > 0 ? CurrencyFormatter.format(g.budget) : 'No budget'),
          KeyValueRow('Exchange date', g.exchangeDate == null ? '' : AppDates.display(g.exchangeDate!)),
          KeyValueRow('Members',
              '${g.memberUids.length} (min ${SecretSantaGroup.minMembers}, max ${SecretSantaGroup.maxMembers})'),
          KeyValueRow('Created', g.createdAt == null ? '' : AppDates.displayWithTime(g.createdAt!.toLocal())),
          if (g.drawnAt != null) KeyValueRow('Drawn', AppDates.displayWithTime(g.drawnAt!.toLocal())),
        ]),
        const SizedBox(height: AppSpacing.md),
        members.when(
          loading: () => const SectionCard(title: 'Members', children: [LinearProgressIndicator()]),
          error: (e, _) => SectionCard(title: 'Members', children: [Text('Could not load members: $e')]),
          data: (list) => _Members(group: g, members: list),
        ),
      ],
    );
  }
}

class _Members extends ConsumerStatefulWidget {
  const _Members({required this.group, required this.members});
  final SecretSantaGroup group;
  final List<SecretSantaMember> members;

  @override
  ConsumerState<_Members> createState() => _MembersState();
}

class _MembersState extends ConsumerState<_Members> {
  List<RevealedAssignment>? _revealed;
  bool _revealing = false;
  String? _error;

  Future<void> _reveal() async {
    final session = ref.read(adminSessionProvider);
    if (session == null) return;
    final ok = await confirmAction(
      context,
      title: 'Reveal assignments?',
      message: 'This shows who drew whom in “${widget.group.name}”. Members never see each other’s assignments; '
          'your name, the group and the time are recorded in the audit log before anything is shown.',
      confirmLabel: 'Reveal',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _revealing = true;
      _error = null;
    });
    try {
      final list =
          await ref.read(secretSantaAdminRepositoryProvider).revealAssignments(widget.group.id, session: session);
      if (mounted) setState(() => _revealed = list);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reveal the assignments: $e');
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final uids = [for (final m in members) m.uid];
    final status = ref.watch(secretSantaAssignmentStatusProvider((widget.group.id, uids.join(','))));
    final session = ref.watch(adminSessionProvider);
    final canReveal = session != null && SecretSantaAccess.canReveal(session.role);
    final names = {for (final m in members) m.uid: m.name};
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 12);

    final assigned = status.valueOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        title: 'Members (${members.length})',
        trailing: Text(
          status.when(
            data: (s) => '${s.count} of ${members.length} have an assignment',
            loading: () => 'Checking assignments…',
            error: (_, __) => 'Assignments unknown',
          ),
          style: muted,
        ),
        children: [
          if (members.isEmpty) const Text('No members yet.'),
          for (final m in members)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.soft(context),
                  foregroundColor: AppColors.goldText(context),
                  child: Text(m.name.isEmpty ? '?' : m.name.characters.first.toUpperCase()),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text(m.name.isEmpty ? m.uid : m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      if (m.uid == widget.group.organiserUid) ...[
                        const SizedBox(width: AppSpacing.xs),
                        const StatusPill(label: 'Organiser', color: AppColors.primaryDark),
                      ],
                    ]),
                    Text(
                      [
                        if (m.phone != null && m.phone!.isNotEmpty) m.phone!,
                        if (m.joinedAt != null) 'Joined ${AppDates.displayWithTime(m.joinedAt!.toLocal())}',
                      ].join(' · '),
                      style: muted,
                    ),
                    if (m.wishlistNote != null && m.wishlistNote!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Text('Wish: ${m.wishlistNote!}', maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                  ]),
                ),
                const SizedBox(width: AppSpacing.sm),
                _AssignedMark(has: assigned?.memberHasAssignment[m.uid]),
              ]),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      SectionCard(
        title: 'Assignments',
        children: [
          Text(
            'Each member sees only their own assignee in the app. Assignments stay hidden here too unless a super '
            'admin reveals them (for a dispute or support case); every reveal is audited.',
            style: muted,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_revealed == null)
            Align(
              alignment: Alignment.centerLeft,
              child: canReveal
                  ? OutlinedButton.icon(
                      key: const ValueKey('revealAssignments'),
                      onPressed: _revealing || (assigned?.count ?? 0) == 0 ? null : _reveal,
                      icon: _revealing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.visibility_outlined),
                      label: const Text('Reveal assignments'),
                    )
                  : Text('Only super admins can reveal who drew whom.', style: muted),
            )
          else if (_revealed!.isEmpty)
            const Text('No assignments were found.')
          else
            for (final a in _revealed!)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(children: [
                  Expanded(child: Text(names[a.giverUid] ?? a.giverUid, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Icon(Icons.arrow_forward, size: 16, color: AppColors.gold(context)),
                  ),
                  Expanded(
                    child: Text(
                      a.assignment.assigneeName.isNotEmpty
                          ? a.assignment.assigneeName
                          : (names[a.assignment.assigneeUid] ?? a.assignment.assigneeUid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    ]);
  }
}

class _AssignedMark extends StatelessWidget {
  const _AssignedMark({required this.has});
  final bool? has;

  @override
  Widget build(BuildContext context) => switch (has) {
        null => const SizedBox(width: 96),
        true => const StatusPill(label: 'Has assignment', color: AppColors.success),
        false => StatusPill(label: 'No assignment', color: AppColors.textMuted(context)),
      };
}
