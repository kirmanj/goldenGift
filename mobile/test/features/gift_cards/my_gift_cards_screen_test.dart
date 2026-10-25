import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/features/gift_cards/data/gift_cards_repository.dart';
import 'package:golden_gift/features/gift_cards/presentation/widgets/gift_card_labels.dart';

import 'phase8_test_harness.dart';

final _en = l10nFor('en');

Future<FakeFirebaseFirestore> _db() async {
  final db = FakeFirebaseFirestore();
  Future<void> card(String id, Map<String, dynamic> data) => db.doc('gift_cards/$id').set({
        'templateId': 'a',
        'templateName': 'Golden Classic',
        'amount': 25000,
        'balance': 25000,
        'purchaserUid': 'someone',
        'recipientName': 'Sara',
        ...data,
      });
  await card('g1', {
    'code': 'ABCDEFGHJKLM',
    'recipientUid': 'u1',
    'status': 'sent',
    'message': 'Happy birthday!',
    'sentAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
    'expiresAt': Timestamp.fromDate(DateTime(2027, 10, 1)),
  });
  await card('g2', {
    'code': 'ZZZZYYYYXXXX',
    'recipientUid': 'u1',
    'status': 'redeemed',
    'balance': 0,
    'sentAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
  });
  await card('g3', {
    'code': 'QQQQWWWWEEEE',
    'purchaserUid': 'u1',
    'recipientName': 'Omar',
    'status': 'pending',
    'amount': 50000,
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 11, 1, 9)),
  });
  return db;
}

void main() {
  testWidgets('Received: code, balance, expiry, status; Redeem only on redeemable cards', (tester) async {
    await pumpPhase8(tester, initialPath: '/gift-cards', firestore: await _db());
    expect(find.byKey(const ValueKey('gift-card-g1')), findsOneWidget);
    expect(find.byKey(const ValueKey('gift-card-g2')), findsOneWidget);
    expect(find.byKey(const ValueKey('gift-card-g3')), findsNothing);
    expect(find.text('ABCD-EFGH-JKLM'), findsOneWidget);
    expect(find.text(_en.giftCardBalance('25,000 IQD')), findsOneWidget);
    expect(find.text(_en.expiresOn('01/10/2027')), findsOneWidget);
    expect(find.text(_en.giftCardStatusActive), findsOneWidget);
    expect(find.text(_en.giftCardStatusRedeemed), findsOneWidget);
    expect(find.byKey(const ValueKey('redeem-g1')), findsOneWidget);
    expect(find.byKey(const ValueKey('redeem-g2')), findsNothing);

    await tapKey(tester, 'copy-code-g1');
    expect(find.text(_en.codeCopied), findsOneWidget);
  });

  testWidgets('Sent: recipient and send date, no code', (tester) async {
    await pumpPhase8(tester, initialPath: '/gift-cards', firestore: await _db());
    await tapKey(tester, 'tab-sent');
    expect(find.byKey(const ValueKey('gift-card-g3')), findsOneWidget);
    expect(find.byKey(const ValueKey('gift-card-g1')), findsNothing);
    expect(find.text(_en.giftCardTo('Omar')), findsOneWidget);
    expect(find.text(_en.giftCardScheduledFor('01/11/2026')), findsOneWidget);
    expect(find.text(_en.giftCardStatusScheduled), findsOneWidget);
    expect(find.text('QQQQ-WWWW-EEEE'), findsNothing);
  });

  testWidgets('empty tabs; the shop is one tap away', (tester) async {
    final h = await pumpPhase8(tester, initialPath: '/gift-cards');
    expect(find.byKey(const ValueKey('received-empty')), findsOneWidget);
    await tapKey(tester, 'tab-sent');
    expect(find.byKey(const ValueKey('sent-empty')), findsOneWidget);
    await tester.tap(find.text(_en.giftCardDesignCta));
    await tester.pumpAndSettle();
    expect(h.location, '/gift-cards/shop');
  });

  testWidgets('Redeem on a card → credits sheet → My Wallet', (tester) async {
    final h = await pumpPhase8(tester, initialPath: '/gift-cards', firestore: await _db());
    await tapKey(tester, 'redeem-g1');
    expect(h.callable.callsTo('redeemGiftCard').single, {'code': 'ABCDEFGHJKLM'});
    expect(find.byKey(const ValueKey('redeemed-sheet')), findsOneWidget);
    expect(find.text(_en.giftCardRedeemedBody('25,000 IQD')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('redeemed-view-wallet')));
    await tester.pumpAndSettle();
    expect(h.location, '/wallet');
  });

  testWidgets('"Have a code?" normalizes the code and checks its length first', (tester) async {
    final h = await pumpPhase8(tester, initialPath: '/gift-cards');
    await tapKey(tester, 'redeem-code-button');
    expect(find.text(_en.errorRequired), findsOneWidget);
    await enterIn(tester, 'redeem-code', 'abc');
    await tapKey(tester, 'redeem-code-button');
    expect(find.text(_en.giftCardCodeInvalid), findsOneWidget);
    expect(h.callable.calls, isEmpty);

    await enterIn(tester, 'redeem-code', 'abcd-efgh jklm');
    await tapKey(tester, 'redeem-code-button');
    expect(h.callable.callsTo('redeemGiftCard').single['code'], 'ABCDEFGHJKLM');
    expect(find.byKey(const ValueKey('redeemed-sheet')), findsOneWidget);
  });

  testWidgets('every redeem failure has its own message', (tester) async {
    final cases = <(FirebaseFunctionsException, String)>[
      (FirebaseFunctionsException(code: 'not-found', message: ''), _en.redeemNotFound),
      (FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'expired'}), _en.redeemExpired),
      (FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'redeemed'}),
          _en.redeemAlreadyRedeemed),
      (FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'disabled'}),
          _en.redeemDisabled),
      (FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'not_sent'}),
          _en.redeemNotYetSent),
      (FirebaseFunctionsException(code: 'resource-exhausted', message: ''), _en.redeemTooManyAttempts),
      (FirebaseFunctionsException(code: 'unavailable', message: ''), _en.redeemUnavailable),
      (FirebaseFunctionsException(code: 'deadline-exceeded', message: ''), _en.authErrorNetwork),
      (FirebaseFunctionsException(code: 'permission-denied', message: ''), _en.somethingWentWrong),
    ];
    final callable = FakeCallable()..script('redeemGiftCard', [for (final c in cases) c.$1]);
    await pumpPhase8(tester, initialPath: '/gift-cards', callable: callable);
    for (final (_, message) in cases) {
      await enterIn(tester, 'redeem-code', 'ABCD-EFGH-JKLM');
      await tapKey(tester, 'redeem-code-button');
      expect(find.text(message), findsOneWidget, reason: message);
    }
    expect(find.byKey(const ValueKey('redeemed-sheet')), findsNothing);
  });

  test('every failure reason maps to a message', () {
    for (final reason in RedeemFailureReason.values) {
      expect(redeemFailureMessage(_en, reason), isNotEmpty);
    }
  });

  testWidgets('a failed tile redeem shows a snack bar', (tester) async {
    final callable = FakeCallable()
      ..script('redeemGiftCard', [
        FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'expired'}),
      ]);
    await pumpPhase8(tester, initialPath: '/gift-cards', firestore: await _db(), callable: callable);
    await tapKey(tester, 'redeem-g1');
    expect(find.text(_en.redeemExpired), findsOneWidget);
  });

  testWidgets('guests see the sign-in card', (tester) async {
    await pumpPhase8(tester, initialPath: '/gift-cards', guest: true);
    expect(find.byKey(const ValueKey('guest-sign-in-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('redeem-code')), findsNothing);
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await pumpPhase8(tester, initialPath: '/gift-cards', firestore: await _db(), locale: locale, themeMode: mode);
        await tapKey(tester, 'tab-sent');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320 px, 1.3× text', (tester) async {
      await pumpPhase8(tester,
          initialPath: '/gift-cards', firestore: await _db(), locale: 'ckb', size: const Size(320, 2400), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'redeem-g1');
      expect(tester.takeException(), isNull);
    });
  });
}
