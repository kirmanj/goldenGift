import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/models/special_request_model.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/special_requests/data/special_requests_admin_repository.dart';
import 'package:golden_gift_admin/features/special_requests/special_request_detail_screen.dart';
import 'package:golden_gift_admin/features/special_requests/special_requests_screen.dart';

import '../products/products_test_helpers.dart' show RecordingFirestore;
import '../seller/phase8_test_harness.dart';

Map<String, dynamic> requestMap({
  String status = 'submitted',
  String type = 'gift',
  String lastBy = 'customer',
  DateTime? lastAt,
  String text = 'A wooden box engraved with our wedding date\nand two names',
  int? quote,
  String? orderId,
}) =>
    {
      'userId': 'cust-1',
      'type': type,
      'text': text,
      'images': ['https://example.com/r/1.jpg', 'https://example.com/r/2.jpg'],
      'status': status,
      'customerName': 'Sara',
      'customerPhone': '+9647501234567',
      'lastMessageAt': Timestamp.fromDate(lastAt ?? DateTime(2026, 10, 20, 9)),
      'lastMessageBy': lastBy,
      if (quote != null) 'quoteAmount': quote,
      if (quote != null) 'quoteNote': 'Ready in 3 days',
      if (orderId != null) 'orderId': orderId,
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 19, 9)),
    };

Future<SpecialRequestModel> seedRequest(FirebaseFirestore db, String id, Map<String, dynamic> data) async {
  await db.doc(FirestorePaths.specialRequestDoc(id)).set(data);
  return SpecialRequestModel.fromMap(id, data);
}

Future<List<Map<String, dynamic>>> messages(FirebaseFirestore db, String id) async =>
    [for (final d in (await db.collection(FirestorePaths.specialRequestMessages(id)).get()).docs) d.data()];

SpecialRequestModel model(SpecialRequestStatus status, {SpecialRequestType type = SpecialRequestType.gift}) =>
    SpecialRequestModel(id: 'r', userId: 'u', text: 't', status: status, type: type);

void main() {
  group('status rules', () {
    test('allowed transitions (SRS §5.17)', () {
      expect(requestTransitions(model(SpecialRequestStatus.submitted)),
          [SpecialRequestStatus.inReview, SpecialRequestStatus.rejected]);
      expect(requestTransitions(model(SpecialRequestStatus.inReview)),
          [SpecialRequestStatus.quoted, SpecialRequestStatus.rejected]);
      expect(requestTransitions(model(SpecialRequestStatus.quoted)),
          [SpecialRequestStatus.inReview, SpecialRequestStatus.rejected]);
      expect(requestTransitions(model(SpecialRequestStatus.accepted)), [SpecialRequestStatus.completed]);
      expect(requestTransitions(model(SpecialRequestStatus.rejected)), isEmpty);
      expect(requestTransitions(model(SpecialRequestStatus.completed)), isEmpty);
      // Support messages are never quoted; they are resolved instead.
      expect(requestTransitions(model(SpecialRequestStatus.inReview, type: SpecialRequestType.support)),
          [SpecialRequestStatus.completed, SpecialRequestStatus.rejected]);
      expect(canSendQuote(model(SpecialRequestStatus.submitted)), isFalse);
      expect(canSendQuote(model(SpecialRequestStatus.inReview)), isTrue);
    });

    test('quote validation and message text', () {
      expect(validateQuote(null, ''), 'Enter the quoted amount.');
      expect(validateQuote(999, ''), startsWith('A quote is at least 1,000 IQD'));
      expect(validateQuote(25000, 'x' * 501), startsWith('Keep the note under 500'));
      expect(validateQuote(25000, 'ok'), isNull);
      expect(quoteMessage(25000, ' Ready in 3 days '), 'Quote: 25,000 IQD — Ready in 3 days');
      expect(quoteMessage(25000, ''), 'Quote: 25,000 IQD');
    });
  });

  group('inbox query', () {
    test('newest activity first; status, type and awaiting-reply filters', () async {
      final db = FakeFirebaseFirestore();
      await seedRequest(db, 'a', requestMap(lastAt: DateTime(2026, 10, 18)));
      await seedRequest(db, 'b', requestMap(status: 'inReview', lastBy: 'admin', lastAt: DateTime(2026, 10, 20)));
      await seedRequest(db, 'c', requestMap(type: 'support', lastAt: DateTime(2026, 10, 19)));
      final repo = SpecialRequestsAdminRepository(db);
      Future<List<String>> ids(SpecialRequestFilters f) async => [for (final r in await repo.watch(f).first) r.id];
      expect(await ids(const SpecialRequestFilters()), ['b', 'c', 'a']);
      expect(await ids(const SpecialRequestFilters(status: SpecialRequestStatus.inReview)), ['b']);
      expect(await ids(const SpecialRequestFilters(type: SpecialRequestType.support)), ['c']);
      expect(await ids(const SpecialRequestFilters(awaitingReply: true)), ['c', 'a']);
      expect(await ids(const SpecialRequestFilters(type: SpecialRequestType.gift, awaitingReply: true)), ['a']);
      expect(const SpecialRequestFilters(status: SpecialRequestStatus.quoted).copyWith(clearStatus: true),
          const SpecialRequestFilters());
    });
  });

  group('writes', () {
    test('reply = message + request markers + submitted→inReview + audit, in ONE batch', () async {
      final db = RecordingFirestore();
      final r = await seedRequest(db, 'r1', requestMap());
      await SpecialRequestsAdminRepository(db).reply(r, '  We can do this!  ', adminUid: 'admin-1');
      expect(db.commits, hasLength(1));
      expect(db.commits.single, hasLength(3));
      final m = (await messages(db, 'r1')).single;
      expect(m['senderUid'], 'admin-1');
      expect(m['role'], 'admin');
      expect(m['text'], 'We can do this!');
      expect(m['images'], isEmpty);
      expect(m['at'], isNotNull);
      final saved = (await db.doc('special_requests/r1').get()).data()!;
      expect(saved['status'], 'inReview');
      expect(saved['lastMessageBy'], 'admin');
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'specialRequest.reply');
      expect(audit['before'], {'status': 'submitted'});
    });

    test('a reply keeps any later status and refuses empty text', () async {
      final db = FakeFirebaseFirestore();
      final r = await seedRequest(db, 'r1', requestMap(status: 'quoted', quote: 30000));
      final repo = SpecialRequestsAdminRepository(db);
      await repo.reply(r, 'Any questions?', adminUid: 'admin-1');
      expect((await db.doc('special_requests/r1').get()).data()!['status'], 'quoted');
      expect(() => repo.reply(r, '   ', adminUid: 'admin-1'), throwsA(isA<SpecialRequestException>()));
    });

    test('send quote: status quoted + amount + note + thread message + audit (one batch)', () async {
      final db = RecordingFirestore();
      final r = await seedRequest(db, 'r1', requestMap(status: 'inReview'));
      final repo = SpecialRequestsAdminRepository(db);
      await expectLater(repo.sendQuote(r, amount: 500, adminUid: 'admin-1'), throwsA(isA<SpecialRequestException>()));
      expect(db.commits, isEmpty);
      await repo.sendQuote(r, amount: 45000, note: 'Walnut, ready in 3 days', adminUid: 'admin-1');
      expect(db.commits.single, hasLength(3));
      final saved = (await db.doc('special_requests/r1').get()).data()!;
      expect(saved['status'], 'quoted');
      expect(saved['quoteAmount'], 45000);
      expect(saved['quoteNote'], 'Walnut, ready in 3 days');
      expect((await messages(db, 'r1')).single['text'], 'Quote: 45,000 IQD — Walnut, ready in 3 days');
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'specialRequest.quote');
      expect((audit['after'] as Map)['quoteAmount'], 45000);
    });

    test('a submitted request cannot be quoted before review', () async {
      final db = FakeFirebaseFirestore();
      final r = await seedRequest(db, 'r1', requestMap());
      expect(() => SpecialRequestsAdminRepository(db).sendQuote(r, amount: 45000, adminUid: 'a'),
          throwsA(isA<SpecialRequestException>()));
    });

    test('reject needs a reason, which is posted in the thread', () async {
      final db = FakeFirebaseFirestore();
      final r = await seedRequest(db, 'r1', requestMap());
      final repo = SpecialRequestsAdminRepository(db);
      expect(() => repo.setStatus(r, SpecialRequestStatus.rejected, adminUid: 'a'), throwsA(isA<SpecialRequestException>()));
      await repo.setStatus(r, SpecialRequestStatus.rejected, reason: 'We cannot engrave glass', adminUid: 'admin-1');
      final saved = (await db.doc('special_requests/r1').get()).data()!;
      expect(saved['status'], 'rejected');
      expect(saved['rejectReason'], 'We cannot engrave glass');
      expect(saved['lastMessageBy'], 'admin');
      expect((await messages(db, 'r1')).single['text'], 'We cannot engrave glass');
      expect((await auditEntries(db)).single['action'], 'specialRequest.status');
    });

    test('withdrawing a quote clears it and tells the customer', () async {
      final db = FakeFirebaseFirestore();
      final r = await seedRequest(db, 'r1', requestMap(status: 'quoted', quote: 30000));
      await SpecialRequestsAdminRepository(db).setStatus(r, SpecialRequestStatus.inReview, adminUid: 'admin-1');
      final saved = (await db.doc('special_requests/r1').get()).data()!;
      expect(saved['status'], 'inReview');
      expect(saved.containsKey('quoteAmount'), isFalse);
      expect(saved.containsKey('quoteNote'), isFalse);
      expect((await messages(db, 'r1')).single['text'], quoteWithdrawnMessage);
    });

    test('moves outside the rules are refused; completed only after acceptance', () async {
      final db = FakeFirebaseFirestore();
      final repo = SpecialRequestsAdminRepository(db);
      final submitted = await seedRequest(db, 'r1', requestMap());
      expect(() => repo.setStatus(submitted, SpecialRequestStatus.completed, adminUid: 'a'),
          throwsA(isA<SpecialRequestException>()));
      expect(() => repo.setStatus(submitted, SpecialRequestStatus.quoted, adminUid: 'a'),
          throwsA(isA<SpecialRequestException>()));
      final accepted = await seedRequest(db, 'r2', requestMap(status: 'accepted', quote: 30000, orderId: 'o1'));
      await repo.setStatus(accepted, SpecialRequestStatus.completed, adminUid: 'admin-1');
      expect((await db.doc('special_requests/r2').get()).data()!['status'], 'completed');
      expect(await messages(db, 'r2'), isEmpty);
      expect(await auditEntries(db), hasLength(1));
    });

    test('assign to me', () async {
      final db = FakeFirebaseFirestore();
      final r = await seedRequest(db, 'r1', requestMap());
      await SpecialRequestsAdminRepository(db).assignTo(r, adminUid: 'admin-1');
      expect((await db.doc('special_requests/r1').get()).data()!['assignedAdminUid'], 'admin-1');
      expect((await auditEntries(db)).single['action'], 'specialRequest.assign');
    });

    test('roles', () {
      expect(SpecialRequestsAccess.canAct(AdminRole.ops), isTrue);
      expect(SpecialRequestsAccess.canAct(AdminRole.finance), isFalse);
    });
  });

  group('screens', () {
    Future<FakeFirebaseFirestore> seeded() async {
      final db = FakeFirebaseFirestore();
      await seedRequest(db, 'r1', requestMap(lastAt: DateTime(2026, 10, 20)));
      await seedRequest(db, 'r2', requestMap(status: 'inReview', lastBy: 'admin', lastAt: DateTime(2026, 10, 19), text: 'Gold necklace with initials'));
      await seedRequest(db, 'r3', requestMap(type: 'support', lastAt: DateTime(2026, 10, 18), text: 'Where is my order?'));
      await db.collection(FirestorePaths.specialRequestMessages('r1')).add(
          {'senderUid': 'cust-1', 'role': 'customer', 'text': 'Is walnut possible?', 'images': [], 'at': Timestamp.fromDate(DateTime(2026, 10, 20))});
      return db;
    }

    testWidgets('inbox: newest first, first line only, awaiting-reply and type filters, row opens the thread', (tester) async {
      final db = await seeded();
      await pumpPhase8(tester, const SpecialRequestsScreen(), db: db);
      final first = find.text('A wooden box engraved with our wedding date');
      expect(first, findsOneWidget);
      expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(find.text('Gold necklace with initials')).dy));
      expect(find.text('and two names'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('awaitingReply')));
      await settle(tester);
      expect(find.text('Gold necklace with initials'), findsNothing);
      expect(find.text('Where is my order?'), findsOneWidget);

      await tester.tap(find.text('Gift ideas'));
      await settle(tester);
      expect(find.text('Where is my order?'), findsNothing);

      await tester.tap(first);
      await settle(tester);
      expect(find.text('visited: /special-requests/r1'), findsOneWidget);
    });

    testWidgets('detail: thread, reply (auto in review), quote dialog validation and send', (tester) async {
      final db = await seeded();
      await pumpPhase8(tester, const SpecialRequestDetailScreen(requestId: 'r1'), db: db, size: const Size(1440, 1100));
      expect(find.text('Is walnut possible?'), findsOneWidget);
      expect(find.text('Photos (2)'), findsOneWidget);
      expect(find.text('Send quote'), findsNothing, reason: 'a submitted request is reviewed first');

      await tester.enterText(find.byKey(const ValueKey('replyField')), 'Yes, walnut works.');
      await settle(tester);
      await tester.tap(find.text('Send'));
      await settle(tester);
      expect(find.text('Yes, walnut works.'), findsOneWidget);
      expect((await db.doc('special_requests/r1').get()).data()!['status'], 'inReview');

      await tester.tap(find.text('Send quote'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('quoteAmount')), '900');
      await tester.tap(find.widgetWithText(FilledButton, 'Send quote').last);
      await settle(tester);
      expect(find.textContaining('A quote is at least 1,000 IQD'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('quoteAmount')), '45000');
      await tester.enterText(find.byKey(const ValueKey('quoteNote')), 'Ready Thursday');
      await tester.tap(find.widgetWithText(FilledButton, 'Send quote').last);
      await settle(tester);
      final saved = (await db.doc('special_requests/r1').get()).data()!;
      expect(saved['status'], 'quoted');
      expect(saved['quoteAmount'], 45000);
      expect(find.text('Quote: 45,000 IQD — Ready Thursday'), findsOneWidget);
      expect(find.text('Withdraw quote'), findsOneWidget);
    });

    testWidgets('detail: reject asks for a reason; assign to me', (tester) async {
      final db = await seeded();
      await pumpPhase8(tester, const SpecialRequestDetailScreen(requestId: 'r1'), db: db, size: const Size(1440, 1100));
      await tester.tap(find.text('Assign to me'));
      await settle(tester);
      expect((await db.doc('special_requests/r1').get()).data()!['assignedAdminUid'], testAdmin.uid);
      expect(find.text('You'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await settle(tester);
      expect(find.text('A reason is required.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('reasonField')), 'Not something we make');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await settle(tester);
      expect((await db.doc('special_requests/r1').get()).data()!['status'], 'rejected');
    });

    testWidgets('read-only roles see the thread without actions', (tester) async {
      final db = await seeded();
      await pumpPhase8(tester, const SpecialRequestDetailScreen(requestId: 'r1'),
          db: db, session: staffSession(AdminRole.finance), size: const Size(1440, 1100));
      expect(find.text('Is walnut possible?'), findsOneWidget);
      expect(find.byKey(const ValueKey('replyField')), findsNothing);
      expect(find.text('Your role can read requests but not answer them.'), findsOneWidget);
    });

    for (final (mode, size) in layoutMatrix) {
      testWidgets('inbox + detail lay out in ${mode.name} at ${size.width.toInt()} px', (tester) async {
        final db = await seeded();
        await seedRequest(db, 'q', requestMap(status: 'accepted', quote: 30000, orderId: 'o1'));
        final errors = await errorsOutsideCoreNav(() async {
          await pumpPhase8(tester, const SpecialRequestsScreen(), db: db, mode: mode, size: size);
          expect(find.text('Where is my order?'), findsOneWidget);
          await pumpPhase8(tester, const SpecialRequestDetailScreen(requestId: 'q'), db: db, mode: mode, size: size);
          expect(find.text('Quote & order'), findsOneWidget);
          expect(find.text('Mark completed'), findsOneWidget);
        });
        expect(errors, isEmpty);
      });
    }
  });
}
