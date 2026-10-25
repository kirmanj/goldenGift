import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/services/callable.dart';
import '../../../models/secret_santa_model.dart';

enum SecretSantaFailureReason { notFound, alreadyDrawn, tooFewMembers, full, impossible, notOrganiser, unavailable, rateLimited, unknown }

class SecretSantaFailure implements Exception {
  const SecretSantaFailure(this.reason);
  final SecretSantaFailureReason reason;

  /// Server contract: `not-found` with a message (bad invite code / group —
  /// an undeployed function answers `not-found` / "NOT_FOUND"), `permission-denied`
  /// (not the organiser), `failed-precondition` {reason: drawn | too_few |
  /// full | impossible (exclusions leave no valid draw)}.
  factory SecretSantaFailure.from(Object error) {
    if (error is SecretSantaFailure) return error;
    if (error is FirebaseFunctionsException) {
      final details = error.details is Map ? Map<String, dynamic>.from(error.details as Map) : const <String, dynamic>{};
      return SecretSantaFailure(switch (error.code) {
        'not-found' when details['reason'] == null && error.message != 'NOT_FOUND' => SecretSantaFailureReason.notFound,
        'permission-denied' => SecretSantaFailureReason.notOrganiser,
        'resource-exhausted' => SecretSantaFailureReason.rateLimited,
        'failed-precondition' => switch (details['reason']) {
            'drawn' => SecretSantaFailureReason.alreadyDrawn,
            'too_few' => SecretSantaFailureReason.tooFewMembers,
            'full' => SecretSantaFailureReason.full,
            'impossible' => SecretSantaFailureReason.impossible,
            _ => SecretSantaFailureReason.unknown,
          },
        'not-found' || 'unimplemented' || 'internal' || 'unavailable' => SecretSantaFailureReason.unavailable,
        _ => SecretSantaFailureReason.unknown,
      });
    }
    return const SecretSantaFailure(SecretSantaFailureReason.unknown);
  }
}

/// Secret Santa (SRS §5.16). The organiser creates the group (client write:
/// group + own member doc in one batch); others join with the invite code via
/// `joinSecretSanta`; `drawSecretSanta` writes one private assignment per giver.
class SecretSantaRepository {
  SecretSantaRepository(this._db, this._call, {Random? random}) : _random = random ?? Random.secure();
  final FirebaseFirestore _db;
  final CallableInvoker _call;
  final Random _random;

  /// No 0/O/1/I so codes survive being read aloud.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String newInviteCode() => List.generate(8, (_) => _alphabet[_random.nextInt(_alphabet.length)]).join();

  Stream<List<SecretSantaGroup>> watchMine(String uid) => _db
      .collection(FirestorePaths.secretSantaGroups)
      .where('memberUids', arrayContains: uid)
      .snapshots()
      .map((s) => [for (final d in s.docs) SecretSantaGroup.fromMap(d.id, d.data())]
        ..sort((a, b) => (a.exchangeDate ?? DateTime(9999)).compareTo(b.exchangeDate ?? DateTime(9999))));

  Stream<SecretSantaGroup?> watch(String id) => _db
      .doc(FirestorePaths.secretSantaDoc(id))
      .snapshots()
      .map((s) => s.exists ? SecretSantaGroup.fromMap(s.id, s.data()!) : null);

  Stream<List<SecretSantaMember>> watchMembers(String id) => _db
      .collection(FirestorePaths.secretSantaMembers(id))
      .snapshots()
      .map((s) => [for (final d in s.docs) SecretSantaMember.fromMap(d.id, d.data())]
        ..sort((a, b) => (a.joinedAt ?? DateTime(0)).compareTo(b.joinedAt ?? DateTime(0))));

  Stream<SecretSantaAssignment?> watchMyAssignment(String groupId, String uid) => _db
      .doc(FirestorePaths.secretSantaAssignment(groupId, uid))
      .snapshots()
      .map((s) => s.exists ? SecretSantaAssignment.fromMap(uid, s.data()!) : null);

  Future<String> create({
    required String uid,
    required String organiserName,
    String? organiserPhone,
    required String name,
    required SecretSantaType type,
    required int budget,
    required DateTime exchangeDate,
  }) async {
    final ref = _db.collection(FirestorePaths.secretSantaGroups).doc();
    final batch = _db.batch();
    batch.set(ref, {
      'name': name.trim(),
      'type': type.name,
      'budget': budget,
      'exchangeDate': Timestamp.fromDate(exchangeDate),
      'organiserUid': uid,
      'status': SecretSantaStatus.open.name,
      'inviteCode': newInviteCode(),
      'memberUids': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.doc('${FirestorePaths.secretSantaMembers(ref.id)}/$uid'), {
      'name': organiserName.trim(),
      'phone': organiserPhone,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return ref.id;
  }

  /// Returns the group id.
  Future<String> join(String inviteCode, {required String name, String? wishlistNote}) async {
    try {
      final data = callableMap(await _call('joinSecretSanta', {
        'inviteCode': inviteCode.trim().toUpperCase(),
        'name': name.trim(),
        'wishlistNote': (wishlistNote?.trim().isEmpty ?? true) ? null : wishlistNote!.trim(),
      }));
      return data['groupId'] as String? ?? '';
    } catch (e) {
      throw SecretSantaFailure.from(e);
    }
  }

  /// The member's own wish note (shown to whoever draws them).
  Future<void> setWishlistNote(String groupId, String uid, String note) => _db
      .doc('${FirestorePaths.secretSantaMembers(groupId)}/$uid')
      .update({'wishlistNote': note.trim().isEmpty ? null : note.trim()});

  Future<void> draw(String groupId) async {
    try {
      await _call('drawSecretSanta', {'groupId': groupId});
    } catch (e) {
      throw SecretSantaFailure.from(e);
    }
  }
}

final secretSantaRepositoryProvider = Provider<SecretSantaRepository>(
    (ref) => SecretSantaRepository(ref.watch(firestoreProvider), ref.watch(callableInvokerProvider)));

final mySecretSantaGroupsProvider = StreamProvider.autoDispose<List<SecretSantaGroup>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(secretSantaRepositoryProvider).watchMine(uid);
});

final secretSantaGroupProvider = StreamProvider.autoDispose.family<SecretSantaGroup?, String>(
    (ref, id) => ref.watch(secretSantaRepositoryProvider).watch(id));

final secretSantaMembersProvider = StreamProvider.autoDispose.family<List<SecretSantaMember>, String>(
    (ref, id) => ref.watch(secretSantaRepositoryProvider).watchMembers(id));

final mySecretSantaAssignmentProvider = StreamProvider.autoDispose.family<SecretSantaAssignment?, String>((ref, groupId) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(secretSantaRepositoryProvider).watchMyAssignment(groupId, uid);
});
