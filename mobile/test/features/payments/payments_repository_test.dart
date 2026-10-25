import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/payments/data/payments_repository.dart';
import 'package:golden_gift/features/payments/presentation/providers/payment_providers.dart';
import 'package:golden_gift/features/payments/presentation/screens/payment_status_screen.dart';
import 'package:golden_gift/features/payments/presentation/widgets/payment_ui.dart';
import 'package:golden_gift/models/order_model.dart';

void main() {
  final due = DateTime.utc(2026, 10, 21, 9, 30);
  final now = DateTime.utc(2026, 10, 21, 9, 10);

  group('createPaymentSession', () {
    test('order: sends {purpose, orderId} and parses {sessionId, payUrl, expiresAt}', () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final repo = PaymentsRepository(FakeFirebaseFirestore(), (name, data) async {
        calls.add((name, data));
        return {'sessionId': 'ps1', 'payUrl': 'https://test.zaincash.iq/transaction/pay?id=t1', 'expiresAt': due.toIso8601String()};
      });
      final s = await repo.startOrderPayment('o1');
      expect(calls.single.$1, 'createPaymentSession');
      expect(calls.single.$2, {'purpose': 'order', 'orderId': 'o1'});
      expect(s.sessionId, 'ps1');
      expect(s.payUrl, 'https://test.zaincash.iq/transaction/pay?id=t1');
      expect(s.expiresAt, due);
    });

    test('top-up: sends {purpose: topUp, amount}', () async {
      Map<String, dynamic>? sent;
      final repo = PaymentsRepository(FakeFirebaseFirestore(), (name, data) async {
        sent = data;
        return {'sessionId': 'ps2', 'payUrl': 'https://x.iq/pay'};
      });
      final s = await repo.startTopUp(25000);
      expect(sent, {'purpose': 'topUp', 'amount': 25000});
      expect(s.expiresAt, isNull);
    });

    test('an empty answer is a failure, not a session', () async {
      final repo = PaymentsRepository(FakeFirebaseFirestore(), (_, __) async => {'sessionId': '', 'payUrl': ''});
      await expectLater(
        repo.startTopUp(5000),
        throwsA(isA<PaymentFailure>().having((f) => f.reason, 'reason', PaymentFailureReason.unknown)),
      );
    });

    PaymentFailureReason reasonFor(String code, {String? message, Object? details}) =>
        PaymentFailure.from(FirebaseFunctionsException(code: code, message: message ?? code, details: details)).reason;

    test('server errors map to PaymentFailureReason', () async {
      expect(reasonFor('failed-precondition', details: {'reason': 'gateway_disabled'}), PaymentFailureReason.gatewayDisabled);
      expect(reasonFor('failed-precondition', details: {'reason': 'not_payable'}), PaymentFailureReason.notPayable);
      expect(reasonFor('failed-precondition', details: {'reason': 'already_paid'}), PaymentFailureReason.alreadyPaid);
      expect(reasonFor('failed-precondition', details: {'reason': 'expired'}), PaymentFailureReason.expired);
      expect(reasonFor('failed-precondition', details: {'reason': 'other'}), PaymentFailureReason.unknown);
      expect(reasonFor('not-found', message: 'Order not found.'), PaymentFailureReason.notPayable);
      expect(reasonFor('permission-denied', message: 'This is not your order.'), PaymentFailureReason.notPayable);
      // Gateway down / not configured, or the function isn't deployed.
      expect(reasonFor('unavailable', message: 'Online payment is not available right now.'), PaymentFailureReason.unavailable);
      expect(reasonFor('not-found', message: 'NOT_FOUND'), PaymentFailureReason.unavailable);
      expect(reasonFor('internal'), PaymentFailureReason.unavailable);
      expect(reasonFor('deadline-exceeded'), PaymentFailureReason.network);
      expect(reasonFor('invalid-argument'), PaymentFailureReason.unknown);
      expect(PaymentFailure.from(StateError('x')).reason, PaymentFailureReason.unknown);

      final repo = PaymentsRepository(FakeFirebaseFirestore(), (_, __) async {
        throw FirebaseFunctionsException(code: 'failed-precondition', message: 'm', details: const {'reason': 'expired'});
      });
      await expectLater(
        repo.startOrderPayment('o1'),
        throwsA(isA<PaymentFailure>().having((f) => f.reason, 'reason', PaymentFailureReason.expired)),
      );
    });
  });

  group('payment_sessions/{id}', () {
    test('watchSession: parses the doc and follows its status; missing → null', () async {
      final db = FakeFirebaseFirestore();
      final repo = PaymentsRepository(db, (_, __) async => null);
      await db.doc(FirestorePaths.paymentSessionDoc('ps1')).set({
        'uid': 'u1',
        'purpose': 'order',
        'orderId': 'o1',
        'orderNumber': 'GG-2610-00042',
        'amount': 75000,
        'currency': 'IQD',
        'gateway': 'zainCash',
        'env': 'test',
        'status': 'pending',
        'gatewayTxnId': 't1',
        'payUrl': 'https://test.zaincash.iq/transaction/pay?id=t1',
        'expiresAt': Timestamp.fromDate(due),
        'createdAt': Timestamp.fromDate(now),
      });
      final stream = repo.watchSession('ps1');
      final first = await stream.first;
      expect(first!.id, 'ps1');
      expect(first.purpose, PaymentPurpose.order);
      expect(first.orderId, 'o1');
      expect(first.orderNumber, 'GG-2610-00042');
      expect(first.amount, 75000);
      expect(first.status, PaymentSessionStatus.pending);
      expect(first.isSettled, isFalse);
      expect(first.payUrl, startsWith('https://'));
      expect(first.expiresAt, due.toLocal());

      final statuses = <PaymentSessionStatus?>[];
      final sub = stream.listen((s) => statuses.add(s?.status));
      await pumpEventQueue();
      await db.doc(FirestorePaths.paymentSessionDoc('ps1')).update({'status': 'paid', 'creditedToWallet': false});
      await pumpEventQueue();
      await sub.cancel();
      expect(statuses, [PaymentSessionStatus.pending, PaymentSessionStatus.paid]);

      expect(await repo.watchSession('nope').first, isNull);
    });

    test('fromMap is tolerant (top-up, unknown status, missing fields)', () {
      final s = PaymentSessionModel.fromMap('ps2', {'purpose': 'topUp', 'amount': 50000.0, 'status': 'weird'});
      expect(s.purpose, PaymentPurpose.topUp);
      expect(s.amount, 50000);
      expect(s.status, PaymentSessionStatus.pending);
      expect(s.orderId, isNull);
      expect(s.payUrl, isNull);
      expect(s.creditedToWallet, isFalse);
      expect(PaymentSessionModel.fromMap('x', const {}).purpose, PaymentPurpose.order);
    });
  });

  group('rules', () {
    OrderModel zainCashOrder({
      String method = 'zainCash',
      String paymentStatus = 'pending',
      String status = 'pending',
      DateTime? dueBy,
    }) =>
        OrderModel.fromMap('o1', {
          'orderNumber': 'GG-2610-00042',
          'userId': 'u1',
          'subtotal': 70000,
          'total': 75000,
          'paymentMethod': method,
          'paymentStatus': paymentStatus,
          'status': status,
          if (dueBy != null) 'paymentDueBy': Timestamp.fromDate(dueBy),
        });

    test('OrderModel reads paymentDueBy', () {
      expect(zainCashOrder(dueBy: due).paymentDueBy, due.toLocal());
      expect(zainCashOrder().paymentDueBy, isNull);
    });

    test('orderAwaitsOnlinePayment: unpaid ZainCash order, pending / confirmed, before paymentDueBy', () {
      expect(orderAwaitsOnlinePayment(zainCashOrder(dueBy: due), now), isTrue);
      expect(orderAwaitsOnlinePayment(zainCashOrder(dueBy: due, status: 'confirmed'), now), isTrue);
      expect(orderAwaitsOnlinePayment(zainCashOrder(dueBy: due), due), isFalse);
      expect(orderAwaitsOnlinePayment(zainCashOrder(), now), isFalse);
      expect(orderAwaitsOnlinePayment(zainCashOrder(dueBy: due, paymentStatus: 'paid'), now), isFalse);
      expect(orderAwaitsOnlinePayment(zainCashOrder(dueBy: due, status: 'cancelledByBuyer'), now), isFalse);
      expect(orderAwaitsOnlinePayment(zainCashOrder(dueBy: due, status: 'preparing'), now), isFalse);
      expect(orderAwaitsOnlinePayment(zainCashOrder(dueBy: due, method: 'cashOnDelivery'), now), isFalse);
    });

    test('top-up limits: 5,000–1,000,000 IQD', () {
      expect(PaymentLimits.validTopUp(5000), isTrue);
      expect(PaymentLimits.validTopUp(1000000), isTrue);
      expect(PaymentLimits.validTopUp(4999), isFalse);
      expect(PaymentLimits.validTopUp(1000001), isFalse);
      expect(PaymentLimits.validTopUp(null), isFalse);
      expect(PaymentLimits.topUpPresets.every(PaymentLimits.validTopUp), isTrue);
    });

    test('countdown text: mm:ss, h:mm:ss past an hour, never negative, LTR-isolated', () {
      String plain(Duration d) => formatCountdown(d).replaceAll(RegExp('[${String.fromCharCode(0x2066)}${String.fromCharCode(0x2069)}]'), '');
      expect(plain(const Duration(minutes: 24, seconds: 5)), '24:05');
      expect(plain(const Duration(seconds: 9)), '00:09');
      expect(plain(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(plain(const Duration(seconds: -4)), '00:00');
      expect(formatCountdown(Duration.zero), startsWith(String.fromCharCode(0x2066)));
    });

    test('opens only http(s) pay pages; a throwing opener is "not opened"', () async {
      final opened = <Uri>[];
      Future<bool> ok(Uri u) async {
        opened.add(u);
        return true;
      }

      expect(await openPaymentPage(ok, 'https://test.zaincash.iq/transaction/pay?id=t1'), isTrue);
      expect(await openPaymentPage(ok, 'javascript:alert(1)'), isFalse);
      expect(await openPaymentPage(ok, 'goldengift://payment'), isFalse);
      expect(await openPaymentPage(ok, null), isFalse);
      expect(opened, [Uri.parse('https://test.zaincash.iq/transaction/pay?id=t1')]);
      expect(await openPaymentPage((_) async => throw StateError('no browser'), 'https://x.iq/p'), isFalse);
    });
  });

  group('payment status view', () {
    PaymentSessionModel session(String status, {String purpose = 'order', bool credited = false, DateTime? expires}) =>
        PaymentSessionModel.fromMap('ps1', {
          'uid': 'u1',
          'purpose': purpose,
          'orderId': purpose == 'order' ? 'o1' : null,
          'amount': 75000,
          'status': status,
          'creditedToWallet': credited,
          'expiresAt': Timestamp.fromDate(expires ?? due),
        });
    OrderModel order({String status = 'pending', String paymentStatus = 'pending', String? reason}) =>
        OrderModel.fromMap('o1', {
          'orderNumber': 'GG-2610-00042',
          'userId': 'u1',
          'subtotal': 70000,
          'total': 75000,
          'paymentMethod': 'zainCash',
          'paymentStatus': paymentStatus,
          'status': status,
          'cancelReason': reason,
          'paymentDueBy': Timestamp.fromDate(due),
        });

    test('the session (and the order) decide; the deep link hint never does', () {
      expect(paymentViewFor(null, null, now), PaymentView.missing);
      expect(paymentViewFor(session('pending'), order(), now), PaymentView.waiting);
      expect(paymentViewFor(session('pending'), order(), due), PaymentView.timeUp);
      expect(paymentViewFor(session('paid'), order(paymentStatus: 'paid'), now), PaymentView.orderPaid);
      expect(paymentViewFor(session('paid', credited: true), order(status: 'cancelledByBuyer'), now), PaymentView.paidToWallet);
      expect(paymentViewFor(session('paid', purpose: 'topUp', credited: true), null, now), PaymentView.toppedUp);
      expect(paymentViewFor(session('failed'), order(status: 'cancelledByBuyer', reason: 'payment_failed'), now),
          PaymentView.failed);
      expect(paymentViewFor(session('expired'), null, now), PaymentView.expired);
      // Still pending, but the order was paid through another session / cancelled meanwhile.
      expect(paymentViewFor(session('pending'), order(paymentStatus: 'paid'), now), PaymentView.orderPaid);
      expect(paymentViewFor(session('pending'), order(status: 'cancelledByBuyer', reason: 'payment_expired'), now),
          PaymentView.expired);
      expect(paymentViewFor(session('pending'), order(status: 'cancelledByBuyer', reason: 'Changed my mind'), now),
          PaymentView.failed);
    });
  });

  group('goldengift://payment deep link', () {
    test('custom scheme (warm start), cold start and /payment all reach the status page', () {
      // What go_router hands over for `goldengift://payment?…`: the empty path becomes `/`.
      expect(paymentDeepLinkRedirect(Uri.parse('goldengift://payment/?sid=ps1&status=paid')), '/payment/ps1?status=paid');
      expect(paymentDeepLinkRedirect(Uri.parse('goldengift://payment?sid=ps1&status=failed')), '/payment/ps1?status=failed');
      // Cold start: GoRouter keeps only the query of the platform's default route.
      expect(paymentDeepLinkRedirect(Uri.parse('/?sid=ps1&status=pending')), '/payment/ps1?status=pending');
      expect(paymentDeepLinkRedirect(Uri.parse('/payment?sid=ps1')), '/payment/ps1');
      // Missing / malformed session id → Orders.
      expect(paymentDeepLinkRedirect(Uri.parse('goldengift://payment/?status=error')), AppRoutes.orders);
      expect(paymentDeepLinkRedirect(Uri.parse('goldengift://payment/?sid=../x')), AppRoutes.orders);
      // Everything else is left alone.
      expect(paymentDeepLinkRedirect(Uri.parse('/')), isNull);
      expect(paymentDeepLinkRedirect(Uri.parse('/payment/ps1?status=paid')), isNull);
      expect(paymentDeepLinkRedirect(Uri.parse('/orders/o1')), isNull);
      expect(paymentDeepLinkRedirect(Uri.parse('https://goldengift.app/p/mug')), isNull);
      expect(AppRoutes.paymentFor('ps1'), '/payment/ps1');
    });
  });

  test('checkPaymentStatus asks the server for one session; resource-exhausted is rate limited', () async {
    final sent = <(String, Map<String, dynamic>)>[];
    final repo = PaymentsRepository(FakeFirebaseFirestore(), (name, data) async {
      sent.add((name, data));
      return {'status': 'paid'};
    });
    expect(await repo.checkStatus('ps9'), 'paid');
    expect(sent.single.$1, 'checkPaymentStatus');
    expect(sent.single.$2, {'sessionId': 'ps9'});

    final limited = PaymentsRepository(FakeFirebaseFirestore(), (_, __) async {
      throw FirebaseFunctionsException(code: 'resource-exhausted', message: 'slow down');
    });
    await expectLater(
      limited.checkStatus('ps9'),
      throwsA(isA<PaymentFailure>().having((f) => f.reason, 'reason', PaymentFailureReason.rateLimited)),
    );
  });
}
