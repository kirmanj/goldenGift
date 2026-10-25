import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/orders/data/orders_repository.dart';
import 'package:golden_gift/features/payments/presentation/screens/payment_status_screen.dart';
import 'package:golden_gift/models/app_settings_model.dart';

import '../checkout/phase6_test_harness.dart';
import 'payments_test_harness.dart';

final _en = l10nFor('en');
const _placeKey = ValueKey('place-order');
const _zainCash = PaymentSettings(zainCash: true);

final _products = {'box': testProduct('box'), 'mug': testProduct('mug')};
final _lines = [testLine('l1', 'box'), testLine('l2', 'mug')];

typedef _Pumped = (Phase6Harness, FakePaymentCalls);

/// Checkout with ZainCash on; `orders/o-new` is what `placeOrder` creates.
Future<_Pumped> _pumpCheckout(
  WidgetTester tester, {
  PaymentSettings payments = _zainCash,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 2400),
  double textScale = 1,
  Future<void> Function(FakeFirebaseFirestore db)? seed,
}) async {
  final db = FakeFirebaseFirestore();
  await seedAddress(db, testAddress('a1', isDefault: true));
  await seedOrder(db, 'o-new', number: 'GG-2610-00042', extra: zainCashOrderExtra());
  await seed?.call(db);
  final calls = FakePaymentCalls(db);
  final h = await pumpPhase6(
    tester,
    initialPath: AppRoutes.checkout,
    firestore: db,
    cartItems: _lines,
    cartProducts: _products,
    payments: payments,
    now: payNow,
    locale: locale,
    themeMode: themeMode,
    size: size,
    textScale: textScale,
    overrides: paymentOverrides(calls),
    extraRoutes: paymentRoutes,
  );
  return (h, calls);
}

Future<void> _payWithZainCash(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(const ValueKey('payment-zainCash')), 200,
      scrollable:
          find.descendant(of: find.byKey(const ValueKey('checkout-list')), matching: find.byType(Scrollable)).first);
  await tester.ensureVisible(find.byKey(const ValueKey('payment-zainCash')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('payment-zainCash')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_placeKey));
  await tester.pumpAndSettle();
}

/// Order details of a seeded order (pushed on top of /orders).
Future<_Pumped> _pumpOrder(
  WidgetTester tester, {
  required Map<String, dynamic> extra,
  String status = 'pending',
  DateTime? now,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 2400),
  double textScale = 1,
  Future<void> Function(FakeFirebaseFirestore db)? seed,
}) async {
  final db = FakeFirebaseFirestore();
  await seedOrder(db, 'o1', number: 'GG-2610-00042', status: status, extra: extra);
  await seed?.call(db);
  final calls = FakePaymentCalls(db);
  final h = await pumpPhase6(
    tester,
    initialPath: AppRoutes.order('o1'),
    firestore: db,
    payments: _zainCash,
    locale: locale,
    themeMode: themeMode,
    size: size,
    textScale: textScale,
    overrides: paymentOverrides(calls, now: now),
    extraRoutes: paymentRoutes,
  );
  return (h, calls);
}

Future<_Pumped> _pumpWallet(
  WidgetTester tester, {
  PaymentSettings payments = _zainCash,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 2400),
  double textScale = 1,
}) async {
  final db = FakeFirebaseFirestore();
  await db.doc(FirestorePaths.walletDoc('u1')).set({'balance': 12000, 'credits': 0, 'currency': 'IQD'});
  final calls = FakePaymentCalls(db);
  final h = await pumpPhase6(
    tester,
    initialPath: AppRoutes.wallet,
    firestore: db,
    payments: payments,
    locale: locale,
    themeMode: themeMode,
    size: size,
    textScale: textScale,
    overrides: paymentOverrides(calls),
    extraRoutes: paymentRoutes,
  );
  return (h, calls);
}

String _viewTitle(WidgetTester tester, PaymentView view) =>
    tester.widget<Text>(find.byKey(ValueKey('payment-view-${view.name}'))).data!;

void main() {
  group('checkout with ZainCash (SRS §5.11)', () {
    testWidgets('ZainCash is a usable method when enabled; card stays disabled', (tester) async {
      await _pumpCheckout(tester, payments: const PaymentSettings(zainCash: true, card: true));
      final zain = tester.widget<RadioListTile<PaymentMethod>>(find.byKey(const ValueKey('payment-zainCash')));
      final card = tester.widget<RadioListTile<PaymentMethod>>(find.byKey(const ValueKey('payment-card')));
      expect(zain.enabled, isNot(false));
      expect(card.enabled, isFalse);
      expect(find.text(_en.paymentZainCash), findsOneWidget);
      expect(find.text(_en.paymentZainCashHint), findsOneWidget);
    });

    testWidgets('hidden while app_settings/payments.zainCash is off', (tester) async {
      await _pumpCheckout(tester, payments: const PaymentSettings());
      expect(find.byKey(const ValueKey('payment-zainCash')), findsNothing);
    });

    testWidgets('Place order → placeOrder → createPaymentSession(order) → ZainCash page → status page → paid',
        (tester) async {
      final (h, calls) = await _pumpCheckout(tester);
      await _payWithZainCash(tester);

      final request = h.orders.placeRequests.single;
      expect(request.paymentMethod, PaymentMethod.zainCash);
      expect(request.useWallet, isFalse);
      expect(request.toMap()['paymentMethod'], 'zainCash');
      expect(calls.calls.single, {'purpose': 'order', 'orderId': 'o-new'});
      expect(h.openedLinks, [Uri.parse(testPayUrl)]);
      expect(h.location, AppRoutes.paymentFor('ps1'));

      // Waiting: amount, order, time left, the three actions.
      expect(_viewTitle(tester, PaymentView.waiting), _en.paymentWaitingTitle);
      expect(find.byKey(const ValueKey('payment-amount')), findsOneWidget);
      expect(find.text('75,000 IQD'), findsOneWidget);
      expect(find.text(_en.orderNumber('GG-2610-00042')), findsOneWidget);
      expect(find.textContaining('30:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-open-again')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-check-status')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-cancel')), findsOneWidget);
      // Not a purchase until the money arrives.
      expect(h.analytics.events.containsKey('purchase'), isFalse);

      await tester.tap(find.byKey(const ValueKey('payment-open-again')));
      await tester.pumpAndSettle();
      expect(h.openedLinks, hasLength(2));

      await tester.tap(find.byKey(const ValueKey('payment-check-status')));
      await tester.pumpAndSettle();
      expect(find.text(_en.paymentStillPending), findsOneWidget);

      await settleSession(h.firestore, 'ps1', 'paid', orderId: 'o-new');
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.orderSuccessFor('o-new'));
      expect(h.analytics.events['purchase']?['transaction_id'], 'GG-2610-00042');
    });

    testWidgets('failed: the order was cancelled → explanation; Try again puts the lines back in the cart',
        (tester) async {
      final (h, _) = await _pumpCheckout(tester);
      await _payWithZainCash(tester);
      expect(h.cart.items, isEmpty);

      await settleSession(h.firestore, 'ps1', 'failed', orderId: 'o-new', cancelReason: 'payment_failed');
      await tester.pumpAndSettle();
      expect(_viewTitle(tester, PaymentView.failed), _en.paymentFailedTitle);
      expect(find.text(_en.paymentOrderCancelledBody('GG-2610-00042')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-open-again')), findsNothing);
      expect(find.byKey(const ValueKey('payment-order-details')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('payment-try-again')));
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.mainTab(1));
      expect(h.cart.items.values.map((l) => l.productId), unorderedEquals(['box']));
      expect(h.cart.items.values.single.qty, 2);
    });

    testWidgets('expired: "Time to pay ran out"; Order details opens the order', (tester) async {
      final (h, _) = await _pumpCheckout(tester);
      await _payWithZainCash(tester);
      await settleSession(h.firestore, 'ps1', 'expired', orderId: 'o-new', cancelReason: 'payment_expired');
      await tester.pumpAndSettle();
      expect(_viewTitle(tester, PaymentView.expired), _en.paymentExpiredTitle);
      await tester.tap(find.byKey(const ValueKey('payment-order-details')));
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.order('o-new'));
    });

    testWidgets('Cancel leaves for Order details; nothing is cancelled', (tester) async {
      final (h, _) = await _pumpCheckout(tester);
      await _payWithZainCash(tester);
      await tester.tap(find.byKey(const ValueKey('payment-cancel')));
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.order('o-new'));
      expect(h.orders.cancelCalls, isEmpty);
      expect(find.byKey(const ValueKey('pay-now')), findsOneWidget);
    });

    testWidgets('a retry after a failed placeOrder reuses the same clientRequestId', (tester) async {
      final (h, calls) = await _pumpCheckout(tester);
      h.orders.placeResults.add(const OrderFailure(OrderFailureReason.network));
      await _payWithZainCash(tester);
      expect(find.text(_en.somethingWentWrong), findsOneWidget);
      expect(calls.calls, isEmpty);
      expect(h.location, AppRoutes.checkout);

      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      expect(h.orders.placeRequests, hasLength(2));
      expect(h.orders.placeRequests[1].clientRequestId, h.orders.placeRequests[0].clientRequestId);
      expect(calls.calls.single, {'purpose': 'order', 'orderId': 'o-new'});
      expect(h.location, AppRoutes.paymentFor('ps1'));
    });

    testWidgets('session can\'t start (gateway down) → Order details with "pay later" message', (tester) async {
      final (h, calls) = await _pumpCheckout(tester);
      calls.results.add(FirebaseFunctionsException(code: 'unavailable', message: 'Online payment is not available'));
      await _payWithZainCash(tester);
      expect(h.location, AppRoutes.order('o-new'));
      expect(find.text('${_en.paymentErrorUnavailable} ${_en.paymentOrderSaved}'), findsOneWidget);
      expect(h.openedLinks, isEmpty);
      expect(find.byKey(const ValueKey('pay-now')), findsOneWidget);
    });

    testWidgets('credits + ZainCash: below 1,000 IQD left to pay → message, Place order disabled', (tester) async {
      await _pumpCheckout(tester, seed: (db) async {
        await db.doc(FirestorePaths.walletDoc('u1')).set({'balance': 0, 'credits': 74500, 'currency': 'IQD'});
      });
      await tester.tap(find.byKey(const ValueKey('payment-zainCash')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gateway-minimum')), findsOneWidget);
      expect(find.text(_en.zainCashMinimum('1,000 IQD')), findsOneWidget);
      expect(primaryButton(tester, _placeKey).onPressed, isNull);
    });

    testWidgets('credits + ZainCash: credits first, ZainCash pays the rest', (tester) async {
      final (h, _) = await _pumpCheckout(tester, seed: (db) async {
        await db.doc(FirestorePaths.walletDoc('u1')).set({'balance': 0, 'credits': 5000, 'currency': 'IQD'});
      });
      await tester.tap(find.byKey(const ValueKey('payment-zainCash')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gateway-minimum')), findsNothing);
      expect(find.text('70,000 IQD'), findsWidgets);
      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      expect(h.orders.placeRequests.single.useCredits, isTrue);
      expect(h.orders.placeRequests.single.paymentMethod, PaymentMethod.zainCash);
    });
  });

  group('payment status page', () {
    testWidgets('a late payment for a cancelled order says it went to the wallet', (tester) async {
      final (h, _) = await _pumpCheckout(tester);
      await _payWithZainCash(tester);
      await settleSession(h.firestore, 'ps1', 'paid', orderId: 'o-new', creditedToWallet: true);
      await tester.pumpAndSettle();
      expect(_viewTitle(tester, PaymentView.paidToWallet), _en.paymentLateCreditedTitle);
      expect(find.text(_en.paymentLateCreditedBody('75,000 IQD')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('payment-my-wallet')));
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.wallet);
    });

    testWidgets('time up while still pending: no "Open ZainCash again", still checkable', (tester) async {
      final db = FakeFirebaseFirestore();
      final calls = FakePaymentCalls(db);
      await seedOrder(db, 'o1', number: 'GG-2610-00042', extra: zainCashOrderExtra());
      await calls.call('createPaymentSession', {'purpose': 'order', 'orderId': 'o1'});
      await pumpPhase6(
        tester,
        initialPath: AppRoutes.paymentFor('ps1'),
        firestore: db,
        overrides: paymentOverrides(calls, now: payDue.add(const Duration(minutes: 1))),
        extraRoutes: paymentRoutes,
      );
      expect(_viewTitle(tester, PaymentView.timeUp), _en.paymentWaitingTitle);
      expect(find.text(_en.paymentTimeUp), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-open-again')), findsNothing);
      expect(find.byKey(const ValueKey('payment-check-status')), findsOneWidget);
    });

    testWidgets('unknown session → "We couldn\'t find this payment" + Orders', (tester) async {
      final db = FakeFirebaseFirestore();
      final h = await pumpPhase6(
        tester,
        initialPath: AppRoutes.paymentFor('nope'),
        firestore: db,
        overrides: paymentOverrides(FakePaymentCalls(db)),
        extraRoutes: paymentRoutes,
      );
      expect(find.text(_en.paymentNotFound), findsOneWidget);
      await tester.tap(find.text(_en.orders));
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.orders);
    });

    testWidgets('guests get "Sign in to continue"', (tester) async {
      final db = FakeFirebaseFirestore();
      await pumpPhase6(
        tester,
        initialPath: AppRoutes.paymentFor('ps1'),
        guest: true,
        firestore: db,
        overrides: paymentOverrides(FakePaymentCalls(db)),
        extraRoutes: paymentRoutes,
      );
      expect(find.byKey(const ValueKey('guest-sign-in-card')), findsOneWidget);
    });
  });

  group('order details (SRS §5.12)', () {
    testWidgets('unpaid ZainCash order: payment chip, time left and Pay now → new session → status page',
        (tester) async {
      final (h, calls) = await _pumpOrder(tester, extra: zainCashOrderExtra());
      expect(find.byKey(const ValueKey('payment-status')), findsOneWidget);
      expect(find.text(_en.paymentZainCash), findsOneWidget);
      expect(find.text(_en.paymentStatusPending), findsOneWidget);
      expect(find.byKey(const ValueKey('pay-within')), findsOneWidget);
      expect(find.textContaining('30:00'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('pay-now')));
      await tester.tap(find.byKey(const ValueKey('pay-now')));
      await tester.pumpAndSettle();
      expect(calls.calls.single, {'purpose': 'order', 'orderId': 'o1'});
      expect(h.openedLinks, [Uri.parse(testPayUrl)]);
      expect(h.location, AppRoutes.paymentFor('ps1'));

      // Cancel pops back to the order (it was pushed from there).
      await tester.tap(find.byKey(const ValueKey('payment-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-now')), findsOneWidget);
    });

    testWidgets('Pay now refused by the server → localized message', (tester) async {
      final (_, calls) = await _pumpOrder(tester, extra: zainCashOrderExtra());
      calls.results.add(FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'The time to pay this order has run out.',
        details: const {'reason': 'expired'},
      ));
      await tester.ensureVisible(find.byKey(const ValueKey('pay-now')));
      await tester.tap(find.byKey(const ValueKey('pay-now')));
      await tester.pumpAndSettle();
      expect(find.text(_en.paymentErrorExpired), findsOneWidget);
    });

    testWidgets('no Pay now past paymentDueBy', (tester) async {
      await _pumpOrder(tester, extra: zainCashOrderExtra(), now: payDue);
      expect(find.byKey(const ValueKey('pay-now')), findsNothing);
      expect(find.byKey(const ValueKey('pay-within')), findsNothing);
    });

    testWidgets('no Pay now once paid', (tester) async {
      await _pumpOrder(tester, extra: {...zainCashOrderExtra(), 'paymentStatus': 'paid'});
      expect(find.byKey(const ValueKey('pay-now')), findsNothing);
      expect(find.text(_en.paymentStatusPaid), findsOneWidget);
    });

    testWidgets('no Pay now for cash on delivery', (tester) async {
      await _pumpOrder(tester, extra: const {});
      expect(find.byKey(const ValueKey('pay-now')), findsNothing);
      expect(find.byKey(const ValueKey('pay-within')), findsNothing);
      expect(find.text(_en.cashOnDelivery), findsOneWidget);
    });

    Future<void> seedCancelHistory(FakeFirebaseFirestore db) async {
      await db.doc('orders/o1/status_history/h0').set({'status': 'pending', 'byRole': 'customer', 'at': DateTime(2026, 10, 21, 8)});
      await db.doc('orders/o1/status_history/h1').set({'status': 'cancelledByBuyer', 'byRole': 'system', 'note': null, 'at': DateTime(2026, 10, 21, 8, 31)});
    }

    for (final (reason, label) in [
      ('payment_failed', (String l) => l10nFor(l).orderCancelReasonPaymentFailed),
      ('payment_expired', (String l) => l10nFor(l).orderCancelReasonPaymentExpired),
    ]) {
      for (final locale in ['en', 'ar', 'ckb']) {
        testWidgets('cancel reason $reason is translated ($locale)', (tester) async {
          await _pumpOrder(
            tester,
            status: 'cancelledByBuyer',
            locale: locale,
            extra: {...zainCashOrderExtra(), 'paymentStatus': 'failed', 'cancelReason': reason},
            seed: seedCancelHistory,
          );
          expect(find.text(label(locale)), findsOneWidget);
          expect(find.text(reason), findsNothing);
          expect(find.text(l10nFor(locale).paymentStatusFailed), findsOneWidget);
          expect(find.byKey(const ValueKey('pay-now')), findsNothing);
          // Cancelled by the system, not "By you".
          expect(find.text(l10nFor(locale).orderChangedByYou), findsOneWidget); // the pending step only
        });
      }
    }

    testWidgets('a reason typed by the customer is still shown as written', (tester) async {
      await _pumpOrder(tester, status: 'cancelledByBuyer', extra: const {'cancelReason': 'Ordered by mistake'});
      expect(find.text('Ordered by mistake'), findsOneWidget);
    });
  });

  group('wallet top-up (SRS §5.18)', () {
    testWidgets('no Top up while ZainCash is off', (tester) async {
      await _pumpWallet(tester, payments: const PaymentSettings());
      expect(find.byKey(const ValueKey('wallet-top-up')), findsNothing);
    });

    testWidgets('custom amount is validated (5,000–1,000,000) before any call', (tester) async {
      final (_, calls) = await _pumpWallet(tester);
      await tester.tap(find.byKey(const ValueKey('wallet-top-up')));
      await tester.pumpAndSettle();
      expect(find.text(_en.topUpTitle), findsOneWidget);
      for (final a in [10000, 25000, 50000, 100000]) {
        expect(find.byKey(ValueKey('top-up-$a')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('top-up-custom')));
      await tester.pumpAndSettle();
      final range = _en.topUpAmountRange('5,000 IQD', '1,000,000 IQD');
      for (final bad in ['3000', '2000000', '']) {
        await tester.enterText(find.descendant(of: find.byKey(const ValueKey('top-up-amount')), matching: find.byType(EditableText)), bad);
        await tester.tap(find.byKey(const ValueKey('top-up-continue')));
        await tester.pumpAndSettle();
        expect(find.text(range), findsOneWidget, reason: bad);
      }
      expect(calls.calls, isEmpty);
    });

    testWidgets('custom amount → createPaymentSession(topUp) → ZainCash → "Added X to your balance" → wallet',
        (tester) async {
      final (h, calls) = await _pumpWallet(tester);
      await tester.tap(find.byKey(const ValueKey('wallet-top-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('top-up-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('top-up-amount')), matching: find.byType(EditableText)), '50000');
      await tester.tap(find.byKey(const ValueKey('top-up-continue')));
      await tester.pumpAndSettle();

      expect(calls.calls.single, {'purpose': 'topUp', 'amount': 50000});
      expect(h.openedLinks, [Uri.parse(testPayUrl)]);
      expect(h.location, AppRoutes.paymentFor('ps1'));
      expect(find.text('50,000 IQD'), findsOneWidget);
      expect(find.text(_en.paymentForTopUp), findsOneWidget);

      await settleSession(h.firestore, 'ps1', 'paid', creditedToWallet: true);
      await tester.pumpAndSettle();
      expect(_viewTitle(tester, PaymentView.toppedUp), _en.topUpSuccessTitle);
      expect(find.text(_en.topUpSuccessBody('50,000 IQD')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('payment-back-to-wallet')));
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.wallet);
      expect(find.byKey(const ValueKey('wallet-top-up')), findsOneWidget);
    });

    testWidgets('preset amount; failed top-up → nothing charged, Try again back to the wallet', (tester) async {
      final (h, calls) = await _pumpWallet(tester);
      await tester.tap(find.byKey(const ValueKey('wallet-top-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('top-up-100000')));
      await tester.tap(find.byKey(const ValueKey('top-up-continue')));
      await tester.pumpAndSettle();
      expect(calls.calls.single, {'purpose': 'topUp', 'amount': 100000});

      await settleSession(h.firestore, 'ps1', 'failed');
      await tester.pumpAndSettle();
      expect(_viewTitle(tester, PaymentView.failed), _en.paymentFailedTitle);
      expect(find.text(_en.paymentNothingCharged), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-order-details')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('payment-try-again')));
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.wallet);
    });

    testWidgets('gateway down → message in the sheet, no page opened', (tester) async {
      final (h, calls) = await _pumpWallet(tester);
      calls.results.add(FirebaseFunctionsException(code: 'unavailable', message: 'down'));
      await tester.tap(find.byKey(const ValueKey('wallet-top-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('top-up-continue')));
      await tester.pumpAndSettle();
      expect(find.text(_en.paymentErrorUnavailable), findsOneWidget);
      expect(h.openedLinks, isEmpty);
      expect(h.location, AppRoutes.wallet);
    });

    testWidgets('Arabic-Indic digits are accepted (ar)', (tester) async {
      final (_, calls) = await _pumpWallet(tester, locale: 'ar');
      await tester.tap(find.byKey(const ValueKey('wallet-top-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('top-up-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('top-up-amount')), matching: find.byType(EditableText)), '٧٥٠٠٠');
      await tester.tap(find.byKey(const ValueKey('top-up-continue')));
      await tester.pumpAndSettle();
      expect(calls.calls.single, {'purpose': 'topUp', 'amount': 75000});
    });
  });

  group('RTL, dark mode, 320 px at 1.3×', () {
    const small = Size(320, 640);
    for (final locale in ['ar', 'ckb']) {
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('checkout + waiting + failed pages render ($locale, ${theme.name}, 320 px @1.3×)', (tester) async {
          final (h, _) = await _pumpCheckout(tester, locale: locale, themeMode: theme, size: small, textScale: 1.3);
          final l10n = l10nFor(locale);
          await _payWithZainCash(tester);
          expect(find.text(l10n.paymentWaitingTitle), findsOneWidget);
          expect(Directionality.of(tester.element(find.text(l10n.paymentWaitingTitle))), TextDirection.rtl);
          await tester.scrollUntilVisible(find.byKey(const ValueKey('payment-cancel')), 200,
              scrollable: find
                  .descendant(of: find.byKey(const ValueKey('payment-status-list')), matching: find.byType(Scrollable))
                  .first);
          expect(tester.takeException(), isNull);

          await settleSession(h.firestore, 'ps1', 'failed', orderId: 'o-new', cancelReason: 'payment_failed');
          await tester.pumpAndSettle();
          expect(find.text(l10n.paymentFailedTitle), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('order details Pay now renders ($locale, ${theme.name}, 320 px @1.3×)', (tester) async {
          final l10n = l10nFor(locale);
          await _pumpOrder(tester, extra: zainCashOrderExtra(), locale: locale, themeMode: theme, size: small, textScale: 1.3);
          await tester.scrollUntilVisible(find.byKey(const ValueKey('pay-now')), 200,
              scrollable: find
                  .descendant(of: find.byKey(const ValueKey('order-details-list')), matching: find.byType(Scrollable))
                  .first);
          expect(find.text(l10n.payNow), findsOneWidget);
          expect(find.byKey(const ValueKey('pay-within')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('wallet Top up + sheet with an error render ($locale, ${theme.name}, 320 px @1.3×)', (tester) async {
          final l10n = l10nFor(locale);
          await _pumpWallet(tester, locale: locale, themeMode: theme, size: small, textScale: 1.3);
          await tester.tap(find.byKey(const ValueKey('wallet-top-up')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('top-up-custom')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const ValueKey('top-up-continue')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('top-up-continue')));
          await tester.pumpAndSettle();
          expect(find.text(l10n.topUpAmountRange('5,000 IQD', '1,000,000 IQD')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('top-up success page (ckb, dark, 320 px @1.3×)', (tester) async {
      final db = FakeFirebaseFirestore();
      final calls = FakePaymentCalls(db);
      await calls.call('createPaymentSession', {'purpose': 'topUp', 'amount': 1000000});
      await settleSession(db, 'ps1', 'paid', creditedToWallet: true);
      await pumpPhase6(
        tester,
        initialPath: AppRoutes.paymentFor('ps1'),
        firestore: db,
        locale: 'ckb',
        themeMode: ThemeMode.dark,
        size: const Size(320, 640),
        textScale: 1.3,
        overrides: paymentOverrides(calls),
        extraRoutes: paymentRoutes,
      );
      expect(find.text(l10nFor('ckb').topUpSuccessBody('1,000,000 IQD')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('every new payment text exists in en, ar and ckb', () {
    for (final l in ['en', 'ar', 'ckb']) {
      final t = l10nFor(l);
      for (final s in [
        t.paymentZainCash,
        t.paymentWaitingTitle,
        t.paymentOpenAgain,
        t.paymentCheckStatus,
        t.payNow,
        t.walletTopUp,
        t.topUpContinue,
        t.orderCancelReasonPaymentFailed,
        t.orderCancelReasonPaymentExpired,
      ]) {
        expect(s.trim(), isNotEmpty);
      }
    }
    expect(l10nFor('ar').paymentZainCash, isNot(_en.paymentZainCash));
  });
}
