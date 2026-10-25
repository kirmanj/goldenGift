import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/features/secret_santa/data/secret_santa_repository.dart';
import 'package:golden_gift/models/secret_santa_model.dart';

void main() {
  test('create writes the group and the organiser as first member in one batch', () async {
    final db = FakeFirebaseFirestore();
    final repo = SecretSantaRepository(db, (_, __) async => null, random: Random(1));
    final id = await repo.create(
      uid: 'u1',
      organiserName: 'Sara',
      name: ' Office 2026 ',
      type: SecretSantaType.work,
      budget: 25000,
      exchangeDate: DateTime(2026, 12, 24),
    );
    final group = (await repo.watch(id).first)!;
    expect(group.name, 'Office 2026');
    expect(group.memberUids, ['u1']);
    expect(group.isOrganiser('u1'), isTrue);
    expect(group.canDraw, isFalse); // needs 3 members
    expect(group.inviteCode, matches(RegExp(r'^[A-HJ-NP-Z2-9]{8}$')));
    expect(group.joinLink, 'https://goldengift.app/s/${group.inviteCode}');
    expect((await repo.watchMembers(id).first).single.name, 'Sara');
    expect((await repo.watchMine('u1').first).single.id, id);
  });

  test('my assignment is read from the private assignments doc', () async {
    final db = FakeFirebaseFirestore();
    await db.doc(FirestorePaths.secretSantaAssignment('g1', 'u1')).set({
      'assigneeUid': 'u2',
      'assigneeName': 'Karwan',
      'assigneeWishlistNote': 'Books',
      'drawnAt': Timestamp.fromDate(DateTime(2026, 12, 1)),
    });
    final repo = SecretSantaRepository(db, (_, __) async => null);
    final a = await repo.watchMyAssignment('g1', 'u1').first;
    expect(a!.assigneeName, 'Karwan');
    expect(await repo.watchMyAssignment('g1', 'u3').first, isNull);
  });

  test('join normalizes the code; failures are mapped', () async {
    final sent = <Map<String, dynamic>>[];
    final repo = SecretSantaRepository(FakeFirebaseFirestore(), (name, data) async {
      expect(name, 'joinSecretSanta');
      sent.add(data);
      return {'groupId': 'g1'};
    });
    expect(await repo.join(' abcd2345 ', name: 'Lana', wishlistNote: ' '), 'g1');
    expect(sent.single, {'inviteCode': 'ABCD2345', 'name': 'Lana', 'wishlistNote': null});

    Future<SecretSantaFailureReason> reasonFor(FirebaseFunctionsException e) async {
      try {
        await SecretSantaRepository(FakeFirebaseFirestore(), (_, __) async => throw e).draw('g1');
      } on SecretSantaFailure catch (f) {
        return f.reason;
      }
      fail('expected SecretSantaFailure');
    }

    expect(await reasonFor(FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'too_few'})),
        SecretSantaFailureReason.tooFewMembers);
    expect(await reasonFor(FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'impossible'})),
        SecretSantaFailureReason.impossible);
    expect(await reasonFor(FirebaseFunctionsException(code: 'permission-denied', message: '')),
        SecretSantaFailureReason.notOrganiser);
    expect(await reasonFor(FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND')),
        SecretSantaFailureReason.unavailable);
    expect(await reasonFor(FirebaseFunctionsException(code: 'not-found', message: 'No group with that code')),
        SecretSantaFailureReason.notFound);
  });
}
