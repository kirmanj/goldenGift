import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/features/gift_cards/data/gift_cards_repository.dart';
import 'package:golden_gift/features/orders/data/orders_repository.dart';
import 'package:golden_gift/models/gift_card_model.dart';
import 'package:golden_gift/models/localized_text.dart';

void main() {
  test('templates: active only, by sortOrder; amount rules', () async {
    final db = FakeFirebaseFirestore();
    Future<void> t(String id, int order, {bool active = true}) => db.doc('${FirestorePaths.giftCardTemplates}/$id').set({
          'name': 'T$id',
          'presetAmounts': [15000, 25000, 100000],
          'minAmount': 10000,
          'maxAmount': 500000,
          'sortOrder': order,
          'isActive': active,
        });
    await t('b', 2);
    await t('a', 1);
    await t('off', 0, active: false);
    final list = await GiftCardsRepository(db, (_, __) async => null).watchTemplates().first;
    expect(list.map((t) => t.id), ['a', 'b']);
    final tpl = list.first;
    expect(tpl.accepts(25000), isTrue);
    expect(tpl.accepts(12345), isTrue);
    expect(tpl.accepts(9999), isFalse);
    expect(tpl.accepts(600000), isFalse);
    expect(const GiftCardTemplateModel(id: 'x', name: LocalizedText.empty, presetAmounts: [5000]).accepts(6000), isFalse);
  });

  test('received / purchased cards and the formatted code', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('${FirestorePaths.giftCards}/g1').set({
      'code': 'ABCDEFGHJKLM',
      'templateId': 'a',
      'amount': 25000,
      'balance': 25000,
      'purchaserUid': 'buyer',
      'recipientUid': 'me',
      'recipientName': 'Sara',
      'status': 'sent',
      'sentAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      'expiresAt': Timestamp.fromDate(DateTime(2027, 10, 1)),
    });
    final repo = GiftCardsRepository(db, (_, __) async => null);
    final received = await repo.watchReceived('me').first;
    expect(received.single.formattedCode, 'ABCD-EFGH-JKLM');
    expect(received.single.isRedeemable(DateTime(2026, 10, 21)), isTrue);
    expect(received.single.isRedeemable(DateTime(2027, 10, 2)), isFalse);
    expect((await repo.watchPurchased('buyer').first).single.id, 'g1');
  });

  test('purchase sends the designer payload and maps failures like orders', () async {
    final sent = <(String, Map<String, dynamic>)>[];
    final repo = GiftCardsRepository(FakeFirebaseFirestore(), (name, data) async {
      sent.add((name, data));
      return {'orderId': 'o1', 'orderNumber': 'GG-2610-00009', 'total': 25000};
    });
    final placed = await repo.purchase(GiftCardPurchase(
      clientRequestId: 'r1',
      templateId: 'a',
      amount: 25000,
      recipientName: ' Sara ',
      recipientEmail: ' SARA@Example.com ',
      message: 'Happy birthday',
      scheduledAt: DateTime.utc(2026, 11, 1, 9),
      addressId: 'home',
    ));
    expect(placed.orderNumber, 'GG-2610-00009');
    expect(sent.single.$1, 'purchaseGiftCard');
    expect(sent.single.$2['recipientName'], 'Sara');
    expect(sent.single.$2['recipientEmail'], 'sara@example.com');
    expect(sent.single.$2['recipientPhone'], isNull);
    expect(sent.single.$2['scheduledAt'], '2026-11-01T09:00:00.000Z');
    expect(sent.single.$2['paymentMethod'], 'cashOnDelivery');

    final failing = GiftCardsRepository(FakeFirebaseFirestore(), (_, __) async {
      throw FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND');
    });
    await expectLater(
      failing.purchase(const GiftCardPurchase(clientRequestId: 'r', templateId: 'a', amount: 1, recipientName: 'x')),
      throwsA(isA<OrderFailure>().having((f) => f.reason, 'reason', OrderFailureReason.unavailable)),
    );
  });

  test('redeem normalizes the code and maps every failure', () async {
    final sent = <Map<String, dynamic>>[];
    final ok = GiftCardsRepository(FakeFirebaseFirestore(), (_, data) async {
      sent.add(data);
      return {'giftCardId': 'g1', 'amount': 25000, 'credits': 30000};
    });
    final r = await ok.redeem(' abcd-efgh jklm ');
    expect(sent.single['code'], 'ABCDEFGHJKLM');
    expect(r.credits, 30000);

    Future<RedeemFailureReason> reasonFor(FirebaseFunctionsException e) async {
      try {
        await GiftCardsRepository(FakeFirebaseFirestore(), (_, __) async => throw e).redeem('x');
      } on RedeemFailure catch (f) {
        return f.reason;
      }
      fail('expected a RedeemFailure');
    }

    expect(await reasonFor(FirebaseFunctionsException(code: 'not-found', message: '')), RedeemFailureReason.notFound);
    expect(await reasonFor(FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'expired'})),
        RedeemFailureReason.expired);
    expect(await reasonFor(FirebaseFunctionsException(code: 'failed-precondition', message: '', details: const {'reason': 'redeemed'})),
        RedeemFailureReason.alreadyRedeemed);
    expect(await reasonFor(FirebaseFunctionsException(code: 'resource-exhausted', message: '')),
        RedeemFailureReason.tooManyAttempts);
    expect(await reasonFor(FirebaseFunctionsException(code: 'unavailable', message: '')), RedeemFailureReason.unavailable);
  });
}
