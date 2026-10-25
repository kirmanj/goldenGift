import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/secret_santa_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../stores/widgets/detail_widgets.dart';
import '../users/data/users_admin_repository.dart' show adminUserLookupProvider;
import 'data/secret_santa_admin_repository.dart';
import 'secret_santa_ui.dart';

/// SRS §9 Secret Santa: read-only list of groups, newest first, with a status
/// filter and a lookup by invite code; a row opens the group.
class SecretSantaScreen extends ConsumerStatefulWidget {
  const SecretSantaScreen({super.key});

  @override
  ConsumerState<SecretSantaScreen> createState() => _SecretSantaScreenState();
}

class _SecretSantaScreenState extends ConsumerState<SecretSantaScreen> {
  SecretSantaStatus? _status;
  int _limit = SecretSantaAdminRepository.pageSize;
  final _code = TextEditingController();

  /// The submitted invite code (null = the normal list).
  String? _search;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submitCode() {
    final code = SecretSantaAdminRepository.normalizeInviteCode(_code.text);
    setState(() => _search = code.isEmpty ? null : code);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _search != null
        ? ref.watch(secretSantaInviteSearchProvider(_search!))
        : ref.watch(adminSecretSantaGroupsProvider((_status, _limit)));
    return AdminScaffold(
      title: 'Secret Santa',
      selectedRoute: AdminRoutes.secretSanta,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<SecretSantaStatus?>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: null, label: Text('All')),
                    for (final s in SecretSantaStatus.values)
                      ButtonSegment(value: s, label: Text(secretSantaStatusLabel(s))),
                  ],
                  selected: {_status},
                  onSelectionChanged: _search != null
                      ? null
                      : (s) => setState(() {
                            _status = s.first;
                            _limit = SecretSantaAdminRepository.pageSize;
                          }),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    key: const ValueKey('inviteCodeSearch'),
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Invite code',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search == null
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _code.clear();
                                setState(() => _search = null);
                              },
                            ),
                    ),
                    onSubmitted: (_) => _submitCode(),
                  ),
                ),
                Text('Read-only monitoring', style: TextStyle(color: AppColors.textMuted(context))),
              ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: groups.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => CenteredNote(
              icon: Icons.error_outline,
              text: 'Could not load groups: $e\n\nThe status filter needs the Firestore index '
                  'secret_santa_groups: status + createdAt desc.',
            ),
            data: (list) => list.isEmpty
                ? CenteredNote(
                    icon: Icons.redeem_outlined,
                    text: _search != null ? 'No group has the invite code $_search.' : 'No Secret Santa groups yet.',
                  )
                : ListView.separated(
                    itemCount: list.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      if (i == list.length) {
                        return _search != null || list.length < _limit
                            ? const SizedBox(height: AppSpacing.lg)
                            : Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Center(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() => _limit += SecretSantaAdminRepository.pageSize),
                                    child: const Text('Load more'),
                                  ),
                                ),
                              );
                      }
                      final g = list[i];
                      return SecretSantaGroupRow(
                        key: ValueKey(g.id),
                        group: g,
                        onTap: () => context.go(AdminRoutes.secretSantaGroup(g.id)),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

class SecretSantaGroupRow extends ConsumerWidget {
  const SecretSantaGroupRow({super.key, required this.group, required this.onTap});
  final SecretSantaGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = group;
    final organiser = ref.watch(adminUserLookupProvider(g.organiserUid)).valueOrNull;
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 12);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.soft(context),
        foregroundColor: AppColors.goldText(context),
        child: const Icon(Icons.redeem_outlined),
      ),
      title: Row(children: [
        Flexible(
          child: Text(g.name.isEmpty ? '(unnamed group)' : g.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: AppSpacing.sm),
        SecretSantaTypePill(g.type),
        const SizedBox(width: AppSpacing.xs),
        SecretSantaStatusPill(g.status),
      ]),
      subtitle: Text(
        [
          'Organiser: ${organiser?.name.isNotEmpty == true ? organiser!.name : g.organiserUid}',
          '${g.memberUids.length} member${g.memberUids.length == 1 ? '' : 's'}',
          g.budget > 0 ? 'Budget ${CurrencyFormatter.format(g.budget)}' : 'No budget',
          if (g.exchangeDate != null) 'Exchange ${AppDates.display(g.exchangeDate!)}',
          'Code ${g.inviteCode}',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: g.createdAt == null ? null : Text('Created ${AppDates.display(g.createdAt!.toLocal())}', style: muted),
    );
  }
}
