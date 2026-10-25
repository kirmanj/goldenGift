import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/orders/data/orders_repository.dart';
import 'package:golden_gift/features/orders/presentation/widgets/order_timeline.dart';
import 'package:golden_gift/models/order_model.dart';

import '../checkout/phase6_test_harness.dart';

final _en = l10nFor('en');

const _photoLine = {
  'id': 'l1',
  'productId': 'frame',
  'storeId': 's1',
  'titleSnapshot': 'Photo Frame',
  'unitPrice': 40000,
  'qty': 1,
  'status': 'preparing',
  'selections': [
    {
      'groupId': 'frame',
      'type': 'imageVariant',
      'label': 'Frame',
      'valueId': 'walnut',
      'valueLabel': 'Walnut',
      'priceDelta': 5000
    },
    {'groupId': 'text1', 'type': 'text', 'label': 'Text', 'text': 'Happy B-day'},
    {
      'groupId': 'photos',
      'type': 'photoUpload',
      'label': 'Photos',
      'urls': ['', '']
    },
  ],
};

const _mugLine = {
  'id': 'l2',
  'productId': 'mug',
  'storeId': 's2',
  'titleSnapshot': 'Photo Mug',
  'unitPrice': 15000,
  'qty': 2,
  'status': 'readyForDelivery',
};

Future<FakeFirebaseFirestore> _seed(String status,
    {List<(String, String?)> history = const [], Map<String, dynamic> extra = const {}}) async {
  final db = FakeFirebaseFirestore();
  await seedOrder(db, 'o1', status: status, number: 'GG-2610-00007', items: [_photoLine, _mugLine], extra: extra);
  var minute = 0;
  for (final (s, note) in history) {
    await db.collection('orders/o1/status_history').add({
      'status': s,
      'note': note,
      'at': DateTime(2026, 10, 20, 12, minute++),
    });
  }
  return db;
}

Future<Phase6Harness> _pump(WidgetTester tester, FakeFirebaseFirestore db,
        {String locale = 'en',
        ThemeMode mode = ThemeMode.light,
        Size size = const Size(390, 3200),
        double scale = 1}) =>
    pumpPhase6(tester,
        initialPath: AppRoutes.order('o1'),
        firestore: db,
        locale: locale,
        themeMode: mode,
        size: size,
        textScale: scale);

void main() {
  group('timeline (status_history)', () {
    testWidgets('flow steps with done / current / upcoming markers, times and notes', (tester) async {
      await _pump(
          tester,
          await _seed('preparing',
              history: [('pending', null), ('confirmed', 'Called the customer'), ('preparing', null)]));
      expect(find.byKey(const ValueKey('timeline-pending-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-confirmed-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-preparing-current')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-readyForDelivery-upcoming')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-delivered-upcoming')), findsOneWidget);
      expect(find.text('Called the customer'), findsOneWidget);
      expect(find.text('20/10/2026 12:01'), findsOneWidget);
    });

    test('an order that left the flow shows the reached steps, then the stop', () {
      const order = OrderModel(
        id: 'o1',
        orderNumber: 'GG',
        userId: 'u1',
        subtotal: 0,
        total: 0,
        status: OrderStatus.refunded,
        cancelReason: 'Changed my mind',
      );
      final steps = orderTimeline(order, const [
        StatusHistoryEntry(status: OrderStatus.pending),
        StatusHistoryEntry(status: OrderStatus.confirmed),
        StatusHistoryEntry(status: OrderStatus.cancelledByBuyer),
        StatusHistoryEntry(status: OrderStatus.refunded),
      ]);
      expect(steps.map((s) => (s.status, s.mark)), [
        (OrderStatus.pending, TimelineMark.done),
        (OrderStatus.confirmed, TimelineMark.done),
        (OrderStatus.cancelledByBuyer, TimelineMark.stopped),
        (OrderStatus.refunded, TimelineMark.stopped),
      ]);
      expect(steps[2].note, 'Changed my mind');
    });

    test('delivered → every step done', () {
      const order =
          OrderModel(id: 'o', orderNumber: '', userId: '', subtotal: 0, total: 0, status: OrderStatus.delivered);
      expect(orderTimeline(order, const []).every((s) => s.mark == TimelineMark.done), isTrue);
    });

    testWidgets('a cancelled order shows the cancellation and its reason', (tester) async {
      await _pump(
        tester,
        await _seed('cancelledByBuyer',
            history: [('pending', null), ('cancelledByBuyer', null)], extra: {'cancelReason': 'Wrong size'}),
      );
      expect(find.byKey(const ValueKey('timeline-cancelledByBuyer-stopped')), findsOneWidget);
      expect(find.text('Wrong size'), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-delivered-upcoming')), findsNothing);
    });
  });

  testWidgets('items show personalization, per-line status and photos (full-screen viewer)', (tester) async {
    await _pump(tester, await _seed('preparing'));
    expect(find.text('Photo Frame'), findsOneWidget);
    expect(find.text('Frame: Walnut · Text: Happy B-day · ${_en.photosCount(2)}'), findsOneWidget);
    expect(find.text('2 × 15,000 IQD'), findsOneWidget);
    // l2 is further along than the order → its own chip.
    expect(find.byKey(const ValueKey('status-chip-readyForDelivery')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-photo-l1-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('order-photo-l1-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-viewer')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('photo-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-viewer')), findsNothing);
  });

  testWidgets('address, delivery, gift message, payment and totals', (tester) async {
    await _pump(
      tester,
      await _seed('pending', extra: {
        'isGift': true,
        'giftMessage': 'Love you mum',
        'discount': 3000,
        'creditsUsed': 2000,
        'total': 70000,
      }),
    );
    expect(find.text('Sara Ahmed'), findsOneWidget);
    expect(find.text('+964 750 123 4567'), findsOneWidget);
    expect(find.text('Erbil'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('order-delivery-when'))).data, contains('22/10/2026'));
    expect(find.text('Love you mum'), findsOneWidget);
    expect(find.text(_en.cashOnDelivery), findsOneWidget);
    expect(find.text(_en.paymentStatusPending), findsOneWidget);
    expect(find.text('−3,000 IQD'), findsOneWidget);
    expect(find.text('−2,000 IQD'), findsOneWidget);
    expect(find.text('70,000 IQD'), findsWidgets);
  });

  group('cancel (SRS §5.12)', () {
    for (final (status, visible) in [
      ('pending', true),
      ('confirmed', true),
      ('preparing', false),
      ('delivered', false),
      ('cancelledByBuyer', false),
    ]) {
      testWidgets('$status → Cancel ${visible ? 'shown' : 'hidden'}', (tester) async {
        await _pump(tester, await _seed(status));
        expect(find.byKey(const ValueKey('cancel-order')), visible ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('confirm with a reason → cancelOrder → "Order cancelled"', (tester) async {
      final h = await _pump(tester, await _seed('pending'));
      await tester.tap(find.byKey(const ValueKey('cancel-order')));
      await tester.pumpAndSettle();
      expect(find.text(_en.cancelOrderConfirm), findsOneWidget);
      await tester.enterText(
          find.descendant(of: find.byKey(const ValueKey('cancel-reason')), matching: find.byType(TextField)),
          ' Too late ');
      await tester.tap(find.byKey(const ValueKey('cancel-dialog-confirm')));
      await tester.pumpAndSettle();
      expect(h.orders.cancelCalls, [('o1', 'Too late')]);
      expect(find.text(_en.orderCancelled), findsOneWidget);
    });

    testWidgets('closing the dialog does not cancel', (tester) async {
      final h = await _pump(tester, await _seed('pending'));
      await tester.tap(find.byKey(const ValueKey('cancel-order')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancel-dialog-close')));
      await tester.pumpAndSettle();
      expect(h.orders.cancelCalls, isEmpty);
    });

    testWidgets('notCancellable → "can no longer be cancelled"', (tester) async {
      final h = await _pump(tester, await _seed('confirmed'));
      h.orders.cancelError = const OrderFailure(OrderFailureReason.notCancellable);
      await tester.tap(find.byKey(const ValueKey('cancel-order')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancel-dialog-confirm')));
      await tester.pumpAndSettle();
      expect(h.orders.cancelCalls, [('o1', null)]);
      expect(find.text(_en.orderNotCancellable), findsOneWidget);
    });
  });

  testWidgets('Reorder adds every line with a new id, then opens the cart', (tester) async {
    final h = await _pump(tester, await _seed('delivered'));
    await tester.tap(find.byKey(const ValueKey('reorder')));
    await tester.pumpAndSettle();
    final lines = h.cart.items.values.toList();
    expect(lines.map((l) => l.productId).toSet(), {'frame', 'mug'});
    expect(lines.map((l) => l.id), everyElement(isNot(anyOf('l1', 'l2'))));
    expect(lines.firstWhere((l) => l.productId == 'mug').qty, 2);
    expect(
        lines.firstWhere((l) => l.productId == 'frame').selections.map((s) => s.groupId), ['frame', 'text1', 'photos']);
    expect(find.text(_en.reorderAdded), findsOneWidget);
    expect(find.text('main tab 1'), findsOneWidget);
  });

  testWidgets('Contact support opens Contact Us', (tester) async {
    final h = await _pump(tester, await _seed('delivered'));
    await tester.tap(find.byKey(const ValueKey('contact-support')));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.contactUs);
  });

  testWidgets('guests see the sign-in card', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), guest: true);
    expect(find.byKey(const ValueKey('guest-sign-in-card')), findsOneWidget);
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [
      ('ar', ThemeMode.light),
      ('ar', ThemeMode.dark),
      ('ckb', ThemeMode.light),
      ('ckb', ThemeMode.dark)
    ]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await _pump(tester, await _seed('confirmed', history: [('pending', null), ('confirmed', 'ok')]),
            locale: locale, mode: mode);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('320 px, 1.3× text', (tester) async {
      await _pump(tester,
          await _seed('cancelledBySeller', history: [('pending', null), ('cancelledBySeller', 'Out of walnut')]),
          locale: 'ckb', size: const Size(320, 4000), scale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });
}
