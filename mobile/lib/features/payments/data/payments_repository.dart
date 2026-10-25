import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/services/callable.dart';
import '../../../core/utils/firestore_parse.dart';
import '../../../models/order_model.dart';

/// Online payment through a gateway (Phase 9: ZainCash, SRS §5.11, §5.18,
/// §6.14, §7). The app asks `createPaymentSession` for a session, opens its
/// `payUrl` outside the app and watches `payment_sessions/{id}` (owner-readable,
/// written only by functions) until it is settled.

/// Amounts the server enforces (functions/src/orders/placeOrder.ts
/// `MIN_GATEWAY_AMOUNT`, functions/src/payments/paymentSessions.ts `TOP_UP_*`).
class PaymentLimits {
  PaymentLimits._();

  /// A gateway order must collect at least this much (after promo and credits).
  static const minGatewayAmount = 1000;
  static const topUpMin = 5000;
  static const topUpMax = 1000000;
  static const topUpPresets = [10000, 25000, 50000, 100000];

  static bool validTopUp(int? amount) => amount != null && amount >= topUpMin && amount <= topUpMax;
}

enum PaymentPurpose { order, topUp }

enum PaymentSessionStatus { pending, paid, failed, expired }

/// `payment_sessions/{id}` (SRS §6.14) as the customer may read it.
class PaymentSessionModel {
  const PaymentSessionModel({
    required this.id,
    required this.uid,
    required this.purpose,
    this.orderId,
    this.orderNumber,
    required this.amount,
    this.gateway = 'zainCash',
    required this.status,
    this.payUrl,
    this.expiresAt,
    this.creditedToWallet = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String uid;
  final PaymentPurpose purpose;
  final String? orderId;
  final String? orderNumber;
  final int amount;
  final String gateway;
  final PaymentSessionStatus status;

  /// The gateway's pay page (set once the gateway transaction exists).
  final String? payUrl;

  /// The order's `paymentDueBy`, or 30 minutes after a top-up started.
  final DateTime? expiresAt;

  /// A paid session whose amount went to the wallet balance: a top-up, or a
  /// payment that arrived for an order that no longer waited for it.
  final bool creditedToWallet;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isSettled => status != PaymentSessionStatus.pending;

  factory PaymentSessionModel.fromMap(String id, Map<String, dynamic> map) => PaymentSessionModel(
        id: id,
        uid: map['uid'] as String? ?? '',
        purpose: FirestoreParse.enumValue(PaymentPurpose.values, map['purpose'], PaymentPurpose.order),
        orderId: FirestoreParse.stringOrNull(map['orderId']),
        orderNumber: FirestoreParse.stringOrNull(map['orderNumber']),
        amount: FirestoreParse.integer(map['amount']),
        gateway: FirestoreParse.stringOrNull(map['gateway']) ?? 'zainCash',
        status: FirestoreParse.enumValue(PaymentSessionStatus.values, map['status'], PaymentSessionStatus.pending),
        payUrl: FirestoreParse.stringOrNull(map['payUrl']),
        expiresAt: FirestoreParse.date(map['expiresAt']),
        creditedToWallet: FirestoreParse.boolean(map['creditedToWallet']),
        createdAt: FirestoreParse.date(map['createdAt']),
        updatedAt: FirestoreParse.date(map['updatedAt']),
      );
}

/// What `createPaymentSession` answers.
class PaymentSession {
  const PaymentSession({required this.sessionId, required this.payUrl, this.expiresAt});
  final String sessionId;
  final String payUrl;
  final DateTime? expiresAt;
}

/// Why a payment could not start (mapped to localized text by the UI).
enum PaymentFailureReason {
  /// `app_settings/payments.zainCash` is off.
  gatewayDisabled,

  /// Not a gateway order / not this customer's / no longer waiting / blocked account.
  notPayable,
  alreadyPaid,

  /// `paymentDueBy` has passed.
  expired,

  /// Gateway not configured or not answering, or the function isn't deployed —
  /// nothing was charged; try again later.
  unavailable,

  /// Too many attempts (`resource-exhausted`) — wait a few minutes.
  rateLimited,
  network,
  unknown,
}

class PaymentFailure implements Exception {
  const PaymentFailure(this.reason, {this.message});
  final PaymentFailureReason reason;
  final String? message;

  /// Server contract (functions/src/payments/paymentSessions.ts): HttpsError
  /// `failed-precondition` with details `{reason}`; `not-found` "Order not
  /// found." (any other `not-found` = the function isn't deployed).
  factory PaymentFailure.from(Object error) {
    if (error is PaymentFailure) return error;
    if (error is FirebaseFunctionsException) {
      final details = error.details is Map ? Map<String, dynamic>.from(error.details as Map) : const <String, dynamic>{};
      final orderMissing = (error.message ?? '').toLowerCase().contains('order not found');
      final reason = switch (error.code) {
        'failed-precondition' => switch (details['reason']) {
            'gateway_disabled' => PaymentFailureReason.gatewayDisabled,
            'not_payable' => PaymentFailureReason.notPayable,
            'already_paid' => PaymentFailureReason.alreadyPaid,
            'expired' => PaymentFailureReason.expired,
            _ => PaymentFailureReason.unknown,
          },
        'not-found' when orderMissing => PaymentFailureReason.notPayable,
        'permission-denied' => PaymentFailureReason.notPayable,
        'not-found' || 'unimplemented' || 'internal' || 'unavailable' => PaymentFailureReason.unavailable,
        'resource-exhausted' => PaymentFailureReason.rateLimited,
        'deadline-exceeded' => PaymentFailureReason.network,
        _ => PaymentFailureReason.unknown,
      };
      return PaymentFailure(reason, message: error.message);
    }
    return PaymentFailure(PaymentFailureReason.unknown, message: '$error');
  }
}

/// Whether the customer can (still) pay [order] online (SRS §6.7): a ZainCash
/// order, unpaid, pending / confirmed and before its `paymentDueBy`.
bool orderAwaitsOnlinePayment(OrderModel order, DateTime now) {
  final due = order.paymentDueBy;
  return order.paymentMethod == PaymentMethod.zainCash &&
      order.paymentStatus == PaymentStatus.pending &&
      order.status.customerCanCancel &&
      due != null &&
      now.isBefore(due);
}

class PaymentsRepository {
  PaymentsRepository(this._db, this._call);
  final FirebaseFirestore _db;
  final CallableInvoker _call;

  /// Starts paying the caller's ZainCash order. Throws [PaymentFailure].
  Future<PaymentSession> startOrderPayment(String orderId) =>
      _create({'purpose': PaymentPurpose.order.name, 'orderId': orderId});

  /// Starts a wallet top-up of [amount] IQD (5,000–1,000,000). Throws [PaymentFailure].
  Future<PaymentSession> startTopUp(int amount) => _create({'purpose': PaymentPurpose.topUp.name, 'amount': amount});

  Future<PaymentSession> _create(Map<String, dynamic> data) async {
    try {
      final res = callableMap(await _call('createPaymentSession', data));
      final id = res['sessionId'] as String? ?? '';
      final url = res['payUrl'] as String? ?? '';
      if (id.isEmpty || url.isEmpty) throw const PaymentFailure(PaymentFailureReason.unknown, message: 'empty session');
      return PaymentSession(
        sessionId: id,
        payUrl: url,
        expiresAt: DateTime.tryParse(res['expiresAt'] as String? ?? ''),
      );
    } catch (e) {
      throw PaymentFailure.from(e);
    }
  }

  /// Asks the gateway about one session right now (`checkPaymentStatus`) and
  /// settles it server-side — for a customer who paid but closed the browser
  /// before the redirect. Returns the resulting status (pending | paid |
  /// failed | expired). Throws [PaymentFailure].
  Future<String> checkStatus(String sessionId) async {
    try {
      final res = callableMap(await _call('checkPaymentStatus', {'sessionId': sessionId}));
      return res['status'] as String? ?? 'pending';
    } catch (e) {
      throw PaymentFailure.from(e);
    }
  }

  /// The session doc; null when it doesn't exist (or isn't readable).
  Stream<PaymentSessionModel?> watchSession(String sessionId) => _db
      .doc(FirestorePaths.paymentSessionDoc(sessionId))
      .snapshots()
      .map((s) => s.exists ? PaymentSessionModel.fromMap(s.id, s.data()!) : null);
}

final paymentsRepositoryProvider = Provider<PaymentsRepository>(
  (ref) => PaymentsRepository(ref.watch(firestoreProvider), ref.watch(callableInvokerProvider)),
);

final paymentSessionProvider = StreamProvider.autoDispose.family<PaymentSessionModel?, String>(
  (ref, id) => ref.watch(paymentsRepositoryProvider).watchSession(id),
);
