import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/orders/data/admin_orders_repository.dart';
import 'package:golden_gift_admin/features/orders/invoice.dart';
import 'package:golden_gift_admin/features/orders/order_status_ui.dart';
import 'package:golden_gift_admin/features/orders/orders_screen.dart';

import '../categories/admin_test_harness.dart';

Map<String, dynamic> orderMap({
  String number = 'GG-2610-00001',
  OrderStatus status = OrderStatus.pending,
  String city = 'erbil',
  PaymentMethod payment = PaymentMethod.cashOnDelivery,
  DateTime? createdAt,
  bool hidePrices = false,
  bool isGift = false,
  String? giftMessage,
  String title = 'Engraved Mug',
}) =>
    {
      'orderNumber': number,
      'userId': 'u1',
      'storeIds': ['s1'],
      'items': [
        {
          'id': 'line-1',
          'productId': 'p1',
          'storeId': 's1',
          'titleSnapshot': title,
          'unitPrice': 25000,
          'qty': 2,
          'status': status.name,
          'selections': [
            {'groupId': 'g1', 'type': 'text', 'label': 'Name', 'text': 'Sara'},
            {
              'groupId': 'g2',
              'type': 'photoUpload',
              'label': 'Photos',
              'urls': ['https://example.com/a.jpg'],
            },
          ],
        },
      ],
      'subtotal': 50000,
      'deliveryFee': 5000,
      'total': 55000,
      'paymentMethod': payment.name,
      'paymentStatus': 'pending',
      'address': {'name': 'Sara', 'phone': '+9647501234567', 'city': city, 'area': 'Ankawa', 'street': '100m'},
      'deliveryDate': '2026-10-25',
      'deliverySlot': 'morning',
      'isGift': isGift,
      'giftMessage': giftMessage,
      'hidePrices': hidePrices,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 20, 12)),
    };

Future<OrderModel> seed(FakeFirebaseFirestore db, String id, Map<String, dynamic> data) async {
  await db.doc(FirestorePaths.orderDoc(id)).set(data);
  return OrderModel.fromMap(id, data);
}

void main() {
  group('AdminOrdersRepository.changeStatus', () {
    test('moves the order and every line, records note + author, and audits in the same batch', () async {
      final db = FakeFirebaseFirestore();
      final order = await seed(db, 'o1', orderMap());
      await AdminOrdersRepository(db).changeStatus(order: order, next: OrderStatus.confirmed, adminUid: 'admin-1', note: ' On it ');

      final saved = (await db.doc(FirestorePaths.orderDoc('o1')).get()).data()!;
      expect(saved['status'], 'confirmed');
      expect(saved['statusNote'], 'On it');
      expect(saved['statusUpdatedBy'], 'admin-1');
      expect(saved['statusUpdatedByRole'], 'admin');
      expect((saved['items'] as List).map((i) => (i as Map)['status']), ['confirmed']);
      // The line snapshot survives the rewrite.
      expect(((saved['items'] as List).first as Map)['titleSnapshot'], 'Engraved Mug');

      final audit = await auditEntries(db);
      expect(audit, hasLength(1));
      expect(audit.single['action'], 'order.status');
      expect(audit.single['target'], 'orders/o1');
      expect(audit.single['before'], {'status': 'pending'});
      expect(audit.single['after'], {'status': 'confirmed', 'note': 'On it'});
    });

    test('a cancellation stores the reason for the customer', () async {
      final db = FakeFirebaseFirestore();
      final order = await seed(db, 'o1', orderMap(status: OrderStatus.preparing));
      await AdminOrdersRepository(db)
          .changeStatus(order: order, next: OrderStatus.cancelledBySeller, adminUid: 'admin-1', note: 'Out of walnut');
      final saved = (await db.doc(FirestorePaths.orderDoc('o1')).get()).data()!;
      expect(saved['status'], 'cancelledBySeller');
      expect(saved['cancelReason'], 'Out of walnut');
    });

    test('rebuilds items from the stored order, keeping URLs rewritten after the model was loaded', () async {
      final db = FakeFirebaseFirestore();
      final stale = await seed(db, 'o1', orderMap());
      // placeOrder copies the customer's uploads to orders/{id}/… and rewrites the URLs.
      final fresh = orderMap();
      final line = Map<String, dynamic>.from((fresh['items'] as List).first as Map);
      line['selections'] = [
        (line['selections'] as List).first,
        {
          'groupId': 'g2',
          'type': 'photoUpload',
          'label': 'Photos',
          'urls': ['https://example.com/orders/o1/a.jpg'],
        },
      ];
      line['serverOnly'] = 'kept';
      await db.doc(FirestorePaths.orderDoc('o1')).update({
        'items': [line]
      });

      await AdminOrdersRepository(db).changeStatus(order: stale, next: OrderStatus.confirmed, adminUid: 'admin-1');

      final saved = (await db.doc(FirestorePaths.orderDoc('o1')).get()).data()!;
      final items = (saved['items'] as List).cast<Map>();
      expect(items, hasLength(1));
      expect(items.single['status'], 'confirmed');
      expect(items.single['serverOnly'], 'kept');
      expect(((items.single['selections'] as List)[1] as Map)['urls'], ['https://example.com/orders/o1/a.jpg']);
      expect((await auditEntries(db)).single['action'], 'order.status');
    });

    test('re-checks the transition against the stored status', () async {
      final db = FakeFirebaseFirestore();
      final stale = await seed(db, 'o1', orderMap());
      // Someone else already moved it on.
      await db.doc(FirestorePaths.orderDoc('o1')).update({'status': OrderStatus.delivered.name});
      await expectLater(
        AdminOrdersRepository(db).changeStatus(order: stale, next: OrderStatus.confirmed, adminUid: 'admin-1'),
        throwsStateError,
      );
      expect((await db.doc(FirestorePaths.orderDoc('o1')).get()).data()!['status'], 'delivered');
      expect(await auditEntries(db), isEmpty);
    });

    test('lines a seller already cancelled stay cancelled when the order moves on', () async {
      final db = FakeFirebaseFirestore();
      final map = orderMap(status: OrderStatus.confirmed);
      final line = (map['items'] as List).single as Map<String, dynamic>;
      map['items'] = [
        line,
        {...line, 'id': 'line-2', 'storeId': 's2', 'status': 'cancelledBySeller', 'stockReleased': true},
      ];
      final order = await seed(db, 'o1', map);
      await AdminOrdersRepository(db).changeStatus(order: order, next: OrderStatus.preparing, adminUid: 'admin-1');
      final saved = (await db.doc(FirestorePaths.orderDoc('o1')).get()).data()!;
      expect((saved['items'] as List).map((i) => (i as Map)['status']), ['preparing', 'cancelledBySeller']);
    });

    test('refuses transitions outside allowedNext and writes nothing', () async {
      final db = FakeFirebaseFirestore();
      final order = await seed(db, 'o1', orderMap());
      await expectLater(
        AdminOrdersRepository(db).changeStatus(order: order, next: OrderStatus.delivered, adminUid: 'admin-1'),
        throwsStateError,
      );
      expect((await db.doc(FirestorePaths.orderDoc('o1')).get()).data()!['status'], 'pending');
      expect(await auditEntries(db), isEmpty);
    });
  });

  group('AdminOrdersRepository.query', () {
    Future<List<String>> ids(FakeFirebaseFirestore db, OrderFilters f) async =>
        [for (final d in (await AdminOrdersRepository(db).query(f).get()).docs) d.id];

    test('filters by status, city, payment and day range; newest first', () async {
      final db = FakeFirebaseFirestore();
      await seed(db, 'a', orderMap(createdAt: DateTime(2026, 10, 18, 9)));
      await seed(db, 'b', orderMap(status: OrderStatus.delivered, city: 'duhok', createdAt: DateTime(2026, 10, 19, 23, 30)));
      await seed(db, 'c', orderMap(payment: PaymentMethod.wallet, createdAt: DateTime(2026, 10, 20, 8)));

      expect(await ids(db, const OrderFilters()), ['c', 'b', 'a']);
      expect(await ids(db, const OrderFilters(status: OrderStatus.delivered)), ['b']);
      expect(await ids(db, const OrderFilters(cityId: 'erbil')), ['c', 'a']);
      expect(await ids(db, const OrderFilters(paymentMethod: PaymentMethod.wallet)), ['c']);
      // `to` is inclusive of the whole day.
      expect(await ids(db, OrderFilters(from: DateTime(2026, 10, 19), to: DateTime(2026, 10, 19))), ['b']);
      expect(await ids(db, const OrderFilters(storeId: 's1')), ['c', 'b', 'a']);
      expect(await ids(db, const OrderFilters(storeId: 'other')), isEmpty);
    });

    test('copyWith clears individual filters', () {
      const f = OrderFilters(status: OrderStatus.pending, cityId: 'erbil');
      expect(f.copyWith(clearStatus: true), const OrderFilters(cityId: 'erbil'));
      expect(f.copyWith(clearCity: true, paymentMethod: PaymentMethod.card),
          const OrderFilters(status: OrderStatus.pending, paymentMethod: PaymentMethod.card));
    });
  });

  group('invoiceHtml', () {
    test('an invoice lists prices and totals', () {
      final html = invoiceHtml(OrderModel.fromMap('o1', orderMap()), cityName: 'Erbil');
      expect(html, contains('Invoice'));
      expect(html, contains('GG-2610-00001'));
      expect(html, contains('Engraved Mug'));
      expect(html, contains('Name: Sara'));
      expect(html, contains('1 photo(s)'));
      expect(html, contains('Subtotal'));
      expect(html, contains('Erbil'));
    });

    test('hidePrices prints a packing slip without any amount', () {
      final order = OrderModel.fromMap('o1', orderMap(hidePrices: true, isGift: true, giftMessage: 'Happy birthday!'));
      final html = invoiceHtml(order, cityName: 'Erbil');
      expect(html, contains('Packing slip'));
      expect(html, isNot(contains('Subtotal')));
      expect(html, isNot(contains('Price')));
      expect(html, isNot(contains('IQD')));
      expect(html, contains('Happy birthday!'));
    });

    test('escapes customer-entered text', () {
      final order = OrderModel.fromMap('o1', orderMap(isGift: true, giftMessage: '<script>alert(1)</script>'));
      final html = invoiceHtml(order, cityName: 'Erbil');
      expect(html, isNot(contains('<script>alert(1)')));
      expect(html, contains('&lt;script&gt;'));
    });
  });

  group('staffTransitions', () {
    AdminSession as(AdminRole role) => AdminSession(uid: 'x', email: 'x@y', name: 'X', role: role);

    test('ops and super admins get every allowed transition', () {
      expect(staffTransitions(as(AdminRole.ops), OrderStatus.pending), [OrderStatus.confirmed, OrderStatus.cancelledBySeller]);
      expect(staffTransitions(as(AdminRole.superAdmin), OrderStatus.outForDelivery),
          [OrderStatus.delivered, OrderStatus.returned]);
    });

    test('finance may only refund; content editors and sellers nothing', () {
      expect(staffTransitions(as(AdminRole.finance), OrderStatus.pending), isEmpty);
      expect(staffTransitions(as(AdminRole.finance), OrderStatus.delivered), [OrderStatus.refunded]);
      expect(staffTransitions(as(AdminRole.content), OrderStatus.pending), isEmpty);
      expect(staffTransitions(as(AdminRole.seller), OrderStatus.pending), isEmpty);
    });

    test('every status has a label and the note rule covers off-path moves', () {
      for (final s in OrderStatus.values) {
        expect(orderStatusLabel(s), isNotEmpty);
      }
      expect(statusNeedsNote(OrderStatus.cancelledBySeller), isTrue);
      expect(statusNeedsNote(OrderStatus.confirmed), isFalse);
    });
  });

  group('awaiting online payment', () {
    test('only unpaid ZainCash / card orders are flagged', () {
      OrderModel o(PaymentMethod m, PaymentStatus p, {OrderStatus s = OrderStatus.pending}) =>
          OrderModel.fromMap('o', {...orderMap(payment: m, status: s), 'paymentStatus': p.name});
      expect(awaitingOnlinePayment(o(PaymentMethod.zainCash, PaymentStatus.pending)), isTrue);
      expect(awaitingOnlinePayment(o(PaymentMethod.zainCash, PaymentStatus.paid)), isFalse);
      expect(awaitingOnlinePayment(o(PaymentMethod.cashOnDelivery, PaymentStatus.pending)), isFalse);
      expect(awaitingOnlinePayment(o(PaymentMethod.zainCash, PaymentStatus.failed, s: OrderStatus.cancelledByBuyer)),
          isFalse);
    });

    testWidgets('the panel offers only a cancellation until it is paid', (tester) async {
      final db = FakeFirebaseFirestore();
      await seed(db, 'o1', {...orderMap(payment: PaymentMethod.zainCash), 'paymentStatus': 'pending'});
      await pumpAdminScreen(tester, const OrdersScreen(), db: db);
      expect(find.text('Awaiting payment'), findsOneWidget);
      await tester.tap(find.text('GG-2610-00001'));
      await settle(tester);
      expect(find.text('Mark confirmed'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Cancelled by us'), findsOneWidget);
    });
  });

  group('OrdersScreen', () {
    testWidgets('lists orders, opens the detail and moves the status with a note', (tester) async {
      final db = FakeFirebaseFirestore();
      await seed(db, 'o1', orderMap());
      await seed(db, 'o2', orderMap(number: 'GG-2610-00002', status: OrderStatus.delivered, createdAt: DateTime(2026, 10, 19)));
      await pumpAdminScreen(tester, const OrdersScreen(), db: db);

      expect(find.text('GG-2610-00001'), findsOneWidget);
      expect(find.text('GG-2610-00002'), findsOneWidget);

      await tester.tap(find.text('GG-2610-00001'));
      await settle(tester);
      expect(find.text('Customer & delivery'), findsOneWidget);
      expect(find.text('Customer photos (1)'), findsOneWidget);
      expect(find.text('Print invoice'), findsOneWidget);

      await tester.tap(find.text('Mark confirmed'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).last, 'Packing today');
      await tester.tap(find.text('Confirm'));
      await settle(tester);

      final saved = (await db.doc(FirestorePaths.orderDoc('o1')).get()).data()!;
      expect(saved['status'], 'confirmed');
      expect(saved['statusNote'], 'Packing today');
      expect(await auditEntries(db), hasLength(1));
    });

    testWidgets('a cancellation requires a reason', (tester) async {
      final db = FakeFirebaseFirestore();
      await seed(db, 'o1', orderMap());
      await pumpAdminScreen(tester, const OrdersScreen(), db: db);
      await tester.tap(find.text('GG-2610-00001'));
      await settle(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelled by us'));
      await settle(tester);
      await tester.tap(find.text('Confirm'));
      await settle(tester);
      expect(find.text('Required'), findsOneWidget);
      expect((await db.doc(FirestorePaths.orderDoc('o1')).get()).data()!['status'], 'pending');
    });

    testWidgets('the status filter narrows the list', (tester) async {
      final db = FakeFirebaseFirestore();
      await seed(db, 'o1', orderMap());
      await seed(db, 'o2', orderMap(number: 'GG-2610-00002', status: OrderStatus.delivered, createdAt: DateTime(2026, 10, 19)));
      await pumpAdminScreen(tester, const OrdersScreen(), db: db);

      await tester.tap(find.text('All status'));
      await settle(tester);
      await tester.tap(find.text('Delivered').last);
      await settle(tester);
      expect(find.text('GG-2610-00001'), findsNothing);
      expect(find.text('GG-2610-00002'), findsOneWidget);
    });

    testWidgets('renders in dark mode and wide layouts without errors', (tester) async {
      final db = FakeFirebaseFirestore();
      await seed(db, 'o1', orderMap(isGift: true, giftMessage: 'Love you', hidePrices: true));
      final errors = await errorsOutsideCoreNav(() async {
        await pumpAdminScreen(tester, const OrdersScreen(), db: db, mode: ThemeMode.dark, size: const Size(1440, 1000));
        await tester.tap(find.text('GG-2610-00001'));
        await settle(tester);
        expect(find.text('Print packing slip'), findsOneWidget);
        expect(find.text('Love you'), findsOneWidget);
      });
      expect(errors, isEmpty);
    });
  });
}
