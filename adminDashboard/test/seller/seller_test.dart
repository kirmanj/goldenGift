import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/dashboard/dashboard_screen.dart';
import 'package:golden_gift_admin/features/gift_cards/gift_cards_screen.dart';
import 'package:golden_gift_admin/features/orders/data/seller_orders.dart';
import 'package:golden_gift_admin/features/orders/orders_screen.dart';
import 'package:golden_gift_admin/features/products/product_editor_screen.dart';
import 'package:golden_gift_admin/features/products/products_screen.dart';
import 'package:golden_gift_admin/features/seller/data/seller_kpis.dart';
import 'package:golden_gift_admin/features/seller/store_profile_screen.dart';

import '../products/products_test_helpers.dart' show seedProduct;
import 'phase8_test_harness.dart';

ProductModel product(String id, String title, String storeId, {bool featured = false}) => ProductModel(
      id: id,
      title: LocalizedText(title),
      storeId: storeId,
      price: 20000,
      isFeatured: featured,
    );

/// store-a (the seller's, active) + store-b, products of both, orders of both.
Future<FakeFirebaseFirestore> sellerWorld({String storeStatus = 'active'}) async {
  final db = FakeFirebaseFirestore();
  await seedStore(db, 'store-a', name: 'Store A', status: storeStatus, commission: 10, ownerUid: sellerSession.uid);
  await seedStore(db, 'store-b', name: 'Store B');
  await seedProduct(db, product('mug-a', 'Engraved Mug', 'store-a'), createdAt: DateTime(2026, 10, 2));
  await seedProduct(db, product('frame-b', 'Walnut Frame', 'store-b', featured: true), createdAt: DateTime(2026, 10, 3));
  final now = DateTime.now();
  await db.doc('orders/o1').set(multiStoreOrder(createdAt: now.subtract(const Duration(hours: 1))));
  await db.doc('orders/o2').set({
    ...multiStoreOrder(number: 'GG-2610-00002', createdAt: now.subtract(const Duration(days: 2))),
    'storeIds': ['store-b'],
    'items': [orderLine('x', 'store-b', title: 'Other store only', unitPrice: 50000)],
  });
  return db;
}

Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

void main() {
  group('session', () {
    test('a seller claim (no admin claim) is a seller session for the claimed store', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('admins/u1').set({'role': 'seller', 'storeId': 'ignored', 'name': 'Hawre'});
      final s = await resolveAdminClaims(uid: 'u1', email: 'h@x.iq', claims: {'seller': 'store-a'}, db: db);
      expect(s, isA<AdminSession>());
      s as AdminSession;
      expect(s.isSeller, isTrue);
      expect(s.storeId, 'store-a', reason: 'the claim is what the rules check');
      expect(s.name, 'Hawre');
    });

    test('a seller without an admins doc still gets in; no claim = not authorized', () async {
      final db = FakeFirebaseFirestore();
      final s = await resolveAdminClaims(uid: 'u1', email: 'h@x.iq', displayName: 'H', claims: {'seller': 'store-a'}, db: db);
      expect((s as AdminSession).name, 'H');
      expect(await resolveAdminClaims(uid: 'u1', email: 'h@x.iq', claims: const {}, db: db), isA<AdminNotAuthorized>());
      expect(await resolveAdminClaims(uid: 'u1', email: 'h@x.iq', claims: {'seller': ''}, db: db), isA<AdminNotAuthorized>());
    });

    test('staff: admin claim + admins doc as before', () async {
      final db = FakeFirebaseFirestore();
      expect(await resolveAdminClaims(uid: 'a1', email: 'a@x', claims: {'admin': true}, db: db), isA<AdminNotAuthorized>());
      await db.doc('admins/a1').set({'role': 'ops', 'name': 'Ops'});
      final s = await resolveAdminClaims(uid: 'a1', email: 'a@x', claims: {'admin': true}, db: db) as AdminSession;
      expect(s.role, AdminRole.ops);
      expect(s.storeId, isNull);
    });
  });

  group('gate & navigation', () {
    testWidgets('a pending store sees the pending page instead of the dashboard', (tester) async {
      final db = await sellerWorld(storeStatus: 'pendingApproval');
      await pumpPhase8(tester, const DashboardScreen(), db: db, session: sellerSession);
      expect(find.text('Your store is pending approval'), findsOneWidget);
      expect(find.text('Orders today'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('a suspended store sees the suspended page', (tester) async {
      final db = await sellerWorld(storeStatus: 'suspended');
      await pumpPhase8(tester, const OrdersScreen(), db: db, session: sellerSession);
      expect(find.text('Your store is suspended'), findsOneWidget);
      expect(find.text('GG-2610-00001'), findsNothing);
    });

    testWidgets('a store that no longer exists (rejected) is explained', (tester) async {
      final db = FakeFirebaseFirestore();
      await pumpPhase8(tester, const DashboardScreen(), db: db, session: sellerSession);
      expect(find.text('Your store could not be found'), findsOneWidget);
    });

    testWidgets('an active seller gets own KPIs and the seller nav only', (tester) async {
      final db = await sellerWorld();
      await pumpPhase8(tester, const DashboardScreen(), db: db, session: sellerSession, size: const Size(1440, 1000));
      expect(find.text('Orders today'), findsOneWidget);
      expect(find.text('To confirm'), findsOneWidget);
      expect(find.text('30,000 IQD'), findsOneWidget, reason: 'store-a lines only');
      expect(find.text('Store profile'), findsOneWidget);
      expect(find.text('Gift cards'), findsNothing);
      expect(find.text('Stores / Partners'), findsNothing);
    });

    testWidgets('staff never see the seller-only nav item', (tester) async {
      final db = await sellerWorld();
      await pumpPhase8(tester, const DashboardScreen(), db: db, size: const Size(1440, 1000));
      expect(find.text('Store profile'), findsNothing);
      expect(find.text('Gift cards'), findsOneWidget);
    });

    testWidgets('a seller opening an admin module gets a polite refusal', (tester) async {
      final db = await sellerWorld();
      await pumpPhase8(tester, const GiftCardsScreen(), db: db, session: sellerSession);
      expect(find.text('This module is not available to partner accounts.'), findsOneWidget);
      expect(find.text('Templates'), findsNothing);
    });
  });

  group('KPIs', () {
    test('count only the seller’s lines', () {
      final now = DateTime(2026, 10, 21, 15);
      final orders = [
        OrderModel.fromMap('o1', multiStoreOrder(createdAt: DateTime(2026, 10, 21, 9))),
        OrderModel.fromMap('o2', multiStoreOrder(aStatus: 'preparing', createdAt: DateTime(2026, 10, 19))),
        OrderModel.fromMap('o3', multiStoreOrder(aStatus: 'cancelledBySeller', createdAt: DateTime(2026, 10, 18))),
        OrderModel.fromMap('o4', {
          ...multiStoreOrder(createdAt: DateTime(2026, 10, 21, 10)),
          'items': [orderLine('x', 'store-b')],
        }),
      ];
      final k = SellerKpis.of(orders, 'store-a', now);
      expect(k.ordersToday, 1);
      expect(k.pending, 1);
      expect(k.inProgress, 1);
      expect(k.revenue, 60000, reason: '2 × 30,000; the cancelled line and store-b’s order don’t count');
      expect(k.ordersInWindow, 3);
    });
  });

  group('products', () {
    testWidgets('the list shows only the seller’s products, without Featured or the keyword rebuild', (tester) async {
      final db = await sellerWorld();
      await pumpPhase8(tester, const ProductsScreen(), db: db, session: sellerSession, size: const Size(1440, 1000));
      await tester.pump(const Duration(milliseconds: 100));
      await settle(tester);
      expect(find.text('Engraved Mug'), findsOneWidget);
      expect(find.text('Walnut Frame'), findsNothing);
      expect(find.text('Featured'), findsNothing);
      expect(find.text('Rebuild search keywords'), findsNothing);
      expect(find.byKey(const ValueKey('active-mug-a')), findsOneWidget);
    });

    testWidgets('staff still see every store’s products and Featured', (tester) async {
      final db = await sellerWorld();
      await pumpPhase8(tester, const ProductsScreen(), db: db, size: const Size(1440, 1000));
      expect(find.text('Walnut Frame'), findsOneWidget);
      expect(find.text('Engraved Mug'), findsOneWidget);
      expect(find.text('Featured'), findsOneWidget);
    });

    testWidgets('a new product is locked to the seller’s store and saved there', (tester) async {
      final db = await sellerWorld();
      await pumpPhase8(tester, const ProductEditorScreen(), db: db, session: sellerSession, size: const Size(1280, 2400));
      expect(find.text('Your store'), findsOneWidget);
      expect(find.text('Store A'), findsOneWidget);
      expect(find.text('Featured'), findsNothing);
      expect(find.byTooltip('Delete product'), findsNothing);
      final picker = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>).first);
      expect(picker.onChanged, isNull, reason: 'the store picker is locked');

      await tester.enterText(field('Title · English *'), 'Seller Candle');
      await tester.enterText(field('Price (IQD) *'), '12000');
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('• Choose who it is a gift for (at least one).'), findsOneWidget, reason: 'sellers choose too');
      expect((await db.doc('products/seller-candle').get()).exists, isFalse);
      await tester.tap(find.text('For her'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      final saved = (await db.doc('products/seller-candle').get()).data();
      expect(saved, isNotNull);
      expect(saved!['storeId'], 'store-a');
      expect(saved['isFeatured'], isFalse);
      expect(saved['giftFor'], ['women']);
      expect(saved['forKeys'], contains('women'));
    });

    testWidgets('another store’s product does not open for a seller', (tester) async {
      final db = await sellerWorld();
      await pumpPhase8(tester, const ProductEditorScreen(productId: 'frame-b'), db: db, session: sellerSession);
      expect(find.text('This product belongs to another store.'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });
  });

  group('orders', () {
    test('line status, transitions and the seller view', () {
      final order = OrderModel.fromMap('o1', multiStoreOrder(aStatus: 'preparing', bStatus: 'pending'));
      final view = sellerOrderView(order, 'store-a');
      expect(view.items.map((i) => i.line.storeId), ['store-a']);
      expect(view.total, 30000);
      expect(view.userId, isEmpty);
      expect(sellerOrderView(order, 'store-a', packingSlip: true).hidePrices, isTrue);
      expect(sellerLinesStatus(view.items), OrderStatus.preparing);
      expect(sellerTransitions(OrderStatus.preparing), [OrderStatus.readyForDelivery, OrderStatus.cancelledBySeller]);
      expect(sellerTransitions(OrderStatus.delivered), [OrderStatus.returned], reason: 'refunds stay with finance');
      expect(sellerTransitions(null), isEmpty);
      final mixed = [
        OrderItem.fromMap(orderLine('1', 's', status: 'readyForDelivery')),
        OrderItem.fromMap(orderLine('2', 's', status: 'confirmed')),
        OrderItem.fromMap(orderLine('3', 's', status: 'cancelledBySeller')),
      ];
      expect(sellerLinesStatus(mixed), OrderStatus.confirmed, reason: 'least advanced line still on the flow');
      expect(sellerLinesStatus([mixed.last]), OrderStatus.cancelledBySeller);
      expect(SellerOrdersRepository.payload(orderId: 'o1', status: OrderStatus.preparing, note: '  '),
          {'orderId': 'o1', 'status': 'preparing'});
    });

    testWidgets('the seller sees only their orders and lines and moves their lines via updateOrderItems', (tester) async {
      final db = await sellerWorld();
      final calls = FakeCallables()..responses['updateOrderItems'] = {'status': 'pending'};
      await pumpPhase8(tester, const OrdersScreen(), db: db, session: sellerSession, calls: calls, size: const Size(1440, 1000));
      expect(find.text('GG-2610-00001'), findsOneWidget);
      expect(find.text('GG-2610-00002'), findsNothing);
      expect(find.text('30,000 IQD'), findsOneWidget, reason: 'row total = own lines');
      expect(find.text('All store'), findsNothing, reason: 'no store filter for sellers');

      await tester.tap(find.text('GG-2610-00001'));
      await settle(tester);
      expect(find.text('Engraved Mug'), findsOneWidget);
      expect(find.text('Walnut Frame'), findsNothing);
      expect(find.textContaining('42,000'), findsNothing);
      expect(find.textContaining('77,000'), findsNothing, reason: 'the order total includes other stores');
      expect(find.text('Customer id'), findsNothing);
      expect(find.text('Your items total'), findsOneWidget);
      expect(find.text('Print packing slip'), findsOneWidget);

      await tester.tap(find.text('Mark your items confirmed'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).last, 'On it');
      await tester.tap(find.text('Confirm'));
      await settle(tester);
      expect(calls.payloadsFor('updateOrderItems').single, {'orderId': 'o1', 'status': 'confirmed', 'note': 'On it'});
      expect((await db.doc('orders/o1').get()).data()!['status'], 'pending', reason: 'the seller never writes the order');
      expect(await auditEntries(db), isEmpty);
    });

    testWidgets('cancelling their lines needs a reason', (tester) async {
      final db = await sellerWorld();
      final calls = FakeCallables();
      await pumpPhase8(tester, const OrdersScreen(), db: db, session: sellerSession, calls: calls, size: const Size(1440, 1000));
      await tester.tap(find.text('GG-2610-00001'));
      await settle(tester);
      await tester.tap(find.text('Your items: cancelled by us'));
      await settle(tester);
      await tester.tap(find.text('Confirm'));
      await settle(tester);
      expect(find.text('Required'), findsOneWidget);
      expect(calls.calls, isEmpty);
    });
  });

  group('store profile', () {
    testWidgets('the seller edits their store; the commission is read-only', (tester) async {
      final db = await sellerWorld();
      await pumpPhase8(tester, const StoreProfileScreen(), db: db, session: sellerSession, size: const Size(1440, 1600));
      expect(find.text('Set by Golden Gift'), findsOneWidget);
      expect(find.byKey(const ValueKey('storeCommission')), findsNothing);
      await tester.enterText(field('Store name · English *'), 'Store A Gifts');
      await tester.enterText(find.byKey(const ValueKey('storePhone')), '0751 222 3344');
      await tester.tap(find.text('Save profile'));
      await settle(tester);
      final saved = (await db.doc('stores/store-a').get()).data()!;
      expect(saved['name'], 'Store A Gifts');
      expect(saved['phone'], '+9647512223344');
      expect(saved['commissionPercent'], 10);
      final audit = (await auditEntries(db)).single;
      expect(audit['adminUid'], sellerSession.uid);
      expect(audit['action'], 'store.update');
      expect((audit['after'] as Map).containsKey('commissionPercent'), isFalse);
    });

    testWidgets('staff are pointed to Stores / Partners', (tester) async {
      final db = await sellerWorld();
      await pumpPhase8(tester, const StoreProfileScreen(), db: db);
      expect(find.textContaining('Only partner accounts have a store profile'), findsOneWidget);
    });
  });

  for (final (mode, size) in layoutMatrix) {
    testWidgets('seller pages lay out in ${mode.name} at ${size.width.toInt()} px', (tester) async {
      final db = await sellerWorld();
      await db.doc('orders/o1').update({'isGift': true, 'giftMessage': 'Love you', 'hidePrices': true});
      final errors = await errorsOutsideCoreNav(() async {
        await pumpPhase8(tester, const DashboardScreen(), db: db, session: sellerSession, mode: mode, size: size);
        expect(find.text('Orders today'), findsOneWidget);
        await pumpPhase8(tester, const OrdersScreen(), db: db, session: sellerSession, mode: mode, size: size);
        await tester.tap(find.text('GG-2610-00001'));
        await settle(tester);
        expect(find.text('Your items'), findsOneWidget);
        await pumpPhase8(tester, const ProductsScreen(), db: db, session: sellerSession, mode: mode, size: size);
        expect(find.text('Engraved Mug'), findsOneWidget);
        await pumpPhase8(tester, const StoreProfileScreen(), db: db, session: sellerSession, mode: mode, size: size);
        expect(find.text('Save profile'), findsOneWidget);
        await db.doc('stores/store-a').update({'status': 'suspended'});
        await settle(tester);
        expect(find.text('Your store is suspended'), findsOneWidget);
        await db.doc('stores/store-a').update({'status': 'active'});
      });
      expect(errors, isEmpty);
    });
  }
}
