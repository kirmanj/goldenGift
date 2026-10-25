import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/special_request_model.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/router/admin_routes.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../stores/widgets/detail_widgets.dart';
import 'data/special_requests_admin_repository.dart';
import 'special_request_ui.dart';

/// SRS §9 Special requests inbox: newest activity first, filters by status,
/// type (gift idea / support) and "awaiting reply"; a row opens the thread.
class SpecialRequestsScreen extends ConsumerStatefulWidget {
  const SpecialRequestsScreen({super.key});

  @override
  ConsumerState<SpecialRequestsScreen> createState() => _SpecialRequestsScreenState();
}

class _SpecialRequestsScreenState extends ConsumerState<SpecialRequestsScreen> {
  SpecialRequestFilters _filters = const SpecialRequestFilters();
  int _limit = SpecialRequestsAdminRepository.pageSize;

  void _set(SpecialRequestFilters f) => setState(() {
        _filters = f;
        _limit = SpecialRequestsAdminRepository.pageSize;
      });

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(adminSpecialRequestsProvider((_filters, _limit)));
    return AdminScaffold(
      title: 'Special requests',
      selectedRoute: AdminRoutes.specialRequests,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<SpecialRequestStatus?>(
                key: ValueKey('srStatus-${_filters.status}'),
                initialValue: _filters.status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: [
                  const DropdownMenuItem<SpecialRequestStatus?>(value: null, child: Text('All statuses')),
                  for (final s in SpecialRequestStatus.values)
                    DropdownMenuItem<SpecialRequestStatus?>(value: s, child: Text(specialRequestStatusLabel(s))),
                ],
                onChanged: (v) => _set(_filters.copyWith(status: v, clearStatus: v == null)),
              ),
            ),
            SegmentedButton<SpecialRequestType?>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: null, label: Text('All types')),
                ButtonSegment(value: SpecialRequestType.gift, label: Text('Gift ideas')),
                ButtonSegment(value: SpecialRequestType.support, label: Text('Support')),
              ],
              selected: {_filters.type},
              onSelectionChanged: (s) => _set(_filters.copyWith(type: s.first, clearType: s.first == null)),
            ),
            FilterChip(
              key: const ValueKey('awaitingReply'),
              label: const Text('Awaiting reply'),
              selected: _filters.awaitingReply,
              onSelected: (v) => _set(_filters.copyWith(awaitingReply: v)),
            ),
            if (_filters != const SpecialRequestFilters())
              TextButton(onPressed: () => _set(const SpecialRequestFilters()), child: const Text('Reset filters')),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: requests.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => CenteredNote(
              icon: Icons.error_outline,
              text: 'Could not load requests: $e\n\nA filter combination may need a Firestore index '
                  '(special_requests: status / type / lastMessageBy + lastMessageAt).',
            ),
            data: (list) => list.isEmpty
                ? const CenteredNote(icon: Icons.inbox_outlined, text: 'No requests match these filters.')
                : ListView.separated(
                    itemCount: list.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      if (i == list.length) {
                        return list.length < _limit
                            ? const SizedBox(height: AppSpacing.lg)
                            : Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Center(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() => _limit += SpecialRequestsAdminRepository.pageSize),
                                    child: const Text('Load more'),
                                  ),
                                ),
                              );
                      }
                      final r = list[i];
                      return SpecialRequestRow(
                        key: ValueKey(r.id),
                        request: r,
                        onTap: () => context.go(AdminRoutes.specialRequest(r.id)),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

class SpecialRequestRow extends StatelessWidget {
  const SpecialRequestRow({super.key, required this.request, required this.onTap});
  final SpecialRequestModel request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final awaiting = r.lastMessageBy == 'customer';
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 12);
    final at = r.lastMessageAt ?? r.updatedAt ?? r.createdAt;
    return ListTile(
      onTap: onTap,
      leading: Badge(
        isLabelVisible: awaiting,
        backgroundColor: AppColors.gold(context),
        smallSize: 10,
        child: CircleAvatar(
          backgroundColor: AppColors.soft(context),
          foregroundColor: AppColors.goldText(context),
          child: Icon(r.type == SpecialRequestType.gift ? Icons.lightbulb_outline : Icons.support_agent),
        ),
      ),
      title: Row(children: [
        Flexible(
          child: Text(
            [r.customerName ?? 'Customer', if (r.customerPhone != null) r.customerPhone!].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: awaiting ? FontWeight.w700 : FontWeight.w600),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SpecialRequestTypeChip(r.type),
        const SizedBox(width: AppSpacing.xs),
        SpecialRequestStatusChip(r.status),
      ]),
      subtitle: Text(firstLine(r.text), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(at == null ? '' : DateFormat('MMM d, HH:mm', 'en_US').format(at.toLocal()), style: muted),
        if (r.images.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.image_outlined, size: 14, color: AppColors.textMuted(context)),
            Text(' ${r.images.length}', style: muted),
          ])
        else if (awaiting)
          Text('Awaiting reply', style: muted.copyWith(color: AppColors.goldText(context))),
      ]),
    );
  }
}
