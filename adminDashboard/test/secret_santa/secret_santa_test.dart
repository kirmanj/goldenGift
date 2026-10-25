import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/models/secret_santa_model.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/secret_santa/data/secret_santa_admin_repository.dart';
import 'package:golden_gift_admin/features/secret_santa/secret_santa_group_screen.dart';
import 'package:golden_gift_admin/features/secret_santa/secret_santa_screen.dart';

import '../seller/phase8_test_harness.dart';

Map<String, dynamic> groupMap({
  required String name,
  String status = 'open',
  String type = 'family',
  String code = 'ABCD2345',
  List<String> members = const ['u1', 'u2', 'u3'],
  int budget = 25000,
  DateTime? createdAt,
}) =>
    {
      'name': name,
      'type': type,
      'budget': budget,
      'exchangeDate': Timestamp.fromDate(DateTime(2026, 12, 24)),
      'organiserUid': 'u1',
      'status': status,
      'inviteCode': code,
      'memberUids': members,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 1)),
    };

/// g1 (drawn, 3 members, every assignment), g2 (open), g3 (closed) and the
/// organiser's users doc.
Future<FakeFirebaseFirestore> santaWorld([FakeFirebaseFirestore? db]) async {
  final d = db ?? FakeFirebaseFirestore();
  await d.doc(FirestorePaths.userDoc('u1')).set({'name': 'Sara Ahmed', 'phone': '+9647501112222'});
  await d.doc(FirestorePaths.secretSantaDoc('g1')).set(groupMap(name: 'Ahmed family', status: 'drawn', createdAt: DateTime(2026, 10, 3)));
  await d.doc(FirestorePaths.secretSantaDoc('g2')).set(groupMap(
      name: 'Office party', type: 'work', code: 'WXYZ6789', members: ['u1', 'u4'], budget: 0, createdAt: DateTime(2026, 10, 2)));
  await d.doc(FirestorePaths.secretSantaDoc('g3')).set(groupMap(name: 'Old friends', status: 'closed', code: 'QRST2345'));
  final members = [
    ('u1', 'Sara', '+9647501112222', 'A scarf'),
    ('u2', 'Omar', '+9647703334444', null),
    ('u3', 'Lana', null, 'Books please'),
  ];
  for (var i = 0; i < members.length; i++) {
    final (uid, name, phone, note) = members[i];
    await d.doc('${FirestorePaths.secretSantaMembers('g1')}/$uid').set({
      'name': name,
      'phone': phone,
      'joinedAt': Timestamp.fromDate(DateTime(2026, 10, 3, 10 + i)),
      if (note != null) 'wishlistNote': note,
    });
  }
  for (final (giver, assignee, name) in [('u1', 'u2', 'Omar'), ('u2', 'u3', 'Lana'), ('u3', 'u1', 'Sara')]) {
    await d.doc(FirestorePaths.secretSantaAssignment('g1', giver)).set({'assigneeUid': assignee, 'assigneeName': name});
  }
  return d;
}

/// Fails every batch commit (to prove nothing is revealed without its audit entry).
class FailingAuditFirestore extends FakeFirebaseFirestore {
  @override
  WriteBatch batch() => _FailingBatch(super.batch());
}

class _FailingBatch implements WriteBatch {
  _FailingBatch(this._inner);
  final WriteBatch _inner;

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) => _inner.set(document, data, options);
  @override
  void update(DocumentReference document, Map<String, dynamic> data) => _inner.update(document, data);
  @override
  void delete(DocumentReference document) => _inner.delete(document);
  @override
  Future<void> commit() async => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
}

void main() {
  group('repository', () {
    test('groups newest first, status filter, invite code lookup (normalised)', () async {
      final db = await santaWorld();
      final repo = SecretSantaAdminRepository(db);
      expect([for (final g in await repo.watchGroups().first) g.name], ['Ahmed family', 'Office party', 'Old friends']);
      expect([for (final g in await repo.watchGroups(status: SecretSantaStatus.open).first) g.name], ['Office party']);
      expect([for (final g in await repo.watchByInviteCode(' wxyz 6789 ').first) g.id], ['g2']);
      expect(await repo.watchByInviteCode('NOPE0000').first, isEmpty);
    });

    test('assignment status uses counts: none, all, and per member when partial', () async {
      final db = await santaWorld();
      final repo = SecretSantaAdminRepository(db);
      final all = await repo.assignmentStatus('g1', ['u1', 'u2', 'u3']);
      expect(all.count, 3);
      expect(all.memberHasAssignment.values, everyElement(isTrue));
      final none = await repo.assignmentStatus('g2', ['u1', 'u4']);
      expect(none.count, 0);
      expect(none.memberHasAssignment, {'u1': false, 'u4': false});

      await db.doc(FirestorePaths.secretSantaAssignment('g1', 'u3')).delete();
      final partial = await repo.assignmentStatus('g1', ['u1', 'u2', 'u3']);
      expect(partial.count, 2);
      expect(partial.memberHasAssignment, {'u1': true, 'u2': true, 'u3': false});
    });

    test('reveal: super only, audit entry first, then giver → assignee', () async {
      final db = await santaWorld();
      final repo = SecretSantaAdminRepository(db);
      await expectLater(
        repo.revealAssignments('g1', session: staffSession(AdminRole.ops)),
        throwsA(isA<RevealNotAllowedException>()),
      );
      expect(await auditEntries(db), isEmpty);

      final pairs = await repo.revealAssignments('g1', session: testAdmin);
      expect({for (final p in pairs) p.giverUid: p.assignment.assigneeUid}, {'u1': 'u2', 'u2': 'u3', 'u3': 'u1'});
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'secretSanta.reveal');
      expect(audit['target'], 'secret_santa_groups/g1');
      expect(audit['adminUid'], testAdmin.uid);
    });

    test('a failed audit write reveals nothing', () async {
      final db = await santaWorld(FailingAuditFirestore());
      await expectLater(
        SecretSantaAdminRepository(db).revealAssignments('g1', session: testAdmin),
        throwsA(isA<FirebaseException>()),
      );
    });
  });

  group('screens', () {
    testWidgets('list: name, type, status, organiser, members, budget; filter and invite code search', (tester) async {
      final db = await santaWorld();
      await pumpPhase8(tester, const SecretSantaScreen(), db: db, size: const Size(1440, 1000));
      expect(find.text('Ahmed family'), findsOneWidget);
      expect(find.text('Office party'), findsOneWidget);
      expect(find.text('Old friends'), findsOneWidget);
      expect(find.textContaining('Organiser: Sara Ahmed'), findsNWidgets(3));
      expect(find.textContaining('3 members · Budget 25,000 IQD'), findsNWidgets(2));
      expect(find.textContaining('2 members · No budget'), findsOneWidget);
      expect(find.text('Drawn'), findsWidgets);

      await tester.tap(find.text('Closed').first);
      await settle(tester);
      expect(find.text('Old friends'), findsOneWidget);
      expect(find.text('Ahmed family'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('inviteCodeSearch')), 'abcd2345');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('Ahmed family'), findsOneWidget);
      expect(find.text('Old friends'), findsNothing);
      expect(find.text('Office party'), findsNothing);

      await tester.tap(find.text('Ahmed family'));
      await settle(tester);
      expect(find.text('visited: /secret-santa/g1'), findsOneWidget);
    });

    testWidgets('group: members, wish notes, assignment marks — no pairs until revealed', (tester) async {
      final db = await santaWorld();
      await pumpPhase8(tester, const SecretSantaGroupScreen(groupId: 'g1'), db: db, size: const Size(1440, 1200));
      expect(find.text('Ahmed family'), findsOneWidget);
      expect(find.text('ABCD2345'), findsOneWidget);
      expect(find.text('Omar'), findsOneWidget);
      expect(find.text('Wish: Books please'), findsOneWidget);
      expect(find.textContaining('+9647703334444'), findsOneWidget);
      expect(find.text('3 of 3 have an assignment'), findsOneWidget);
      expect(find.text('Has assignment'), findsNWidgets(3));
      expect(find.byIcon(Icons.arrow_forward), findsNothing, reason: 'who drew whom stays hidden');

      await tester.tap(find.byKey(const ValueKey('revealAssignments')));
      await settle(tester);
      expect(find.text('Reveal assignments?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reveal'));
      await settle(tester);
      expect(find.byIcon(Icons.arrow_forward), findsNWidgets(3));
      expect((await auditEntries(db)).single['action'], 'secretSanta.reveal');
    });

    testWidgets('non-super staff cannot reveal', (tester) async {
      final db = await santaWorld();
      await pumpPhase8(tester, const SecretSantaGroupScreen(groupId: 'g1'), db: db, session: staffSession(AdminRole.ops));
      expect(find.byKey(const ValueKey('revealAssignments')), findsNothing);
      expect(find.text('Only super admins can reveal who drew whom.'), findsOneWidget);
    });

    testWidgets('a reveal whose audit write fails shows an error and no pairs', (tester) async {
      final db = await santaWorld(FailingAuditFirestore());
      await pumpPhase8(tester, const SecretSantaGroupScreen(groupId: 'g1'), db: db, size: const Size(1440, 1200));
      await tester.tap(find.byKey(const ValueKey('revealAssignments')));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Reveal'));
      await settle(tester);
      expect(find.textContaining('Could not reveal the assignments'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsNothing);
    });

    testWidgets('a group that is still open shows no assignments and no reveal', (tester) async {
      final db = await santaWorld();
      await db.doc('${FirestorePaths.secretSantaMembers('g2')}/u1').set({'name': 'Sara', 'joinedAt': Timestamp.now()});
      await pumpPhase8(tester, const SecretSantaGroupScreen(groupId: 'g2'), db: db);
      expect(find.text('0 of 1 have an assignment'), findsOneWidget);
      expect(find.text('No assignment'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('revealAssignments'))).onPressed, isNull);
    });

    for (final (mode, size) in layoutMatrix) {
      testWidgets('list + group lay out in ${mode.name} at ${size.width.toInt()} px', (tester) async {
        final db = await santaWorld();
        final errors = await errorsOutsideCoreNav(() async {
          await pumpPhase8(tester, const SecretSantaScreen(), db: db, mode: mode, size: size);
          expect(find.text('Ahmed family'), findsOneWidget);
          await pumpPhase8(tester, const SecretSantaGroupScreen(groupId: 'g1'), db: db, mode: mode, size: size);
          expect(find.text('Members (3)'), findsOneWidget);
        });
        expect(errors, isEmpty);
      });
    }
  });
}
