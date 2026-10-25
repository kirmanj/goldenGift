import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';

import '../checkout/phase6_test_harness.dart';

final _en = l10nFor('en');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A wallet-paid gift-card order: one synthetic line, no address, no date.
Future<FakeFirebaseFirestore> _giftCardOrder({bool withRecipient = true}) async {
  final db = FakeFirebaseFirestore();
  await seedOrder(db, 'o1', status: 'confirmed', items: [
    {
      'id': 'gc',
      'productId': '',
      'storeId': '',
      'titleSnapshot': 'Gift card',
      'unitPrice': 50000,
      'qty': 1,
      'status': 'confirmed',
      'selections': [
        {'groupId': 'recipient', 'type': 'text', 'label': 'Recipient', 'text': 'Lana'},
      ],
    },
  ], extra: {
    'orderType': 'giftCard',
    'paymentMethod': 'wallet',
    'address': null,
    'deliveryDate': null,
    'deliverySlot': null,
    if (withRecipient)
      'giftCard': {
        'templateId': 't1',
        'amount': 50000,
        'recipientName': 'Lana Karim',
        'recipientPhone': '+9647701234567',
        'recipientEmail': null,
      },
  });
  return db;
}

void main() {
  group('refund to the wallet', () {
    testWidgets('credits + balance: total, both parts, opens My Wallet', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedOrder(db, 'o1', status: 'cancelledByBuyer', extra: {'refundedCredits': 3000, 'refundedBalance': 5000});
      final h = await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: db);
      expect(find.text(_en.orderRefundedToWallet('8,000 IQD')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('order-refund-credits')), matching: find.text('3,000 IQD')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('order-refund-balance')), matching: find.text('5,000 IQD')),
          findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('order-refund')));
      expect(h.location, AppRoutes.wallet);
    });

    testWidgets('one kind only: just the total line', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedOrder(db, 'o1', status: 'refunded', extra: {'refundedBalance': 75000});
      await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: db);
      expect(find.text(_en.orderRefundedToWallet('75,000 IQD')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-refund-credits')), findsNothing);
      expect(find.byKey(const ValueKey('order-refund-balance')), findsNothing);
    });

    testWidgets('nothing refunded: no row', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedOrder(db, 'o1', status: 'cancelledByBuyer');
      await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: db);
      expect(find.byKey(const ValueKey('order-refund')), findsNothing);
    });
  });

  group('gift-card and special-request orders', () {
    testWidgets('gift card: recipient instead of address / delivery, no Reorder, no "null"', (tester) async {
      await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: await _giftCardOrder());
      expect(find.byKey(const ValueKey('order-gift-recipient')), findsOneWidget);
      expect(find.text(_en.giftCardRecipientTitle), findsOneWidget);
      expect(find.text('Lana Karim'), findsOneWidget);
      expect(find.text('+9647701234567'), findsOneWidget);
      expect(find.text(_en.deliveryAddress), findsNothing);
      expect(find.byKey(const ValueKey('order-delivery-when')), findsNothing);
      expect(find.byKey(const ValueKey('reorder')), findsNothing);
      expect(find.textContaining('null'), findsNothing);
      expect(find.text(_en.walletPayment), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('gift card without recipient data: the section is simply hidden', (tester) async {
      await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: await _giftCardOrder(withRecipient: false));
      expect(find.byKey(const ValueKey('order-gift-recipient')), findsNothing);
      expect(find.byKey(const ValueKey('reorder')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('special request: no Reorder', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedOrder(db, 'o1', status: 'confirmed', items: [
        {'id': 'sr', 'productId': '', 'storeId': '', 'titleSnapshot': 'Special request', 'unitPrice': 90000, 'qty': 1},
      ], extra: {'orderType': 'specialRequest'});
      await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: db);
      expect(find.text('Special request'), findsOneWidget);
      expect(find.byKey(const ValueKey('reorder')), findsNothing);
    });

    testWidgets('standard orders keep Reorder', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedOrder(db, 'o1', status: 'delivered');
      await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: db);
      expect(find.byKey(const ValueKey('reorder')), findsOneWidget);
    });
  });

  testWidgets('timeline names the store (seller) and the customer; admin changes stay unlabelled', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedOrder(db, 'o1', status: 'preparing');
    var minute = 0;
    for (final (status, role) in [('pending', 'customer'), ('confirmed', 'admin'), ('preparing', 'seller')]) {
      await db.collection('orders/o1/status_history').add({
        'status': status,
        'byRole': role,
        'at': DateTime(2026, 10, 20, 12, minute++),
      });
    }
    await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: db);
    expect(tester.widget<Text>(find.byKey(const ValueKey('timeline-by-preparing'))).data, _en.orderChangedByStore);
    expect(find.text(_en.orderChangedByYou), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-by-confirmed')), findsNothing);
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light)]) {
      testWidgets('$locale ${mode.name}: refund + store label + gift card', (tester) async {
        final l10n = l10nFor(locale);
        final db = FakeFirebaseFirestore();
        await seedOrder(db, 'o1',
            status: 'cancelledBySeller', extra: {'refundedCredits': 2000, 'refundedBalance': 4000});
        await db.collection('orders/o1/status_history').add({'status': 'preparing', 'byRole': 'seller', 'at': DateTime(2026, 10, 20)});
        final h = await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: db, locale: locale, themeMode: mode);
        expect(find.text(l10n.orderRefundedToWallet('6,000 IQD')), findsOneWidget);
        expect(find.text(l10n.orderChangedByStore), findsOneWidget);
        expect(tester.takeException(), isNull);
        h.router.go(AppRoutes.order('o2'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('320 px, 1.3× text (ckb)', (tester) async {
      final db = await _giftCardOrder();
      await db.doc('orders/o1').update({'status': 'refunded', 'refundedCredits': 20000, 'refundedBalance': 30000});
      await pumpPhase6(tester,
          initialPath: AppRoutes.order('o1'), firestore: db, locale: 'ckb', size: const Size(320, 3000), textScale: 1.3);
      expect(find.byKey(const ValueKey('order-refund')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
