import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/orders/presentation/widgets/order_status_chip.dart';

import '../checkout/phase6_test_harness.dart';

final _en = l10nFor('en');

Map<String, dynamic> _item(String id) => {
      'id': id,
      'productId': 'box',
      'storeId': 's1',
      'titleSnapshot': 'Gift Box',
      'unitPrice': 10000,
      'qty': 1,
      'status': 'pending',
    };

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await seedOrder(db, 'p', status: 'pending', number: 'GG-1', createdAt: DateTime(2026, 10, 20), items: [
    for (final i in ['a', 'b', 'c', 'd', 'e']) _item(i)
  ]);
  await seedOrder(db, 'o', status: 'outForDelivery', number: 'GG-2', createdAt: DateTime(2026, 10, 19));
  await seedOrder(db, 'd', status: 'delivered', number: 'GG-3', createdAt: DateTime(2026, 10, 18));
  await seedOrder(db, 'c', status: 'cancelledByBuyer', number: 'GG-4', createdAt: DateTime(2026, 10, 17));
  await seedOrder(db, 'r', status: 'refunded', number: 'GG-5', createdAt: DateTime(2026, 10, 16));
  await db
      .doc('orders/x')
      .set({'userId': 'someone-else', 'orderNumber': 'GG-9', 'status': 'pending', 'createdAt': DateTime(2026, 10, 21)});
  return db;
}

void main() {
  testWidgets('tabs split orders by status family', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.orders, firestore: await _seed());
    expect(find.text(_en.orderNumber('GG-1')), findsOneWidget);
    expect(find.text(_en.orderNumber('GG-2')), findsOneWidget);
    expect(find.text(_en.orderNumber('GG-3')), findsNothing);
    expect(find.text(_en.orderNumber('GG-9')), findsNothing); // another customer's order
    expect(find.text('20/10/2026'), findsOneWidget);
    expect(find.text('75,000 IQD'), findsNWidgets(2));
    // Up to 3 thumbnails, then "+2".
    expect(find.text('+2'), findsOneWidget);

    await tester.tap(find.text(_en.completedOrders));
    await tester.pumpAndSettle();
    expect(find.text(_en.orderNumber('GG-3')), findsOneWidget);
    expect(find.text(_en.orderNumber('GG-1')), findsNothing);

    await tester.tap(find.text(_en.cancelledOrders));
    await tester.pumpAndSettle();
    expect(find.text(_en.orderNumber('GG-4')), findsOneWidget);
    expect(find.text(_en.orderNumber('GG-5')), findsOneWidget);
    expect(find.text(_en.statusRefunded), findsOneWidget);
  });

  testWidgets('status chips use one colour per family', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.orders, firestore: await _seed());
    expect(orderStatusTone(OrderStatus.pending), OrderStatusTone.info);
    expect(orderStatusTone(OrderStatus.confirmed), OrderStatusTone.info);
    for (final s in [OrderStatus.preparing, OrderStatus.readyForDelivery, OrderStatus.outForDelivery]) {
      expect(orderStatusTone(s), OrderStatusTone.progress);
    }
    expect(orderStatusTone(OrderStatus.delivered), OrderStatusTone.success);
    for (final s in [
      OrderStatus.cancelledByBuyer,
      OrderStatus.cancelledBySeller,
      OrderStatus.returned,
      OrderStatus.refunded
    ]) {
      expect(orderStatusTone(s), OrderStatusTone.error);
    }
    final context = tester.element(find.byKey(const ValueKey('status-chip-pending')));
    final tones = OrderStatusTone.values.map((t) => orderStatusColors(context, t).$2).toSet();
    expect(tones, hasLength(4));
  });

  testWidgets('tapping a card opens its details', (tester) async {
    final h = await pumpPhase6(tester, initialPath: AppRoutes.orders, firestore: await _seed());
    await tester.tap(find.text(_en.orderNumber('GG-2')));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.order('o'));
    expect(find.text(_en.orderDetails), findsOneWidget);
  });

  testWidgets('an empty tab shows its empty state', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.orders);
    expect(find.byKey(const ValueKey('orders-empty-active')), findsOneWidget);
    expect(find.text(_en.noOrdersTitle), findsOneWidget);
    await tester.tap(find.text(_en.cancelledOrders));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('orders-empty-cancelled')), findsOneWidget);
  });

  testWidgets('guests see the sign-in card', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.orders, guest: true);
    expect(find.byKey(const ValueKey('guest-sign-in-card')), findsOneWidget);
    expect(find.text(_en.activeOrders), findsNothing);
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.light), ('ar', ThemeMode.dark), ('ckb', ThemeMode.dark)]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await pumpPhase6(tester,
            initialPath: AppRoutes.orders, firestore: await _seed(), locale: locale, themeMode: mode);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('320 px, 1.3× text', (tester) async {
      await pumpPhase6(tester,
          initialPath: AppRoutes.orders,
          firestore: await _seed(),
          locale: 'ckb',
          size: const Size(320, 1200),
          textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });
}
