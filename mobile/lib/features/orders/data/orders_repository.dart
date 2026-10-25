import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/utils/app_dates.dart';
import '../../../models/order_model.dart';

/// Why `placeOrder` / `cancelOrder` refused (mapped to localized text by the UI).
enum OrderFailureReason {
  cartChanged,
  cityNotAllowed,
  outOfStock,
  minimumNotMet,
  emptyCart,
  notCancellable,

  /// The promo code no longer applies (`details.promoReason` = a PromoRejection name).
  promoInvalid,

  /// Wallet + credits don't cover a "Wallet" payment.
  insufficientFunds,

  /// `invalid-argument`: the delivery date / slot or payment method is no
  /// longer allowed (e.g. a slot started while the customer was on checkout).
  invalidChoice,
  unavailable,
  network,
  unknown,
}

class OrderFailure implements Exception {
  const OrderFailure(this.reason, {this.productIds = const [], this.message});
  final OrderFailureReason reason;
  final List<String> productIds;
  final String? message;

  /// Server contract (functions/src/orders): HttpsError `failed-precondition`
  /// with details `{ reason, productIds? }`.
  factory OrderFailure.from(Object error) {
    if (error is OrderFailure) return error;
    if (error is FirebaseFunctionsException) {
      final details = error.details is Map ? Map<String, dynamic>.from(error.details as Map) : const <String, dynamic>{};
      final ids = (details['productIds'] as List?)?.whereType<String>().toList() ?? const <String>[];
      final reason = switch (error.code) {
        'failed-precondition' => switch (details['reason']) {
            'cart_changed' => OrderFailureReason.cartChanged,
            'city_not_allowed' => OrderFailureReason.cityNotAllowed,
            'out_of_stock' => OrderFailureReason.outOfStock,
            'min_order' => OrderFailureReason.minimumNotMet,
            'empty_cart' => OrderFailureReason.emptyCart,
            'not_cancellable' => OrderFailureReason.notCancellable,
            'promo_invalid' => OrderFailureReason.promoInvalid,
            'insufficient_funds' => OrderFailureReason.insufficientFunds,
            _ => OrderFailureReason.unknown,
          },
        'invalid-argument' => OrderFailureReason.invalidChoice,
        'not-found' || 'unimplemented' || 'internal' || 'unavailable' => OrderFailureReason.unavailable,
        'deadline-exceeded' => OrderFailureReason.network,
        _ => OrderFailureReason.unknown,
      };
      return OrderFailure(reason, productIds: ids, message: error.message);
    }
    return OrderFailure(OrderFailureReason.unknown, message: '$error');
  }
}

/// What the customer chose at checkout (SRS §5.11). The server reads the cart
/// itself from `carts/{uid}/items` — prices are never trusted from the client.
class PlaceOrderRequest {
  const PlaceOrderRequest({
    required this.clientRequestId,
    required this.addressId,
    required this.deliveryDate,
    this.deliverySlot,
    this.isGift = false,
    this.giftMessage,
    this.hidePrices = false,
    this.paymentMethod = PaymentMethod.cashOnDelivery,
    this.promoCode,
    this.useCredits = false,
    this.useWallet = false,
  });

  /// Same id on a retry → the same order (idempotent).
  final String clientRequestId;
  final String addressId;
  final DateTime deliveryDate;
  final String? deliverySlot;
  final bool isGift;
  final String? giftMessage;
  final bool hidePrices;
  final PaymentMethod paymentMethod;
  final String? promoCode;
  final bool useCredits;
  final bool useWallet;

  Map<String, dynamic> toMap() => {
        'clientRequestId': clientRequestId,
        'addressId': addressId,
        'deliveryDate': AppDates.isoDate(deliveryDate),
        'deliverySlot': deliverySlot,
        'isGift': isGift,
        'giftMessage': (giftMessage?.trim().isEmpty ?? true) ? null : giftMessage!.trim(),
        'hidePrices': hidePrices,
        'paymentMethod': paymentMethod.name,
        'promoCode': promoCode,
        'useCredits': useCredits,
        'useWallet': useWallet,
      };
}

class PlacedOrder {
  const PlacedOrder({required this.orderId, required this.orderNumber, required this.total, this.deliveryDate});
  final String orderId;
  final String orderNumber;
  final int total;
  final DateTime? deliveryDate;
}

class OrdersRepository {
  OrdersRepository(this._db, this._functions);
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Stream<List<OrderModel>> watchMine(String uid) => _db
      .collection(FirestorePaths.orders)
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => [for (final d in s.docs) OrderModel.fromMap(d.id, d.data())]);

  Stream<OrderModel?> watch(String orderId) => _db
      .doc(FirestorePaths.orderDoc(orderId))
      .snapshots()
      .map((s) => s.exists ? OrderModel.fromMap(s.id, s.data()!) : null);

  Stream<List<StatusHistoryEntry>> watchHistory(String orderId) => _db
      .collection(FirestorePaths.orderHistory(orderId))
      .orderBy('at')
      .snapshots()
      .map((s) => [for (final d in s.docs) StatusHistoryEntry.fromMap(d.data())]);

  Future<PlacedOrder> placeOrder(PlaceOrderRequest request) async {
    try {
      final result = await _functions.httpsCallable('placeOrder').call<Map<String, dynamic>>(request.toMap());
      final data = Map<String, dynamic>.from(result.data);
      return PlacedOrder(
        orderId: data['orderId'] as String,
        orderNumber: data['orderNumber'] as String? ?? '',
        total: (data['total'] as num?)?.toInt() ?? 0,
        deliveryDate: DateTime.tryParse(data['deliveryDate'] as String? ?? ''),
      );
    } catch (e) {
      throw OrderFailure.from(e);
    }
  }

  Future<void> cancelOrder(String orderId, {String? reason}) async {
    try {
      await _functions.httpsCallable('cancelOrder').call<Map<String, dynamic>>({'orderId': orderId, 'reason': reason});
    } catch (e) {
      throw OrderFailure.from(e);
    }
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider)),
);

final myOrdersProvider = StreamProvider<List<OrderModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(ordersRepositoryProvider).watchMine(uid);
});

final orderByIdProvider = StreamProvider.autoDispose.family<OrderModel?, String>(
  (ref, id) => ref.watch(ordersRepositoryProvider).watch(id),
);

final orderHistoryProvider = StreamProvider.autoDispose.family<List<StatusHistoryEntry>, String>(
  (ref, id) => ref.watch(ordersRepositoryProvider).watchHistory(id),
);
