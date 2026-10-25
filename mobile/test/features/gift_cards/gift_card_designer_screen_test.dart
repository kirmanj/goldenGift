import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/gift_cards/presentation/screens/gift_card_designer_screen.dart';

import 'phase8_test_harness.dart';

final _en = l10nFor('en');
const _path = '/gift-cards/design/a';

Future<FakeFirebaseFirestore> _db({bool address = true, int balance = 0}) async {
  final db = FakeFirebaseFirestore();
  await seedTemplate(db, 'a');
  await seedTemplate(db, 'b', name: 'Birthday', presets: [50000], min: 0, max: 0, sortOrder: 1);
  if (address) await seedAddress(db, testAddress('a1', isDefault: true));
  await seedWallet(db, balance: balance, credits: 90000);
  return db;
}

Future<void> _fillRecipient(WidgetTester tester, {String name = 'Omar', String phone = '0750 111 2233'}) async {
  await enterIn(tester, 'recipient-name', name);
  await enterIn(tester, 'recipient-phone', phone);
}

Future<void> _buy(WidgetTester tester) => tapKey(tester, 'designer-buy');

void main() {
  group('rules', () {
    test('schedule: from tomorrow up to one year ahead', () {
      final now = DateTime(2026, 10, 21, 22, 30);
      expect(GiftCardSchedule.firstDate(now), DateTime(2026, 10, 22));
      expect(GiftCardSchedule.lastDate(now), DateTime(2027, 10, 21));
      expect(GiftCardSchedule.allows(DateTime(2026, 10, 21), now), isFalse);
      expect(GiftCardSchedule.allows(DateTime(2026, 10, 22), now), isTrue);
      expect(GiftCardSchedule.allows(DateTime(2027, 10, 21, 23), now), isTrue);
      expect(GiftCardSchedule.allows(DateTime(2027, 10, 22), now), isFalse);
      expect(GiftCardSchedule.sendAt(DateTime(2026, 11, 1)), DateTime(2026, 11, 1, 9));
    });

    test('amount input', () {
      expect(parseAmountInput('25000'), 25000);
      expect(parseAmountInput('٢٥٠٠٠'), 25000);
      expect(parseAmountInput(''), isNull);
      expect(parseAmountInput('1234567890'), -1);
    });
  });

  testWidgets('presets: the first is selected and the preview follows the choices', (tester) async {
    await pumpPhase8(tester, initialPath: _path, firestore: await _db());
    final preview = find.byKey(const ValueKey('designer-preview'));
    expect(find.descendant(of: preview, matching: find.text('15,000 IQD')), findsOneWidget);

    await tapKey(tester, 'amount-chip-100000');
    expect(find.descendant(of: preview, matching: find.text('100,000 IQD')), findsOneWidget);

    await enterIn(tester, 'recipient-name', 'Omar');
    await enterIn(tester, 'designer-message', 'Happy birthday!');
    expect(find.descendant(of: preview, matching: find.text(_en.giftCardTo('Omar'))), findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('Happy birthday!')), findsOneWidget);

    // Another design keeps a still-valid amount, otherwise picks its first preset.
    await tapKey(tester, 'template-swatch-b');
    expect(find.descendant(of: preview, matching: find.text('50,000 IQD')), findsOneWidget);
    expect(find.byKey(const ValueKey('amount-chip-custom')), findsNothing);
  });

  testWidgets('custom amount must be within the template bounds', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db());
    await _fillRecipient(tester);
    await tapKey(tester, 'amount-chip-custom');

    await _buy(tester);
    expect(find.text(_en.giftCardAmountRequired), findsOneWidget);

    final range = _en.giftCardAmountRange('10,000 IQD', '500,000 IQD');
    await enterIn(tester, 'custom-amount', '5000');
    await _buy(tester);
    expect(find.text(range), findsOneWidget);

    await enterIn(tester, 'custom-amount', '600000');
    await _buy(tester);
    expect(find.text(range), findsOneWidget);
    expect(h.callable.calls, isEmpty);

    await enterIn(tester, 'custom-amount', '12345');
    expect(find.descendant(of: find.byKey(const ValueKey('designer-preview')), matching: find.text('12,345 IQD')),
        findsOneWidget);
    await _buy(tester);
    expect(h.callable.callsTo('purchaseGiftCard').single['amount'], 12345);
  });

  testWidgets('recipient: name required, phone or email, both validated', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db());
    await _buy(tester);
    expect(find.text(_en.errorRequired), findsOneWidget); // name
    expect(find.text(_en.giftCardContactRequired), findsOneWidget);
    expect(find.text(_en.giftCardFixErrors), findsOneWidget);

    await enterIn(tester, 'recipient-name', 'Omar');
    await enterIn(tester, 'recipient-phone', '123');
    await enterIn(tester, 'recipient-email', 'not-an-email');
    await _buy(tester);
    expect(find.text(_en.errorInvalidPhone), findsOneWidget);
    expect(find.text(_en.errorInvalidEmail), findsOneWidget);
    expect(h.callable.calls, isEmpty);

    await enterIn(tester, 'recipient-phone', '');
    await enterIn(tester, 'recipient-email', ' Omar@Example.com ');
    await _buy(tester);
    final sent = h.callable.callsTo('purchaseGiftCard').single;
    expect(sent['recipientName'], 'Omar');
    expect(sent['recipientPhone'], isNull);
    expect(sent['recipientEmail'], 'omar@example.com');
  });

  testWidgets('schedule: picks a date from tomorrow; sends 09:00 that day', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db());
    await _fillRecipient(tester);
    await tapKey(tester, 'send-scheduled');
    // The picker opens on tomorrow; today is not selectable.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('21'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('25'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('25/10/2026'), findsOneWidget);

    await _buy(tester);
    final sent = h.callable.callsTo('purchaseGiftCard').single;
    expect(sent['scheduledAt'], DateTime(2026, 10, 25, 9).toUtc().toIso8601String());
  });

  testWidgets('schedule without a date is an error; "Send now" clears it', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db());
    await _fillRecipient(tester);
    await tapKey(tester, 'send-scheduled');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _buy(tester);
    expect(find.text(_en.giftCardScheduleRequired), findsOneWidget);
    expect(h.callable.calls, isEmpty);

    await tapKey(tester, 'send-now');
    await _buy(tester);
    expect(h.callable.callsTo('purchaseGiftCard').single['scheduledAt'], isNull);
  });

  testWidgets('cash on delivery sends the default address and navigates to Order Success', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db());
    expect(find.text(_en.giftCardCodNote), findsOneWidget);
    expect(find.byKey(const ValueKey('designer-address-a1')), findsOneWidget);
    await _fillRecipient(tester);
    await enterIn(tester, 'designer-message', '  Enjoy  ');
    await _buy(tester);

    final sent = h.callable.callsTo('purchaseGiftCard').single;
    expect(sent['templateId'], 'a');
    expect(sent['amount'], 15000);
    expect(sent['recipientPhone'], '+9647501112233');
    expect(sent['message'], 'Enjoy');
    expect(sent['paymentMethod'], PaymentMethod.cashOnDelivery.name);
    expect(sent['addressId'], 'a1');
    expect(sent['photoUrl'], isNull);
    expect(h.location, '/order-success/o1');
    expect(find.text('order success o1'), findsOneWidget);
    expect(h.analytics.events['purchase']?['item_category'], 'gift_card');
  });

  testWidgets('cash on delivery needs an address', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db(address: false));
    await _fillRecipient(tester);
    expect(find.byKey(const ValueKey('designer-add-address')), findsOneWidget);
    await _buy(tester);
    expect(find.text(_en.giftCardAddressRequired), findsOneWidget);
    expect(h.callable.calls, isEmpty);
  });

  testWidgets('wallet is offered only when the balance covers the card (credits do not count)', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db(balance: 10000));
    await tapKey(tester, 'amount-chip-25000');
    RadioListTile<PaymentMethod> wallet() =>
        tester.widget<RadioListTile<PaymentMethod>>(find.byKey(const ValueKey('payment-wallet')));
    expect(wallet().enabled, isFalse);
    expect(find.text(_en.giftCardWalletShort('10,000 IQD')), findsOneWidget);

    await tapKey(tester, 'amount-chip-15000');
    expect(wallet().enabled, isFalse);

    await h.firestore.doc('wallets/u1').set({'balance': 30000, 'credits': 0});
    await tester.pumpAndSettle();
    expect(wallet().enabled, isTrue);
    expect(find.text(_en.giftCardWalletNote('30,000 IQD')), findsOneWidget);
    await tapKey(tester, 'payment-wallet');
    expect(find.text(_en.giftCardCodNote), findsNothing);
    await _fillRecipient(tester);
    await _buy(tester);
    final sent = h.callable.callsTo('purchaseGiftCard').single;
    expect(sent['paymentMethod'], PaymentMethod.wallet.name);
    expect(sent['addressId'], isNull);
  });

  testWidgets('a retry reuses ONE clientRequestId; failures are explained', (tester) async {
    final callable = FakeCallable()
      ..script('purchaseGiftCard', [
        FirebaseFunctionsException(code: 'unavailable', message: ''),
        FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'insufficient_funds'}),
        FirebaseFunctionsException(code: 'permission-denied', message: ''),
      ]);
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db(), callable: callable);
    await _fillRecipient(tester);

    await _buy(tester);
    expect(find.text(_en.orderFailedUnavailable), findsOneWidget);
    await _buy(tester);
    expect(find.text(_en.walletInsufficient), findsOneWidget);
    await _buy(tester);
    expect(find.text(_en.somethingWentWrong), findsOneWidget);
    expect(h.location, _path);

    await _buy(tester);
    final ids = h.callable.callsTo('purchaseGiftCard').map((c) => c['clientRequestId']).toSet();
    expect(h.callable.callsTo('purchaseGiftCard'), hasLength(4));
    expect(ids, hasLength(1));
    expect(ids.single, isNotEmpty);
    expect(h.location, '/order-success/o1');
  });

  testWidgets('the photo is uploaded once into gift_cards/{uid}/{clientRequestId}', (tester) async {
    final callable = FakeCallable()
      ..script('purchaseGiftCard', [FirebaseFunctionsException(code: 'unavailable', message: '')]);
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db(), callable: callable);
    await addPhoto(tester, 'designer-photo-add', _en);
    expect(h.photos.picks, 1);
    expect(find.byKey(const ValueKey('designer-photo-add')), findsNothing); // one photo max
    await tapKey(tester, 'designer-photo-remove-0');
    expect(find.byKey(const ValueKey('designer-photo-add')), findsOneWidget);
    await addPhoto(tester, 'designer-photo-add', _en);
    await _fillRecipient(tester);
    await _buy(tester);
    await _buy(tester);

    final calls = h.callable.callsTo('purchaseGiftCard');
    final id = calls.first['clientRequestId'];
    expect(h.uploads.folders, ['gift_cards/u1/$id']);
    expect(calls.first['photoUrl'], 'https://img/gift_cards/u1/$id/1.jpg');
    expect(calls.last['photoUrl'], 'https://img/gift_cards/u1/$id/1.jpg');
    expect(calls.last['clientRequestId'], id);
  });

  testWidgets('a failed upload says so and places nothing', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db());
    h.uploads.error = Exception('storage down');
    await addPhoto(tester, 'designer-photo-add', _en);
    await _fillRecipient(tester);
    await _buy(tester);
    expect(find.text(_en.photoUploadFailed), findsOneWidget);
    expect(h.callable.calls, isEmpty);
  });

  testWidgets('guests design freely but must sign in to buy', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, firestore: await _db(), guest: true);
    await _fillRecipient(tester);
    await _buy(tester);
    expect(find.text(_en.signInToContinue), findsOneWidget);
    expect(h.callable.calls, isEmpty);
  });

  testWidgets('unknown template → not available + shop link', (tester) async {
    final h = await pumpPhase8(tester, initialPath: '/gift-cards/design/nope', firestore: await _db());
    expect(find.byKey(const ValueKey('designer-not-found')), findsOneWidget);
    await tester.tap(find.text(_en.giftCardShopTitle));
    await tester.pumpAndSettle();
    expect(h.location, '/gift-cards/shop');
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await pumpPhase8(tester, initialPath: _path, firestore: await _db(), locale: locale, themeMode: mode);
        await tapKey(tester, 'amount-chip-custom');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320 px, 1.3× text, with errors shown', (tester) async {
      await pumpPhase8(tester,
          initialPath: _path,
          firestore: await _db(balance: 1000),
          locale: 'ckb',
          size: const Size(320, 3000),
          textScale: 1.3);
      await tapKey(tester, 'amount-chip-custom');
      await tapKey(tester, 'send-scheduled');
      await tester.tapAt(const Offset(4, 4)); // dismiss the date picker
      await tester.pumpAndSettle();
      await _buy(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
