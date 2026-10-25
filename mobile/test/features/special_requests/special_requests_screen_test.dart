import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/services/analytics_service.dart';

import '../gift_cards/phase8_test_harness.dart';

final _en = l10nFor('en');
const _path = '/special-requests';

void main() {
  testWidgets('IMG_4492 layout: title, subtitle, photo tile, idea field, gold submit', (tester) async {
    await pumpPhase8(tester, initialPath: _path);
    expect(find.text(_en.specialRequests), findsNWidgets(2)); // app bar + heading
    expect(find.text(_en.srSubtitle), findsOneWidget);
    expect(find.byKey(const ValueKey('sr-photos-add')), findsOneWidget);
    expect(find.text(_en.writeYourIdeaHere), findsOneWidget);
    expect(find.text(_en.submitYourRequest), findsOneWidget);
    expect(find.text('0/1000'), findsOneWidget);
    expect(find.byKey(const ValueKey('sr-my-requests')), findsNothing);
  });

  testWidgets('the idea is required', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path);
    await enterIn(tester, 'sr-text', '   ');
    await tapKey(tester, 'sr-submit');
    expect(find.text(_en.srTextRequired), findsOneWidget);
    expect((await h.firestore.collection('special_requests').get()).docs, isEmpty);
  });

  testWidgets('up to 5 photos, removable', (tester) async {
    await pumpPhase8(tester, initialPath: _path);
    for (var i = 0; i < 5; i++) {
      await addPhoto(tester, 'sr-photos-add', _en);
    }
    expect(find.byKey(const ValueKey('sr-photos-add')), findsNothing);
    expect(find.byKey(const ValueKey('sr-photos-remove-4')), findsOneWidget);
    await tapKey(tester, 'sr-photos-remove-2');
    expect(find.byKey(const ValueKey('sr-photos-remove-4')), findsNothing);
    expect(find.byKey(const ValueKey('sr-photos-add')), findsOneWidget);
  });

  testWidgets('submit uploads the photos, writes the request with the profile snapshot, logs analytics', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path);
    await addPhoto(tester, 'sr-photos-add', _en);
    await addPhoto(tester, 'sr-photos-add', _en);
    await enterIn(tester, 'sr-text', '  A wooden box with our names\nand a photo inside  ');
    await tapKey(tester, 'sr-submit');

    final docs = (await h.firestore.collection('special_requests').get()).docs;
    expect(docs, hasLength(1));
    final doc = docs.single.data();
    expect(doc['userId'], 'u1');
    expect(doc['type'], 'gift');
    expect(doc['status'], SpecialRequestStatus.submitted.name);
    expect(doc['text'], 'A wooden box with our names\nand a photo inside');
    expect(doc['customerName'], 'Sara Ahmed');
    expect(doc['customerPhone'], '+9647501234567');
    expect(doc['images'], hasLength(2));
    expect(h.uploads.folders.single, 'special_requests/u1/${docs.single.id}');
    expect(h.analytics.events[AnalyticsEvents.specialRequestSubmit], {'type': 'gift', 'images': 2});

    expect(find.text(_en.srSubmitted), findsOneWidget);
    expect(find.byKey(const ValueKey('sr-photos-remove-0')), findsNothing);
    expect(find.text('0/1000'), findsOneWidget);
    // It now shows in "My requests".
    expect(find.byKey(const ValueKey('sr-my-requests')), findsOneWidget);
    expect(find.byKey(ValueKey('sr-tile-${docs.single.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('sr-status-submitted')), findsOneWidget);
  });

  testWidgets('guests must sign in to submit', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, guest: true);
    await enterIn(tester, 'sr-text', 'An idea');
    await tapKey(tester, 'sr-submit');
    expect(find.text(_en.signInToContinue), findsOneWidget);
    expect((await h.firestore.collection('special_requests').get()).docs, isEmpty);
  });

  testWidgets('my requests: a chip per status, Support chip, unread dot only on open requests', (tester) async {
    final db = FakeFirebaseFirestore();
    const statuses = SpecialRequestStatus.values;
    for (var i = 0; i < statuses.length; i++) {
      await seedRequest(db, 'r-${statuses[i].name}',
          status: statuses[i].name,
          text: 'Idea ${statuses[i].name}',
          lastMessageBy: 'admin',
          createdAt: DateTime(2026, 10, 1 + i));
    }
    await seedRequest(db, 'help', type: 'support', text: 'Where is my order?\nIt is late', createdAt: DateTime(2026, 10, 15));
    await seedRequest(db, 'other', userId: 'u2', text: 'Not mine');
    final h = await pumpPhase8(tester, initialPath: _path, firestore: db);

    for (final s in statuses) {
      expect(find.byKey(ValueKey('sr-tile-r-${s.name}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('sr-status-submitted')), findsNWidgets(2));
    for (final s in statuses.where((s) => s != SpecialRequestStatus.submitted)) {
      expect(find.byKey(ValueKey('sr-status-${s.name}')), findsOneWidget);
    }
    expect(find.text(_en.srStatusInReview), findsOneWidget);
    expect(find.byKey(const ValueKey('sr-type-support')), findsOneWidget);
    expect(find.text('Where is my order?'), findsOneWidget); // first line only
    expect(find.text('Not mine'), findsNothing);
    expect(find.byKey(const ValueKey('sr-unread-r-inReview')), findsOneWidget);
    expect(find.byKey(const ValueKey('sr-unread-r-quoted')), findsOneWidget);
    expect(find.byKey(const ValueKey('sr-unread-r-rejected')), findsNothing);
    expect(find.byKey(const ValueKey('sr-unread-r-completed')), findsNothing);
    expect(find.byKey(const ValueKey('sr-unread-help')), findsNothing);
    expect(find.text('15/10/2026'), findsOneWidget);

    await tapKey(tester, 'sr-tile-r-quoted');
    expect(h.location, '/special-requests/r-quoted');
  });

  group('renders without exceptions', () {
    Future<FakeFirebaseFirestore> db() async {
      final db = FakeFirebaseFirestore();
      await seedRequest(db, 'a', status: 'inReview', lastMessageBy: 'admin');
      await seedRequest(db, 'b', type: 'support', status: 'completed');
      return db;
    }

    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await pumpPhase8(tester, initialPath: _path, firestore: await db(), locale: locale, themeMode: mode);
        await addPhoto(tester, 'sr-photos-add', l10nFor(locale));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320 px, 1.3× text', (tester) async {
      await pumpPhase8(tester,
          initialPath: _path, firestore: await db(), locale: 'ckb', size: const Size(320, 2400), textScale: 1.3);
      await tapKey(tester, 'sr-submit');
      expect(tester.takeException(), isNull);
    });
  });
}
