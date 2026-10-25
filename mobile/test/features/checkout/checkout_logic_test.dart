import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/addresses/data/address_repository.dart';
import 'package:golden_gift/features/cart/presentation/providers/cart_lines.dart';
import 'package:golden_gift/features/checkout/domain/checkout_rules.dart';
import 'package:golden_gift/features/notifications/data/notifications_repository.dart';
import 'package:golden_gift/features/orders/data/orders_repository.dart';
import 'package:golden_gift/models/address_model.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

AddressModel _address(String label, {bool isDefault = false}) => AddressModel(
      id: '',
      label: label,
      name: 'Sara',
      phone: '7501234567',
      city: 'erbil',
      area: 'Ankawa',
      street: '100m Rd',
      isDefault: isDefault,
    );

void main() {
  group('earliest delivery date (SRS §5.11)', () {
    test('same-day products before the cut-off → today', () {
      expect(
        CheckoutRules.earliestDeliveryDate(now: DateTime(2026, 10, 21, 9, 30), maxPreparationDays: 0, sameDayCutoff: '14:00'),
        DateTime(2026, 10, 21),
      );
    });
    test('after the cut-off → +1 day', () {
      expect(
        CheckoutRules.earliestDeliveryDate(now: DateTime(2026, 10, 21, 14, 0), maxPreparationDays: 0, sameDayCutoff: '14:00'),
        DateTime(2026, 10, 22),
      );
    });
    test('preparation days add up, across month ends', () {
      expect(
        CheckoutRules.earliestDeliveryDate(now: DateTime(2026, 10, 30, 20), maxPreparationDays: 2, sameDayCutoff: '14:00'),
        DateTime(2026, 11, 2),
      );
    });
    test('a malformed cut-off falls back to 14:00', () {
      expect(CheckoutRules.parseHm('25:00'), isNull);
      expect(
        CheckoutRules.earliestDeliveryDate(now: DateTime(2026, 10, 21, 15), maxPreparationDays: 0, sameDayCutoff: 'x'),
        DateTime(2026, 10, 22),
      );
    });
  });

  test('dates offered and today’s remaining slots', () {
    final dates = CheckoutRules.deliveryDates(DateTime(2026, 10, 30), count: 3);
    expect(dates, [DateTime(2026, 10, 30), DateTime(2026, 10, 31), DateTime(2026, 11, 1)]);
    final now = DateTime(2026, 10, 21, 15, 10);
    expect(CheckoutRules.availableSlots(DateTime(2026, 10, 21), now, DeliverySlot.defaults).map((s) => s.id), ['evening']);
    expect(CheckoutRules.availableSlots(DateTime(2026, 10, 22), now, DeliverySlot.defaults).length, 3);
  });

  test('city conflicts list only lines restricted elsewhere (SRS §4.3)', () {
    CartItemModel item(String id, String product) =>
        CartItemModel(id: id, productId: product, storeId: 's', titleSnapshot: LocalizedText(product), unitPrice: 1000, qty: 1);
    final products = {
      'box': const ProductModel(id: 'box', title: LocalizedText('Box'), storeId: 's', price: 1000, availableCities: ['erbil', 'duhok']),
      'mug': const ProductModel(id: 'mug', title: LocalizedText('Mug'), storeId: 's', price: 1000),
    };
    final summary = summarize([item('a', 'box'), item('b', 'mug')], products);
    expect(CheckoutRules.cityConflicts(summary, products, 'erbil'), isEmpty);
    expect(CheckoutRules.cityConflicts(summary, products, 'baghdad').map((l) => l.item.id), ['a']);
  });

  group('totals', () {
    test('delivery is added; credits are used before wallet (SRS §5.18)', () {
      final t = CheckoutRules.totals(subtotal: 50000, deliveryFee: 3000, discount: 5000, credits: 10000, wallet: 100000);
      expect(t.discount, 5000);
      expect(t.creditsUsed, 10000);
      expect(t.walletUsed, 38000);
      expect(t.total, 0);
    });
    test('never negative; discount capped at the subtotal', () {
      final t = CheckoutRules.totals(subtotal: 10000, deliveryFee: 3000, discount: 20000);
      expect(t.discount, 10000);
      expect(t.total, 3000);
    });
    test('minimum order', () {
      expect(CheckoutRules.meetsMinimum(9000, 10000), isFalse);
      expect(CheckoutRules.meetsMinimum(9000, 0), isTrue);
    });
  });

  group('addresses: always exactly one default (SRS §5.20)', () {
    test('first address becomes the default; a new default clears the old one', () async {
      final db = FakeFirebaseFirestore();
      final repo = AddressRepository(db);
      final home = await repo.save('u1', _address('Home'));
      expect(home.isDefault, isTrue);
      final work = await repo.save('u1', _address('Work', isDefault: true));
      final list = await repo.watch('u1').first;
      expect(list.where((a) => a.isDefault).map((a) => a.id), [work.id]);
      expect(list.first.id, work.id); // default first
      await repo.setDefault('u1', home.id);
      expect((await repo.watch('u1').first).where((a) => a.isDefault).single.id, home.id);
    });

    test('deleting the default promotes another one', () async {
      final db = FakeFirebaseFirestore();
      final repo = AddressRepository(db);
      final home = await repo.save('u1', _address('Home'));
      final work = await repo.save('u1', _address('Work'));
      await repo.delete('u1', home.id);
      final list = await repo.watch('u1').first;
      expect(list.single.id, work.id);
      expect(list.single.isDefault, isTrue);
    });
  });

  group('orders', () {
    test('placeOrder payload: date only, trimmed gift message, never prices', () {
      final map = PlaceOrderRequest(
        clientRequestId: 'r1',
        addressId: 'a1',
        deliveryDate: DateTime(2026, 11, 2),
        deliverySlot: 'evening',
        isGift: true,
        giftMessage: '  Happy birthday  ',
        hidePrices: true,
      ).toMap();
      expect(map['deliveryDate'], '2026-11-02');
      expect(map['giftMessage'], 'Happy birthday');
      expect(map['paymentMethod'], 'cashOnDelivery');
      expect(map.keys, isNot(contains('total')));
    });

    test('server refusals map to reasons the UI can explain', () {
      OrderFailureReason map(String code, [Map<String, dynamic>? details]) =>
          OrderFailure.from(FirebaseFunctionsException(code: code, message: 'x', details: details)).reason;
      expect(map('failed-precondition', {'reason': 'city_not_allowed', 'productIds': ['box']}), OrderFailureReason.cityNotAllowed);
      expect(map('failed-precondition', {'reason': 'out_of_stock'}), OrderFailureReason.outOfStock);
      expect(map('failed-precondition', {'reason': 'min_order'}), OrderFailureReason.minimumNotMet);
      expect(map('failed-precondition', {'reason': 'not_cancellable'}), OrderFailureReason.notCancellable);
      expect(map('not-found'), OrderFailureReason.unavailable); // function not deployed
      expect(OrderFailure.from(FirebaseFunctionsException(code: 'failed-precondition', message: 'x',
          details: const {'reason': 'cart_changed', 'productIds': ['p1']})).productIds, ['p1']);
    });

    test('status → tab, and who may cancel (SRS §5.12)', () {
      expect(OrderStatus.outForDelivery.tab, OrderTab.active);
      expect(OrderStatus.delivered.tab, OrderTab.completed);
      expect(OrderStatus.refunded.tab, OrderTab.cancelled);
      expect(OrderStatus.confirmed.customerCanCancel, isTrue);
      expect(OrderStatus.preparing.customerCanCancel, isFalse);
    });

    test('order parses items with their own status and the address snapshot', () {
      final o = OrderModel.fromMap('o1', {
        'orderNumber': 'GG-2610-00001',
        'userId': 'u1',
        'subtotal': 80000,
        'deliveryFee': 3000,
        'total': 83000,
        'status': 'preparing',
        'address': _address('Home').toMap(),
        'deliveryDate': '2026-11-02',
        'items': [
          {'id': 'l1', 'productId': 'frame', 'storeId': 's1', 'titleSnapshot': 'Frame', 'unitPrice': 40000, 'qty': 2, 'status': 'preparing'},
        ],
      });
      expect(o.items.single.line.qty, 2);
      expect(o.items.single.status, OrderStatus.preparing);
      expect(o.address!.area, 'Ankawa');
      expect(o.deliveryDate, DateTime(2026, 11, 2));
      expect(o.itemCount, 2);
    });
  });

  group('notifications (SRS §5.5)', () {
    test('own + broadcast docs; broadcasts are read / hidden only on this device', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = FakeFirebaseFirestore();
      await db.collection('notifications').doc('n1').set({'userId': 'u1', 'title': 'Order confirmed', 'body': 'b', 'isRead': false, 'createdAt': DateTime(2026, 10, 21, 10), 'data': {'route': '/orders/o1'}});
      await db.collection('notifications').doc('b1').set({'userId': 'all', 'title': 'Sale!', 'body': 'b', 'isRead': false, 'createdAt': DateTime(2026, 10, 21, 11)});
      await db.collection('notifications').doc('x1').set({'userId': 'someone-else', 'title': 'x', 'body': 'b', 'isRead': false, 'createdAt': DateTime(2026, 10, 21, 12)});
      final repo = NotificationsRepository(db, prefs);

      var list = await repo.watch('u1').first;
      expect(list.map((n) => n.id), ['b1', 'n1']);
      expect(list.last.route, '/orders/o1');

      await repo.markAllRead(list);
      list = await repo.watch('u1').first;
      expect(list.every((n) => n.isRead), isTrue);
      expect((await db.doc('notifications/b1').get()).data()!['isRead'], isFalse); // shared doc untouched

      await repo.remove(list.first); // broadcast → hidden locally
      await repo.remove(list.last); // own → deleted
      expect(await repo.watch('u1').first, isEmpty);
      expect((await db.doc('notifications/b1').get()).exists, isTrue);
      expect((await db.doc('notifications/n1').get()).exists, isFalse);
    });
  });
}
