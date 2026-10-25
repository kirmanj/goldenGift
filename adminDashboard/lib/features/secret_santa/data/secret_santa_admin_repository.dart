import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/models/secret_santa_model.dart';

import '../../../core/data/audit_log.dart';
import '../../../core/session/admin_session.dart';

/// Secret Santa is read-only in the dashboard (SRS §9). Revealing who drew
/// whom is a super-admin action that is audited before anything is shown.
class SecretSantaAccess {
  SecretSantaAccess._();

  static bool canReveal(AdminRole r) => r == AdminRole.superAdmin;
}

class RevealNotAllowedException implements Exception {
  const RevealNotAllowedException();

  @override
  String toString() => 'Only super admins can reveal Secret Santa assignments.';
}

String secretSantaStatusLabel(SecretSantaStatus s) => switch (s) {
      SecretSantaStatus.open => 'Open',
      SecretSantaStatus.drawn => 'Drawn',
      SecretSantaStatus.closed => 'Closed',
    };

String secretSantaTypeLabel(SecretSantaType t) => switch (t) {
      SecretSantaType.family => 'Family',
      SecretSantaType.friends => 'Friends',
      SecretSantaType.work => 'Work',
    };

/// How far the draw got: total assignment docs and, when only some members
/// have one, which members do (found with per-member count queries, so the
/// assignee is never read).
class AssignmentStatus {
  const AssignmentStatus({required this.count, required this.memberHasAssignment});
  final int count;

  /// uid → has an assignment doc.
  final Map<String, bool> memberHasAssignment;
}

/// One giver → assignee pair, read only after the reveal was audited.
class RevealedAssignment {
  const RevealedAssignment({required this.giverUid, required this.assignment});
  final String giverUid;
  final SecretSantaAssignment assignment;
}

/// Reads `secret_santa_groups` for monitoring (SRS §5.16, §6.14, §9).
class SecretSantaAdminRepository {
  SecretSantaAdminRepository(this._db);
  final FirebaseFirestore _db;

  static const pageSize = 50;

  CollectionReference<Map<String, dynamic>> get _groups => _db.collection(FirestorePaths.secretSantaGroups);

  /// Newest first; a status filter needs the index `status + createdAt desc`.
  Stream<List<SecretSantaGroup>> watchGroups({SecretSantaStatus? status, int limit = pageSize}) {
    Query<Map<String, dynamic>> q = _groups;
    if (status != null) q = q.where('status', isEqualTo: status.name);
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => [for (final d in s.docs) SecretSantaGroup.fromMap(d.id, d.data())]);
  }

  /// Invite codes are 8 upper-case characters (the app upper-cases input).
  static String normalizeInviteCode(String code) => code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  Stream<List<SecretSantaGroup>> watchByInviteCode(String code) => _groups
      .where('inviteCode', isEqualTo: normalizeInviteCode(code))
      .limit(10)
      .snapshots()
      .map((s) => [for (final d in s.docs) SecretSantaGroup.fromMap(d.id, d.data())]);

  Stream<SecretSantaGroup?> watchGroup(String id) => _db
      .doc(FirestorePaths.secretSantaDoc(id))
      .snapshots()
      .map((d) => d.exists ? SecretSantaGroup.fromMap(d.id, d.data()!) : null);

  /// By join time (the organiser first).
  Stream<List<SecretSantaMember>> watchMembers(String groupId) =>
      _db.collection(FirestorePaths.secretSantaMembers(groupId)).snapshots().map((s) => [
            for (final d in s.docs) SecretSantaMember.fromMap(d.id, d.data())
          ]..sort((a, b) => (a.joinedAt ?? DateTime(0)).compareTo(b.joinedAt ?? DateTime(0))));

  CollectionReference<Map<String, dynamic>> _assignments(String groupId) =>
      _db.collection('${FirestorePaths.secretSantaDoc(groupId)}/${FirestorePaths.assignments}');

  /// Count aggregates only — no assignment document is downloaded.
  Future<AssignmentStatus> assignmentStatus(String groupId, List<String> memberUids) async {
    final count = (await _assignments(groupId).count().get()).count ?? 0;
    if (count == 0 || count >= memberUids.length) {
      return AssignmentStatus(count: count, memberHasAssignment: {for (final uid in memberUids) uid: count > 0});
    }
    final checks = await Future.wait([
      for (final uid in memberUids)
        _assignments(groupId).where(FieldPath.documentId, isEqualTo: uid).count().get().then((s) => (s.count ?? 0) > 0),
    ]);
    return AssignmentStatus(
      count: count,
      memberHasAssignment: {for (var i = 0; i < memberUids.length; i++) memberUids[i]: checks[i]},
    );
  }

  /// Writes the `secretSanta.reveal` audit entry FIRST (its own committed
  /// batch), then reads the assignments. A failed audit write reveals nothing.
  Future<List<RevealedAssignment>> revealAssignments(String groupId, {required AdminSession session}) async {
    if (!SecretSantaAccess.canReveal(session.role)) throw const RevealNotAllowedException();
    final batch = _db.batch();
    AuditLog.add(batch, _db,
        adminUid: session.uid,
        action: 'secretSanta.reveal',
        target: FirestorePaths.secretSantaDoc(groupId),
        after: {'groupId': groupId});
    await batch.commit();
    final snap = await _assignments(groupId).get();
    return [
      for (final d in snap.docs)
        RevealedAssignment(giverUid: d.id, assignment: SecretSantaAssignment.fromMap(d.id, d.data())),
    ];
  }
}

final secretSantaAdminRepositoryProvider =
    Provider<SecretSantaAdminRepository>((ref) => SecretSantaAdminRepository(ref.watch(firestoreProvider)));

final adminSecretSantaGroupsProvider =
    StreamProvider.autoDispose.family<List<SecretSantaGroup>, (SecretSantaStatus?, int)>(
  (ref, args) => ref.watch(secretSantaAdminRepositoryProvider).watchGroups(status: args.$1, limit: args.$2),
);

final secretSantaInviteSearchProvider = StreamProvider.autoDispose.family<List<SecretSantaGroup>, String>(
  (ref, code) => ref.watch(secretSantaAdminRepositoryProvider).watchByInviteCode(code),
);

final adminSecretSantaGroupProvider = StreamProvider.autoDispose.family<SecretSantaGroup?, String>(
  (ref, id) => ref.watch(secretSantaAdminRepositoryProvider).watchGroup(id),
);

final adminSecretSantaMembersProvider = StreamProvider.autoDispose.family<List<SecretSantaMember>, String>(
  (ref, id) => ref.watch(secretSantaAdminRepositoryProvider).watchMembers(id),
);

/// Keyed by group id + member uids (so a join refreshes it).
final secretSantaAssignmentStatusProvider =
    FutureProvider.autoDispose.family<AssignmentStatus, (String, String)>((ref, args) {
  final uids = args.$2.isEmpty ? const <String>[] : args.$2.split(',');
  return ref.watch(secretSantaAdminRepositoryProvider).assignmentStatus(args.$1, uids);
});
