import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';

import '../gift_cards/phase8_test_harness.dart';

final _en = l10nFor('en');

Future<void> _message(FakeFirebaseFirestore db, String requestId, String id, String role, String text, DateTime at) =>
    db.doc('special_requests/$requestId/messages/$id').set({
      'senderUid': role == 'admin' ? 'admin1' : 'u1',
      'role': role,
      'text': text,
      'images': const <String>[],
      'at': Timestamp.fromDate(at),
    });

Future<FakeFirebaseFirestore> _quoted({int balance = 0}) async {
  final db = FakeFirebaseFirestore();
  await seedRequest(db, 'r1',
      status: 'quoted',
      quoteAmount: 90000,
      quoteNote: 'Walnut wood, 2 names, ready in 3 days',
      lastMessageBy: 'admin',
      // Empty URLs render the offline fallback tile (no network in widget tests).
      images: ['', '']);
  await _message(db, 'r1', 'm1', 'admin', 'Hi Sara! We can make this.', DateTime(2026, 10, 20, 13));
  await _message(db, 'r1', 'm2', 'customer', 'Great, how much?', DateTime(2026, 10, 20, 14));
  await seedAddress(db, testAddress('a1', isDefault: true));
  await seedAddress(db, testAddress('a2', label: 'Work', city: 'duhok'));
  await seedWallet(db, balance: balance);
  return db;
}

void main() {
  group('details', () {
    testWidgets('request, status steps, quote and the thread (Golden Gift on the start side)', (tester) async {
      await pumpPhase8(tester, initialPath: '/special-requests/r1', firestore: await _quoted());
      expect(find.byKey(const ValueKey('sr-text-full')), findsOneWidget);
      expect(find.byKey(const ValueKey('sr-steps')), findsOneWidget);
      expect(find.byKey(const ValueKey('sr-quote')), findsOneWidget);
      expect(find.text('90,000 IQD'), findsOneWidget);
      expect(find.text('Walnut wood, 2 names, ready in 3 days'), findsOneWidget);
      expect(find.byKey(const ValueKey('accept-quote')), findsOneWidget);

      final admin = tester.getCenter(find.text('Hi Sara! We can make this.'));
      final me = tester.getCenter(find.text('Great, how much?'));
      expect(admin.dx, lessThan(me.dx)); // LTR: start = left
      expect(find.text(_en.appTitle), findsOneWidget);
      expect(find.text(_en.srYou), findsOneWidget);
      expect(find.byKey(const ValueKey('sr-reply')), findsOneWidget);
    });

    testWidgets('in Arabic the admin bubble sits on the right (start)', (tester) async {
      await pumpPhase8(tester, initialPath: '/special-requests/r1', firestore: await _quoted(), locale: 'ar');
      final admin = tester.getCenter(find.text('Hi Sara! We can make this.'));
      final me = tester.getCenter(find.text('Great, how much?'));
      expect(admin.dx, greaterThan(me.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a reply lands in the thread and clears the box', (tester) async {
      final h = await pumpPhase8(tester, initialPath: '/special-requests/r1', firestore: await _quoted());
      await enterIn(tester, 'sr-reply', '  Can it be ready by Friday?  ');
      await tester.tap(find.byKey(const ValueKey('sr-send')));
      await tester.pumpAndSettle();
      final messages = await h.firestore.collection('special_requests/r1/messages').get();
      expect(messages.docs.map((d) => d['text']), contains('Can it be ready by Friday?'));
      expect((await h.firestore.doc('special_requests/r1').get())['lastMessageBy'], 'customer');
      expect(find.text('Can it be ready by Friday?'), findsOneWidget);
      final field = tester.widget<TextField>(
          find.descendant(of: find.byKey(const ValueKey('sr-reply')), matching: find.byType(TextField)));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('photos open full screen', (tester) async {
      await pumpPhase8(tester, initialPath: '/special-requests/r1', firestore: await _quoted());
      await tapKey(tester, 'sr-image-1');
      expect(find.byKey(const ValueKey('image-viewer')), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('image-viewer-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('image-viewer')), findsNothing);
    });

    testWidgets('accepted request → View order; rejected → note and no reply box', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedRequest(db, 'done', status: 'accepted', quoteAmount: 90000, orderId: 'o9');
      await seedRequest(db, 'no', status: 'rejected');
      final h = await pumpPhase8(tester, initialPath: '/special-requests/done', firestore: db);
      expect(find.byKey(const ValueKey('accept-quote')), findsNothing);
      await tapKey(tester, 'sr-view-order');
      expect(h.location, '/orders/o9');

      h.router.go('/special-requests/no');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sr-rejected-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('sr-closed')), findsOneWidget);
      expect(find.byKey(const ValueKey('sr-reply')), findsNothing);
      expect(find.text(_en.srNoMessages), findsOneWidget);
    });

    testWidgets('support requests show the Support chip and no quote steps', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedRequest(db, 's1', type: 'support', text: 'Where is my order?');
      await pumpPhase8(tester, initialPath: '/special-requests/s1', firestore: db);
      expect(find.byKey(const ValueKey('sr-type-support')), findsOneWidget);
      expect(find.byKey(const ValueKey('sr-steps')), findsNothing);
    });

    testWidgets('unknown request / guests', (tester) async {
      await pumpPhase8(tester, initialPath: '/special-requests/nope');
      expect(find.byKey(const ValueKey('sr-not-found')), findsOneWidget);
    });

    testWidgets('guests see the sign-in card', (tester) async {
      await pumpPhase8(tester, initialPath: '/special-requests/r1', guest: true);
      expect(find.byKey(const ValueKey('guest-sign-in-card')), findsOneWidget);
    });
  });

  group('accept quote', () {
    testWidgets('sends the chosen address, date, slot and payment → Order Success', (tester) async {
      final h = await pumpPhase8(tester, initialPath: '/special-requests/r1', firestore: await _quoted());
      await tapKey(tester, 'accept-quote');
      expect(h.location, '/special-requests/r1/accept');
      // Default address (Erbil, fee 5,000) → 95,000 total.
      expect(find.byKey(const ValueKey('quote-address-a1')), findsOneWidget);
      expect(find.text('95,000 IQD'), findsWidgets);

      // Change to the Duhok address (fee 4,000) through Saved Addresses.
      await tapKey(tester, 'change-address');
      await tester.tap(find.byKey(const ValueKey('address-a2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quote-address-a2')), findsOneWidget);
      expect(find.text('94,000 IQD'), findsWidgets);

      await tapKey(tester, 'date-2026-10-23');
      await tapKey(tester, 'slot-evening');
      await tapKey(tester, 'confirm-quote');

      final sent = h.callable.callsTo('acceptQuote').single;
      expect(sent['requestId'], 'r1');
      expect(sent['addressId'], 'a2');
      expect(sent['deliveryDate'], '2026-10-23');
      expect(sent['deliverySlot'], 'evening');
      expect(sent['paymentMethod'], PaymentMethod.cashOnDelivery.name);
      expect(sent['clientRequestId'], isNotEmpty);
      expect(h.location, '/order-success/o2');
    });

    testWidgets('wallet only when the balance covers quote + delivery; retries reuse one id', (tester) async {
      final callable = FakeCallable()
        ..script('acceptQuote', [
          FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'city_not_allowed'}),
          FirebaseFunctionsException(code: 'unavailable', message: ''),
        ]);
      final h = await pumpPhase8(tester,
          initialPath: '/special-requests/r1/accept', firestore: await _quoted(balance: 94999), callable: callable);
      RadioListTile<PaymentMethod> wallet() =>
          tester.widget<RadioListTile<PaymentMethod>>(find.byKey(const ValueKey('payment-wallet')));
      expect(wallet().enabled, isFalse);
      expect(find.byKey(const ValueKey('quote-wallet-short')), findsOneWidget);

      await h.firestore.doc('wallets/u1').set({'balance': 95000, 'credits': 0});
      await tester.pumpAndSettle();
      expect(wallet().enabled, isTrue);
      await tapKey(tester, 'payment-wallet');

      await tapKey(tester, 'confirm-quote');
      expect(find.text(_en.orderFailedCity), findsOneWidget);
      await tapKey(tester, 'confirm-quote');
      expect(find.text(_en.orderFailedUnavailable), findsOneWidget);
      await tapKey(tester, 'confirm-quote');

      final calls = h.callable.callsTo('acceptQuote');
      expect(calls, hasLength(3));
      expect(calls.map((c) => c['clientRequestId']).toSet(), hasLength(1));
      expect(calls.last['paymentMethod'], PaymentMethod.wallet.name);
      expect(h.location, '/order-success/o2');
    });

    testWidgets('an unserved city blocks confirming', (tester) async {
      final db = await _quoted();
      await seedAddress(db, testAddress('a1', city: 'baghdad', isDefault: true));
      final h = await pumpPhase8(tester, initialPath: '/special-requests/r1/accept', firestore: db);
      expect(find.byKey(const ValueKey('quote-city-error')), findsOneWidget);
      expect(primaryButton(tester, const ValueKey('confirm-quote')).onPressed, isNull);
      expect(h.callable.calls, isEmpty);
    });

    testWidgets('a quote that can no longer be accepted', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedRequest(db, 'r1', status: 'accepted', quoteAmount: 90000, orderId: 'o9');
      final h = await pumpPhase8(tester, initialPath: '/special-requests/r1/accept', firestore: db);
      expect(find.byKey(const ValueKey('quote-not-acceptable')), findsOneWidget);
      await tester.tap(find.text(_en.srBackToRequest));
      await tester.pumpAndSettle();
      expect(h.location, '/special-requests/r1');
    });
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('details + accept, $locale ${mode.name}', (tester) async {
        final h = await pumpPhase8(tester,
            initialPath: '/special-requests/r1', firestore: await _quoted(), locale: locale, themeMode: mode);
        expect(tester.takeException(), isNull);
        h.router.go('/special-requests/r1/accept');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320 px, 1.3× text', (tester) async {
      final h = await pumpPhase8(tester,
          initialPath: '/special-requests/r1',
          firestore: await _quoted(),
          locale: 'ckb',
          size: const Size(320, 1600),
          textScale: 1.3);
      expect(tester.takeException(), isNull);
      h.router.go('/special-requests/r1/accept');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
