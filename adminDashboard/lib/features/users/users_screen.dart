import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/user_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import 'data/user_search.dart';
import 'data/users_admin_repository.dart';
import 'widgets/user_widgets.dart';

/// SRS §9 Users: newest users (50 per page) and a search box that reads the
/// input as a phone, an email or the start of a name.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _search = TextEditingController();
  UserSearchQuery _query = UserSearchQuery.recent;
  int _limit = UsersAdminRepository.pageSize;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _run() => setState(() {
        _query = UserSearchQuery.parse(_search.text);
        _limit = UsersAdminRepository.pageSize;
      });

  void _clear() {
    _search.clear();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    return AdminScaffold(
      title: 'Users',
      selectedRoute: AdminRoutes.users,
      body: session == null
          ? const SizedBox.shrink()
          : !UsersAccess.canView(session.role)
              ? RoleLockedNotice(module: 'Users', role: session.role, who: 'super admins, ops and finance')
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final users = ref.watch(adminUsersListProvider((_query, _limit)));
    final muted = AppColors.textMuted(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
        child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 420,
            child: TextField(
              key: const ValueKey('user-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Phone, email or name',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(tooltip: 'Clear', onPressed: _clear, icon: const Icon(Icons.clear)),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _run(),
            ),
          ),
          FilledButton.icon(onPressed: _run, icon: const Icon(Icons.search), label: const Text('Search')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        child: Text(
          '${_query.description}  Phones like 0750…, 750… or +964750… all work; '
          'names match from the first letter and are case-sensitive.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: users.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text('Could not load users: $e')),
          ),
          data: (list) => list.isEmpty
              ? Center(child: Text(_query.mode == UserSearchMode.recent ? 'No users yet.' : 'No users match.'))
              : _UsersTable(
                  users: list,
                  footer: LoadMoreButton(
                    visible: list.length >= _limit,
                    onPressed: () => setState(() => _limit += UsersAdminRepository.pageSize),
                  ),
                ),
        ),
      ),
    ]);
  }
}

class _UsersTable extends ConsumerWidget {
  const _UsersTable({required this.users, required this.footer});
  final List<UserModel> users;
  final Widget footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    String cityName(String? id) =>
        id == null ? '—' : (cities.where((c) => c.id == id).firstOrNull?.name.en ?? id);
    return ScrollableTable(
      footer: footer,
      table: DataTable(
        showCheckboxColumn: false,
        columnSpacing: AppSpacing.lg,
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Phone')),
          DataColumn(label: Text('Email')),
          DataColumn(label: Text('City')),
          DataColumn(label: Text('Orders'), numeric: true),
          DataColumn(label: Text('Spent'), numeric: true),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final u in users)
            DataRow(
              key: ValueKey(u.uid),
              onSelectChanged: (_) => context.go(AdminRoutes.user(u.uid)),
              cells: [
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(userDisplayName(u), style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                )),
                DataCell(LtrText(userPhone(u))),
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(u.email ?? '—', overflow: TextOverflow.ellipsis),
                )),
                DataCell(Text(cityName(u.city))),
                DataCell(Text('${u.totalOrders}')),
                DataCell(Text(CurrencyFormatter.format(u.totalSpent))),
                DataCell(UserStateChips(user: u)),
              ],
            ),
        ],
      ),
    );
  }
}
