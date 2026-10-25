import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/callable.dart';
import 'package:golden_gift/features/payments/presentation/providers/payment_providers.dart';
import 'package:golden_gift/features/payments/presentation/screens/payment_status_screen.dart';
import 'package:golden_gift/features/wallet/presentation/screens/wallet_screen.dart';

/// Shared bits of the online-payment widget tests (Phase 9, ZainCash): a
/// scripted `createPaymentSession` that also writes the pending session doc
/// the server would write, a pinned clock, and the payment / wallet pages.

final payNow = DateTime(2026, 10, 21, 9);
final payDue = payNow.add(const Duration(minutes: 30));
const testPayUrl = 'https://test.zaincash.iq/transaction/pay?id=t1';

/// Fake `createPaymentSession`: records each call; answers from [results]
/// (a thrown error, or null = success) and on success writes
/// `payment_sessions/ps{n}` as `pending`, like the function.
class FakePaymentCalls {
  FakePaymentCalls(this.db);
  final FakeFirebaseFirestore db;
  final calls = <Map<String, dynamic>>[];
  final results = <Object?>[];
  int _n = 0;

  Future<Object?> call(String name, Map<String, dynamic> data) async {
    if (name != 'createPaymentSession') throw StateError('unexpected callable $name');
    calls.add(data);
    final next = results.isEmpty ? null : results.removeAt(0);
    if (next != null) throw next;
    final sid = 'ps${++_n}';
    final isOrder = data['purpose'] == 'order';
    final order = isOrder ? (await db.doc(FirestorePaths.orderDoc(data['orderId'] as String)).get()).data() : null;
    await db.doc(FirestorePaths.paymentSessionDoc(sid)).set({
      'uid': 'u1',
      'purpose': data['purpose'],
      'orderId': isOrder ? data['orderId'] : null,
      'orderNumber': order?['orderNumber'],
      'amount': isOrder ? (order?['total'] ?? 75000) : data['amount'],
      'currency': 'IQD',
      'gateway': 'zainCash',
      'env': 'test',
      'status': 'pending',
      'gatewayTxnId': 't$_n',
      'payUrl': testPayUrl,
      'expiresAt': Timestamp.fromDate(payDue),
      'createdAt': Timestamp.fromDate(payNow),
    });
    return {'sessionId': sid, 'payUrl': testPayUrl, 'expiresAt': payDue.toUtc().toIso8601String()};
  }
}

List<Override> paymentOverrides(FakePaymentCalls calls, {DateTime? now}) => [
      callableInvokerProvider.overrideWithValue(calls.call),
      paymentClockProvider.overrideWithValue(PaymentClock(now: () => now ?? payNow, tick: null)),
    ];

final paymentRoutes = <RouteBase>[
  GoRoute(
    path: AppRoutes.payment,
    builder: (_, state) => PaymentStatusScreen(
      sessionId: state.pathParameters['sid']!,
      statusHint: state.uri.queryParameters['status'],
    ),
  ),
  GoRoute(path: AppRoutes.wallet, builder: (_, __) => const WalletScreen()),
];

/// `orders/{id}` as `placeOrder` creates a ZainCash order (unpaid, due in 30 min).
Map<String, dynamic> zainCashOrderExtra({DateTime? dueBy}) => {
      'paymentMethod': 'zainCash',
      'paymentStatus': 'pending',
      'paymentDueBy': dueBy ?? payDue,
    };

/// What the server writes when the session settles (the order as settlePayment / expiry leave it).
Future<void> settleSession(
  FakeFirebaseFirestore db,
  String sid,
  String status, {
  String? orderId,
  bool creditedToWallet = false,
  String? cancelReason,
}) async {
  await db.doc(FirestorePaths.paymentSessionDoc(sid)).update({
    'status': status,
    'creditedToWallet': creditedToWallet,
  });
  if (orderId == null) return;
  if (status == 'paid' && !creditedToWallet) {
    await db.doc(FirestorePaths.orderDoc(orderId)).update({'paymentStatus': 'paid', 'paymentRef': 't1'});
  } else if (cancelReason != null) {
    await db.doc(FirestorePaths.orderDoc(orderId)).update({
      'status': 'cancelledByBuyer',
      'paymentStatus': 'failed',
      'cancelReason': cancelReason,
    });
  }
}
