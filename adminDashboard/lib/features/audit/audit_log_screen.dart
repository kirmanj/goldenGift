import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/firestore_parse.dart';
import 'package:intl/intl.dart';

import '../../core/router/admin_routes.dart';
import '../../core/widgets/admin_scaffold.dart';

class AuditEntry {
  const AuditEntry({required this.id, required this.adminUid, required this.action, required this.target, this.before, this.after, this.at});
  final String id;
  final String adminUid;
  final String action;
  final String target;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final DateTime? at;

  factory AuditEntry.fromMap(String id, Map<String, dynamic> m) => AuditEntry(
        id: id,
        adminUid: m['adminUid'] as String? ?? '',
        action: m['action'] as String? ?? '',
        target: m['target'] as String? ?? '',
        before: m['before'] is Map ? Map<String, dynamic>.from(m['before'] as Map) : null,
        after: m['after'] is Map ? Map<String, dynamic>.from(m['after'] as Map) : null,
        at: FirestoreParse.date(m['at']),
      );
}

final auditEntriesProvider = StreamProvider.autoDispose<List<AuditEntry>>((ref) => ref
    .watch(firestoreProvider)
    .collection(FirestorePaths.adminAuditLog)
    .orderBy('at', descending: true)
    .limit(200)
    .snapshots()
    .map((s) => [for (final d in s.docs) AuditEntry.fromMap(d.id, d.data())]));

/// The last 200 dashboard changes (SRS §9: every mutation is logged).
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(auditEntriesProvider);
    final fmt = DateFormat('yyyy-MM-dd HH:mm', 'en_US');
    return AdminScaffold(
      title: 'Audit log',
      selectedRoute: AdminRoutes.auditLog,
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load the audit log: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No changes recorded yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = list[i];
                  return ExpansionTile(
                    title: Text('${e.action} · ${e.target}'),
                    subtitle: Text('${e.at == null ? '…' : fmt.format(e.at!.toLocal())} · ${e.adminUid}'),
                    childrenPadding: const EdgeInsets.all(AppSpacing.md),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (e.before != null) SelectableText('Before: ${const JsonEncoder.withIndent('  ').convert(_jsonable(e.before!))}'),
                      if (e.after != null) SelectableText('After: ${const JsonEncoder.withIndent('  ').convert(_jsonable(e.after!))}'),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

Object? _jsonable(Object? v) => switch (v) {
      Map() => {for (final e in v.entries) '${e.key}': _jsonable(e.value)},
      List() => [for (final x in v) _jsonable(x)],
      String() || num() || bool() || null => v,
      _ => v.toString(),
    };
