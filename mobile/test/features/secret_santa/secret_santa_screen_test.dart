import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/secret_santa/presentation/providers/secret_santa_providers.dart';

import '../ai_search/phase9_harness.dart';

final _en = l10nFor('en');

Finder _field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

const _names = {'u1': 'Sara', 'u2': 'Karwan', 'u3': 'Lana', 'u4': 'Dilan'};

Future<void> seedGroup(
  FakeFirebaseFirestore db, {
  String id = 'g1',
  String name = 'Office 2026',
  String organiser = 'u1',
  List<String> members = const ['u1', 'u2', 'u3'],
  String status = 'open',
  int budget = 25000,
  String type = 'work',
  String code = 'ABCD2345',
  Map<String, String> notes = const {},
}) async {
  await db.doc('secret_santa_groups/$id').set({
    'name': name,
    'type': type,
    'budget': budget,
    'exchangeDate': Timestamp.fromDate(DateTime(2026, 12, 24)),
    'organiserUid': organiser,
    'status': status,
    'inviteCode': code,
    'memberUids': members,
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
  });
  for (var i = 0; i < members.length; i++) {
    final uid = members[i];
    await db.doc('secret_santa_groups/$id/members/$uid').set({
      'name': _names[uid] ?? uid,
      'joinedAt': Timestamp.fromDate(DateTime(2026, 10, 1, 10, i)),
      if (notes[uid] != null) 'wishlistNote': notes[uid],
    });
  }
}

Future<void> seedAssignment(FakeFirebaseFirestore db, String giver, String assignee, {String? note, String group = 'g1'}) =>
    db.doc('secret_santa_groups/$group/assignments/$giver').set({
      'assigneeUid': assignee,
      'assigneeName': _names[assignee] ?? assignee,
      'assigneeWishlistNote': note,
      'drawnAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
    });

void main() {
  group('helpers', () {
    test('invite codes: typed, spaced, dashed or as the whole link', () {
      expect(normalizeInviteCode(' abcd 2345 '), 'ABCD2345');
      expect(normalizeInviteCode('ABCD-2345'), 'ABCD2345');
      expect(normalizeInviteCode('https://goldengift.app/s/ABCD2345'), 'ABCD2345');
      expect(normalizeInviteCode('ABCD1234'), isNull); // 1 is not in the alphabet
      expect(normalizeInviteCode('ABC'), isNull);
    });

    test('Shop for them: price bands that start within the budget', () {
      expect(shopForThemQuery(25000).priceBands, {0, 1});
      expect(shopForThemQuery(49999).priceBands, {0, 1});
      expect(shopForThemQuery(100000).priceBands, {0, 1, 2, 3});
      expect(shopForThemQuery(500000).priceBands, {0, 1, 2, 3, 4});
      expect(shopForThemQuery(0), const ProductQuery());
    });
  });

  group('my groups', () {
    testWidgets('guests see the sign-in card', (tester) async {
      await pumpPhase9(tester, initialPath: AppRoutes.secretSanta, guest: true);
      expect(find.byKey(const ValueKey('guest-sign-in-card')), findsOneWidget);
    });

    testWidgets('empty state, Create group and Join with a code', (tester) async {
      await pumpPhase9(tester, initialPath: AppRoutes.secretSanta);
      expect(find.byKey(const ValueKey('santa-empty')), findsOneWidget);
      expect(find.text(_en.secretSantaCreateGroup), findsOneWidget);
      expect(find.text(_en.secretSantaJoinWithCode), findsOneWidget);
    });

    testWidgets('cards: name, type · budget · members, date, status and organiser badge', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db);
      await seedGroup(db, id: 'g2', name: 'Family Eid', organiser: 'u2', status: 'drawn', type: 'family', budget: 0);
      final h = await pumpPhase9(tester, initialPath: AppRoutes.secretSanta, firestore: db);
      expect(find.text('Office 2026'), findsOneWidget);
      expect(find.text('Family Eid'), findsOneWidget);
      expect(find.text('${_en.secretSantaTypeWork} · 25,000 IQD per gift · ${_en.secretSantaMembersCount(3)}'),
          findsOneWidget);
      expect(find.text('${_en.secretSantaTypeFamily} · ${_en.secretSantaNoBudget} · ${_en.secretSantaMembersCount(3)}'),
          findsOneWidget);
      expect(find.text(_en.secretSantaExchangeOn('24/12/2026')), findsNWidgets(2));
      expect(find.byKey(const ValueKey('santa-status-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('santa-status-drawn')), findsOneWidget);
      expect(find.text(_en.secretSantaOrganiserBadge), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('santa-group-g2')));
      expect(h.location, AppRoutes.secretSantaGroupFor('g2'));
      expect(find.byKey(const ValueKey('santa-group-name-title')), findsOneWidget);
    });

    testWidgets('a bad code is refused; a valid one (any case, spaces) opens the join flow', (tester) async {
      final h = await pumpPhase9(tester, initialPath: AppRoutes.secretSanta);
      await tester.enterText(_field('santa-join-code'), 'abc');
      await _tap(tester, find.byKey(const ValueKey('santa-join-submit')));
      expect(find.text(_en.secretSantaInvalidCode), findsOneWidget);
      expect(h.location, AppRoutes.secretSanta);

      await tester.enterText(_field('santa-join-code'), ' abcd 2345 ');
      await _tap(tester, find.byKey(const ValueKey('santa-join-submit')));
      expect(h.location, AppRoutes.secretSantaJoin('ABCD2345'));
      expect(find.text(_en.secretSantaJoinBody('ABCD2345')), findsOneWidget);
    });
  });

  group('create', () {
    Future<void> openForm(WidgetTester tester) async {
      await _tap(tester, find.byKey(const ValueKey('santa-create-open')));
      expect(find.byKey(const ValueKey('santa-create-form')), findsOneWidget);
    }

    Future<void> pickTomorrow(WidgetTester tester) async {
      await _tap(tester, find.byKey(const ValueKey('santa-date')));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('validates, writes the group + organiser and opens the group page', (tester) async {
      final h = await pumpPhase9(tester, initialPath: AppRoutes.secretSanta);
      await openForm(tester);
      // Name prefilled from the profile.
      expect(tester.widget<TextField>(_field('santa-your-name')).controller!.text, 'Sara Ahmed');

      await _tap(tester, find.byKey(const ValueKey('santa-create')));
      expect(find.text(_en.errorRequired), findsNWidgets(2)); // group name + date
      expect((await h.firestore.collection('secret_santa_groups').get()).docs, isEmpty);

      await tester.enterText(_field('santa-group-name'), ' Office 2026 ');
      await _tap(tester, find.byKey(const ValueKey('santa-type-work')));
      await _tap(tester, find.byKey(const ValueKey('santa-budget-50000')));
      await pickTomorrow(tester);
      expect(tester.widget<TextField>(_field('santa-date')).controller!.text, '22/10/2026');
      await _tap(tester, find.byKey(const ValueKey('santa-create')));

      final docs = (await h.firestore.collection('secret_santa_groups').get()).docs;
      expect(docs, hasLength(1));
      final group = docs.single.data();
      expect(group['name'], 'Office 2026');
      expect(group['type'], 'work');
      expect(group['budget'], 50000);
      expect((group['exchangeDate'] as Timestamp).toDate(), DateTime(2026, 10, 22));
      expect(group['organiserUid'], 'u1');
      expect(group['memberUids'], ['u1']);
      expect(group['status'], 'open');
      final member = (await h.firestore.doc('secret_santa_groups/${docs.single.id}/members/u1').get()).data()!;
      expect(member['name'], 'Sara Ahmed');
      expect(member['phone'], '+9647501234567');

      expect(h.location, AppRoutes.secretSantaGroupFor(docs.single.id));
      expect(find.byKey(const ValueKey('santa-invite-code')), findsOneWidget);
      expect(find.byKey(const ValueKey('santa-organiser-badge')), findsOneWidget);
      // One member: Draw is disabled with the reason.
      expect(find.byKey(const ValueKey('santa-draw-hint')), findsOneWidget);
    });

    testWidgets('a custom budget needs an amount', (tester) async {
      final h = await pumpPhase9(tester, initialPath: AppRoutes.secretSanta);
      await openForm(tester);
      await tester.enterText(_field('santa-group-name'), 'Friends');
      await _tap(tester, find.byKey(const ValueKey('santa-budget-custom')));
      await pickTomorrow(tester);
      await _tap(tester, find.byKey(const ValueKey('santa-create')));
      expect(find.text(_en.secretSantaBudgetError), findsOneWidget);

      await tester.enterText(_field('santa-budget-amount'), '15000');
      await _tap(tester, find.byKey(const ValueKey('santa-create')));
      final group = (await h.firestore.collection('secret_santa_groups').get()).docs.single.data();
      expect(group['budget'], 15000);
      expect(group['type'], 'friends');
    });
  });

  group('group page', () {
    testWidgets('invite: big code, Copy and a localized share text with the link', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final h = await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db);

      expect(tester.widget<Text>(find.byKey(const ValueKey('santa-invite-code'))).data, 'ABCD2345');
      await _tap(tester, find.byKey(const ValueKey('santa-copy-code')));
      expect(copied, ['ABCD2345']);
      expect(find.text(_en.codeCopied), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('santa-share-link')));
      expect(h.shared.single.text,
          _en.secretSantaShareText('Office 2026', 'https://goldengift.app/s/ABCD2345', 'ABCD2345'));
      expect(h.shared.single.subject, _en.secretSantaShareSubject);
      expect(h.analytics.events[AnalyticsEvents.share]?['content_type'], 'secret_santa');
    });

    testWidgets('members by name with the organiser badge; no one sees assignments before the draw',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db, notes: {'u2': 'Secret wish of Karwan'});
      await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db);
      expect(find.text(_en.secretSantaMembersOf(3, 50)), findsOneWidget);
      expect(find.text('Sara (${_en.secretSantaYou})'), findsOneWidget);
      expect(find.text('Karwan'), findsOneWidget);
      expect(find.text('Lana'), findsOneWidget);
      expect(find.text(_en.secretSantaOrganiser), findsOneWidget);
      // Other members' wish notes are never listed.
      expect(find.text('Secret wish of Karwan'), findsNothing);
      expect(find.byKey(const ValueKey('santa-assignment')), findsNothing);
    });

    testWidgets('organiser draws after confirming (3+ members)', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db);
      final fns = FakeCallables()..handlers['drawSecretSanta'] = (_) => {'ok': true};
      final h = await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db, callables: fns);

      await _tap(tester, find.byKey(const ValueKey('santa-draw')));
      expect(find.text(_en.secretSantaDrawConfirmTitle), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('santa-draw-cancel')));
      expect(fns.calls, isEmpty);

      await _tap(tester, find.byKey(const ValueKey('santa-draw')));
      await _tap(tester, find.byKey(const ValueKey('santa-draw-confirm')));
      expect(fns.callsTo('drawSecretSanta'), [
        {'groupId': 'g1'},
      ]);
      expect(find.text(_en.secretSantaDrawDone), findsOneWidget);
      expect(h.location, AppRoutes.secretSantaGroupFor('g1'));
    });

    testWidgets('Draw is disabled below 3 members, with the reason', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db, members: const ['u1', 'u2']);
      await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db);
      final button = tester.widget<ElevatedButton>(
          find.descendant(of: find.byKey(const ValueKey('santa-draw')), matching: find.byType(ElevatedButton)));
      expect(button.onPressed, isNull);
      expect(find.text(_en.secretSantaDrawHint(3)), findsOneWidget);
    });

    testWidgets('only the organiser can draw: members see "waiting"', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db, organiser: 'u2');
      await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db);
      expect(find.byKey(const ValueKey('santa-draw')), findsNothing);
      expect(find.byKey(const ValueKey('santa-waiting')), findsOneWidget);
      expect(find.byKey(const ValueKey('santa-organiser-badge')), findsNothing);
    });

    for (final (details, code, message) in [
      ({'reason': 'impossible'}, 'failed-precondition', _en.secretSantaErrorImpossible),
      ({'reason': 'too_few'}, 'failed-precondition', _en.secretSantaDrawHint(3)),
      ({'reason': 'drawn'}, 'failed-precondition', _en.secretSantaErrorAlreadyDrawn),
      (<String, String>{}, 'permission-denied', _en.secretSantaErrorNotOrganiser),
      (<String, String>{}, 'internal', _en.secretSantaErrorUnavailable),
    ]) {
      testWidgets('draw failure $code ${details['reason'] ?? ''} → "$message"', (tester) async {
        final db = FakeFirebaseFirestore();
        await seedGroup(db);
        final fns = FakeCallables()
          ..handlers['drawSecretSanta'] =
              (_) => throw FirebaseFunctionsException(code: code, message: 'x', details: details);
        await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db, callables: fns);
        await _tap(tester, find.byKey(const ValueKey('santa-draw')));
        await _tap(tester, find.byKey(const ValueKey('santa-draw-confirm')));
        expect(find.text(message), findsWidgets);
      });
    }

    testWidgets('after the draw: my assignee + their wish note + Shop for them (budget bands)', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db, status: 'drawn');
      await seedAssignment(db, 'u1', 'u2', note: 'Books and dark chocolate');
      await seedAssignment(db, 'u2', 'u3', note: 'Not for Sara to see');
      final h = await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db);

      expect(find.text(_en.secretSantaBuyingFor('Karwan')), findsOneWidget);
      expect(find.text('Books and dark chocolate'), findsOneWidget);
      // Never anyone else's assignment.
      expect(find.text(_en.secretSantaBuyingFor('Lana')), findsNothing);
      expect(find.text('Not for Sara to see'), findsNothing);
      // Drawn: no invite / draw any more.
      expect(find.byKey(const ValueKey('santa-invite-code')), findsNothing);
      expect(find.byKey(const ValueKey('santa-draw')), findsNothing);

      await _tap(tester, find.byKey(const ValueKey('santa-shop-for-them')));
      expect(h.location, AppRoutes.productsFor(const ProductQuery(priceBands: {0, 1})));
      expect(find.text('products price=0,1'), findsOneWidget);
    });

    testWidgets('drawn but my assignment not there yet → "your match will appear"', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db, status: 'drawn');
      await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db);
      expect(find.byKey(const ValueKey('santa-draw-pending')), findsOneWidget);
    });

    testWidgets('my wish note: add, save, shown', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db);
      await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db);
      expect(find.text(_en.secretSantaWishNoteEmpty), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('santa-edit-note')));
      await tester.enterText(_field('santa-note-input'), '  A scarf, size M  ');
      await _tap(tester, find.byKey(const ValueKey('santa-note-save')));
      expect((await db.doc('secret_santa_groups/g1/members/u1').get()).data()!['wishlistNote'], 'A scarf, size M');
      expect(find.text(_en.secretSantaWishNoteSaved), findsOneWidget);
      expect(find.text('A scarf, size M'), findsOneWidget);
    });

    testWidgets('not a member → not available', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db, members: const ['u2', 'u3', 'u4'], organiser: 'u2');
      await pumpPhase9(tester, initialPath: AppRoutes.secretSantaGroupFor('g1'), firestore: db);
      expect(find.byKey(const ValueKey('santa-not-member')), findsOneWidget);
      expect(find.byKey(const ValueKey('santa-invite-code')), findsNothing);
    });
  });

  group('join (/s/:code)', () {
    testWidgets('name prefilled + optional wish note → joinSecretSanta → group page', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedGroup(db, organiser: 'u2', members: const ['u2', 'u3', 'u1']);
      final fns = FakeCallables()..handlers['joinSecretSanta'] = (_) => {'groupId': 'g1'};
      final h = await pumpPhase9(tester, initialPath: '/s/abcd2345', firestore: db, callables: fns);
      expect(tester.widget<TextField>(_field('santa-join-name')).controller!.text, 'Sara Ahmed');
      await tester.enterText(_field('santa-join-note'), 'Books please');
      await _tap(tester, find.byKey(const ValueKey('santa-join-group')));
      expect(fns.callsTo('joinSecretSanta').single, {
        'inviteCode': 'ABCD2345',
        'name': 'Sara Ahmed',
        'wishlistNote': 'Books please',
      });
      expect(h.location, AppRoutes.secretSantaGroupFor('g1'));
      expect(find.text(_en.secretSantaJoined), findsOneWidget);
      expect(find.byKey(const ValueKey('santa-waiting')), findsOneWidget);
    });

    testWidgets('the name is required', (tester) async {
      final fns = FakeCallables()..handlers['joinSecretSanta'] = (_) => {'groupId': 'g1'};
      await pumpPhase9(tester, initialPath: '/s/ABCD2345', callables: fns, profile: testProfile(name: ''));
      await _tap(tester, find.byKey(const ValueKey('santa-join-group')));
      expect(find.text(_en.errorRequired), findsOneWidget);
      expect(fns.calls, isEmpty);
    });

    testWidgets('guests are asked to sign in first', (tester) async {
      final fns = FakeCallables()..handlers['joinSecretSanta'] = (_) => {'groupId': 'g1'};
      await pumpPhase9(tester, initialPath: '/s/ABCD2345', guest: true, callables: fns);
      await tester.enterText(_field('santa-join-name'), 'Lana');
      await _tap(tester, find.byKey(const ValueKey('santa-join-group')));
      expect(find.text(_en.signInToContinue), findsOneWidget);
      expect(fns.calls, isEmpty);
    });

    testWidgets('a malformed link shows "enter the 8-character code"', (tester) async {
      await pumpPhase9(tester, initialPath: '/s/xyz');
      expect(find.byKey(const ValueKey('santa-join-invalid')), findsOneWidget);
    });

    for (final (error, message) in [
      (FirebaseFunctionsException(code: 'not-found', message: 'No group with that code'), _en.secretSantaErrorNotFound),
      (
        FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'full'}),
        _en.secretSantaErrorFull
      ),
      (
        FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'drawn'}),
        _en.secretSantaErrorAlreadyDrawn
      ),
      (FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND'), _en.secretSantaErrorUnavailable),
    ]) {
      testWidgets('join failure ${error.code} ${error.message} → "$message"', (tester) async {
        final fns = FakeCallables()..handlers['joinSecretSanta'] = (_) => throw error;
        final h = await pumpPhase9(tester, initialPath: '/s/ABCD2345', callables: fns);
        await _tap(tester, find.byKey(const ValueKey('santa-join-group')));
        expect(find.text(message), findsOneWidget);
        expect(h.location, '/s/ABCD2345');
      });
    }
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.light), ('ar', ThemeMode.dark), ('ckb', ThemeMode.dark)]) {
      testWidgets('list, group (open + drawn), join and create in $locale ${mode.name}', (tester) async {
        final l10n = l10nFor(locale);
        final db = FakeFirebaseFirestore();
        await seedGroup(db);
        await seedGroup(db, id: 'g2', status: 'drawn', organiser: 'u2');
        await seedAssignment(db, 'u1', 'u3', note: 'Perfume', group: 'g2');
        final h = await pumpPhase9(tester, initialPath: AppRoutes.secretSanta, firestore: db, locale: locale, themeMode: mode);
        expect(find.text(l10n.secretSanta), findsOneWidget);
        expect(Directionality.of(tester.element(find.byKey(const ValueKey('santa-group-g1')))), TextDirection.rtl);
        await _tap(tester, find.byKey(const ValueKey('santa-create-open')));
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
        await tester.pumpAndSettle();
        h.router.go(AppRoutes.secretSantaGroupFor('g1'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('santa-invite-code')), findsOneWidget);
        h.router.go(AppRoutes.secretSantaGroupFor('g2'));
        await tester.pumpAndSettle();
        expect(find.text(l10n.secretSantaBuyingFor('Lana')), findsOneWidget);
        h.router.go(AppRoutes.secretSantaJoin('ABCD2345'));
        await tester.pumpAndSettle();
        expect(find.text(l10n.secretSantaJoinTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final locale in ['en', 'ar', 'ckb']) {
      testWidgets('320 px, 1.3× text ($locale)', (tester) async {
        final db = FakeFirebaseFirestore();
        await seedGroup(db, name: 'A rather long Secret Santa group name for the office');
        await seedGroup(db, id: 'g2', status: 'drawn', organiser: 'u2');
        await seedAssignment(db, 'u1', 'u3', note: 'Perfume', group: 'g2');
        final h = await pumpPhase9(
          tester,
          initialPath: AppRoutes.secretSanta,
          firestore: db,
          locale: locale,
          size: const Size(320, 2400),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.byKey(const ValueKey('santa-create-open')));
        await _tap(tester, find.byKey(const ValueKey('santa-create')));
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        for (final path in [
          AppRoutes.secretSantaGroupFor('g1'),
          AppRoutes.secretSantaGroupFor('g2'),
          AppRoutes.secretSantaJoin('ABCD2345'),
        ]) {
          h.router.go(path);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: path);
        }
      });
    }
  });
}
