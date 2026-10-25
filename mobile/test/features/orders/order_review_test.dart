import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/orders/presentation/widgets/order_review_action.dart';
import 'package:golden_gift/models/order_model.dart';

import '../checkout/phase6_test_harness.dart';

final _en = l10nFor('en');

Map<String, dynamic> _line(String id, String productId, {String status = 'delivered'}) => {
      'id': id,
      'productId': productId,
      'storeId': 's1',
      'titleSnapshot': productId == 'frame' ? 'Photo Frame' : 'Photo Mug',
      'unitPrice': 15000,
      'qty': 1,
      'status': status,
    };

Future<FakeFirebaseFirestore> _order(String status, {List<Map<String, dynamic>>? items, String type = 'standard'}) async {
  final db = FakeFirebaseFirestore();
  await seedOrder(
    db,
    'o1',
    status: status,
    items: items ?? [_line('l1', 'frame', status: status), _line('l2', 'mug', status: status)],
    extra: {'orderType': type},
  );
  return db;
}

Future<void> _myReview(FakeFirebaseFirestore db, String productId, {required bool approved, int rating = 4}) =>
    db.doc('products/$productId/reviews/o1_u1').set({
      'productId': productId,
      'userId': 'u1',
      'userName': 'Sara',
      'storeId': 's1',
      'rating': rating,
      'text': 'Lovely',
      'images': const <String>[],
      'orderId': 'o1',
      'isApproved': approved,
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 20)),
    });

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('which lines can be rated', () {
    OrderModel order(OrderStatus status, List<(String, String, OrderStatus)> lines,
            {OrderType type = OrderType.standard}) =>
        OrderModel.fromMap('o1', {
          'orderNumber': 'GG',
          'userId': 'u1',
          'subtotal': 0,
          'total': 0,
          'status': status.name,
          'orderType': type.name,
          'items': [
            for (final (id, product, s) in lines) _line(id, product, status: s.name),
          ],
        });

    test('delivered lines, one per product, standard orders only', () {
      expect(
          reviewableLineIds(order(OrderStatus.delivered, [
            ('l1', 'frame', OrderStatus.delivered),
            ('l2', 'frame', OrderStatus.delivered),
            ('l3', 'mug', OrderStatus.delivered),
          ])),
          {'l1', 'l3'});
      // Multi-vendor: only the delivered line while the order is still moving.
      expect(
          reviewableLineIds(order(OrderStatus.outForDelivery, [
            ('l1', 'frame', OrderStatus.delivered),
            ('l2', 'mug', OrderStatus.outForDelivery),
          ])),
          {'l1'});
      expect(reviewableLineIds(order(OrderStatus.preparing, [('l1', 'frame', OrderStatus.preparing)])), isEmpty);
      expect(
          reviewableLineIds(
              order(OrderStatus.delivered, [('l1', 'card', OrderStatus.delivered)], type: OrderType.giftCard)),
          isEmpty);
    });
  });

  testWidgets('not delivered → no Rate', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: await _order('preparing'));
    expect(find.byKey(const ValueKey('rate-l1')), findsNothing);
  });

  testWidgets('delivered → Rate per product → form → pending approval', (tester) async {
    final h = await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: await _order('delivered'));
    expect(find.byKey(const ValueKey('rate-l1')), findsOneWidget);
    expect(find.byKey(const ValueKey('rate-l2')), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('rate-l1')));
    expect(find.text(_en.reviewFormTitle), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('review-form')), matching: find.text('Photo Frame')),
        findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('review-star-5')));
    await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('review-text')), matching: find.byType(TextField)), 'Perfect');
    await _tap(tester, find.byKey(const ValueKey('review-submit')));

    final doc = (await h.firestore.doc('products/frame/reviews/o1_u1').get()).data()!;
    expect(doc['rating'], 5);
    expect(doc['text'], 'Perfect');
    expect(doc['orderId'], 'o1');
    expect(doc['storeId'], 's1');
    expect(doc['isApproved'], isFalse);
    expect(find.text(_en.reviewThanks), findsWidgets);
    expect(find.byKey(const ValueKey('rate-l1')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('review-status-l1')), matching: find.text(_en.reviewPending)),
        findsOneWidget);
    // The other product can still be rated.
    expect(find.byKey(const ValueKey('rate-l2')), findsOneWidget);
  });

  testWidgets('an existing review hides Rate: pending / Reviewed, and Edit warns about moderation', (tester) async {
    final db = await _order('delivered');
    await _myReview(db, 'frame', approved: false);
    await _myReview(db, 'mug', approved: true, rating: 3);
    await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: db);
    expect(find.byKey(const ValueKey('rate-l1')), findsNothing);
    expect(find.byKey(const ValueKey('rate-l2')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('review-status-l1')), matching: find.text(_en.reviewPending)),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('review-status-l2')), matching: find.text(_en.reviewReviewed)),
        findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('edit-review-l2')));
    expect(find.byKey(const ValueKey('review-edit-warning')), findsOneWidget);
    expect(
        tester
            .widget<TextField>(
                find.descendant(of: find.byKey(const ValueKey('review-text')), matching: find.byType(TextField)))
            .controller!
            .text,
        'Lovely');
  });

  testWidgets('a gift-card order has nothing to rate', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: await _order('delivered', type: 'giftCard'));
    expect(find.byKey(const ValueKey('rate-l1')), findsNothing);
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light)]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        final db = await _order('delivered');
        await _myReview(db, 'mug', approved: false);
        await pumpPhase6(tester, initialPath: AppRoutes.order('o1'), firestore: db, locale: locale, themeMode: mode);
        expect(find.text(l10nFor(locale).reviewRate), findsOneWidget);
        expect(find.text(l10nFor(locale).reviewPending), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    for (final locale in ['en', 'ar', 'ckb']) {
      testWidgets('320 px, 1.3× text ($locale)', (tester) async {
        final db = await _order('delivered');
        await _myReview(db, 'mug', approved: true);
        await pumpPhase6(tester,
            initialPath: AppRoutes.order('o1'),
            firestore: db,
            locale: locale,
            size: const Size(320, 4000),
            textScale: 1.3);
        await _tap(tester, find.byKey(const ValueKey('rate-l1')));
        await _tap(tester, find.byKey(const ValueKey('review-submit')));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
