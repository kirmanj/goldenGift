import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../gift_cards/phase8_test_harness.dart';

final _en = l10nFor('en');

/// Contact Us in-app form (SRS §5.24) — the channel cards are covered by
/// contact_us_screen_test.dart.
void main() {
  testWidgets('a message becomes a support request; "View your messages" opens Special Requests', (tester) async {
    final h = await pumpPhase8(tester, initialPath: '/contact-us');
    expect(find.byKey(const ValueKey('support-form')), findsOneWidget);
    await enterIn(tester, 'support-message', '  My order GG-2610-00001 is late  ');
    await tapKey(tester, 'support-send');

    final docs = (await h.firestore.collection('special_requests').get()).docs;
    expect(docs, hasLength(1));
    final doc = docs.single.data();
    expect(doc['type'], 'support');
    expect(doc['userId'], 'u1');
    expect(doc['text'], 'My order GG-2610-00001 is late');
    expect(doc['images'], isEmpty);
    expect(doc['customerName'], 'Sara Ahmed');
    expect(h.uploads.folders, isEmpty);
    expect(find.byKey(const ValueKey('support-sent')), findsOneWidget);
    expect(find.text(_en.supportMessageSent), findsOneWidget);

    await tapKey(tester, 'support-view-messages');
    expect(h.location, '/special-requests');
    expect(find.byKey(const ValueKey('sr-type-support')), findsOneWidget);
  });

  testWidgets('"Send another" brings the empty form back', (tester) async {
    await pumpPhase8(tester, initialPath: '/contact-us');
    await enterIn(tester, 'support-message', 'Hello');
    await tapKey(tester, 'support-send');
    await tapKey(tester, 'support-send-another');
    expect(find.byKey(const ValueKey('support-message')), findsOneWidget);
    expect(find.text('0/1000'), findsOneWidget);
  });

  testWidgets('empty message → required', (tester) async {
    final h = await pumpPhase8(tester, initialPath: '/contact-us');
    await tapKey(tester, 'support-send');
    expect(find.text(_en.errorRequired), findsOneWidget);
    expect((await h.firestore.collection('special_requests').get()).docs, isEmpty);
  });

  testWidgets('guests must sign in to send', (tester) async {
    final h = await pumpPhase8(tester, initialPath: '/contact-us', guest: true);
    expect(find.byKey(const ValueKey('support-view-messages')), findsNothing);
    await enterIn(tester, 'support-message', 'Hello');
    await tapKey(tester, 'support-send');
    expect(find.text(_en.signInToContinue), findsOneWidget);
    expect((await h.firestore.collection('special_requests').get()).docs, isEmpty);
  });

  testWidgets('sent state at 320 px with 1.3× text in Kurdish dark', (tester) async {
    await pumpPhase8(tester,
        initialPath: '/contact-us',
        locale: 'ckb',
        themeMode: ThemeMode.dark,
        size: const Size(320, 1400),
        textScale: 1.3);
    await enterIn(tester, 'support-message', 'سڵاو');
    await tapKey(tester, 'support-send');
    expect(find.byKey(const ValueKey('support-sent')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
