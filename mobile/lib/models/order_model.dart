import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';
import 'address_model.dart';
import 'cart_item_model.dart';

/// Which tab an order appears in (SRS §5.12).
enum OrderTab { active, completed, cancelled }

extension OrderStatusX on OrderStatus {
  OrderTab get tab => switch (this) {
        OrderStatus.delivered => OrderTab.completed,
        OrderStatus.cancelledByBuyer ||
        OrderStatus.cancelledBySeller ||
        OrderStatus.returned ||
        OrderStatus.refunded =>
          OrderTab.cancelled,
        _ => OrderTab.active,
      };

  /// The customer may cancel only before preparation starts (SRS §5.12).
  bool get customerCanCancel => this == OrderStatus.pending || this == OrderStatus.confirmed;

  /// Status changes staff may make (admin dashboard; sellers in Phase 8).
  /// Customers cancel only through the `cancelOrder` function.
  List<OrderStatus> get allowedNext => switch (this) {
        OrderStatus.pending => const [OrderStatus.confirmed, OrderStatus.cancelledBySeller],
        OrderStatus.confirmed => const [OrderStatus.preparing, OrderStatus.cancelledBySeller],
        OrderStatus.preparing => const [OrderStatus.readyForDelivery, OrderStatus.cancelledBySeller],
        OrderStatus.readyForDelivery => const [OrderStatus.outForDelivery, OrderStatus.cancelledBySeller],
        OrderStatus.outForDelivery => const [OrderStatus.delivered, OrderStatus.returned],
        OrderStatus.delivered => const [OrderStatus.returned, OrderStatus.refunded],
        OrderStatus.returned => const [OrderStatus.refunded],
        OrderStatus.cancelledByBuyer || OrderStatus.cancelledBySeller => const [OrderStatus.refunded],
        OrderStatus.refunded => const [],
      };

  bool get isFinal => allowedNext.isEmpty;

  /// Progress order for the timeline (cancellation states are off the main path).
  static const flow = [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.readyForDelivery,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];
}

enum OrderType { standard, giftCard, specialRequest }

/// A line of an order: the cart snapshot plus its own status (multi-vendor, SRS §6.7).
class OrderItem {
  const OrderItem({required this.line, required this.status});
  final CartItemModel line;
  final OrderStatus status;

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
        line: CartItemModel.fromMap(map['id'] as String? ?? '', map),
        status: FirestoreParse.enumValue(OrderStatus.values, map['status'], OrderStatus.pending),
      );

  Map<String, dynamic> toMap() => {...line.toMap(), 'id': line.id, 'status': status.name};
}

/// `orders/{orderId}` (SRS §6.7). Created only by the `placeOrder` function.
class OrderModel {
  const OrderModel({
    required this.id,
    required this.orderNumber,
    required this.userId,
    this.storeIds = const [],
    this.items = const [],
    required this.subtotal,
    this.discount = 0,
    this.promoCode,
    this.creditsUsed = 0,
    this.walletUsed = 0,
    this.deliveryFee = 0,
    required this.total,
    this.paymentMethod = PaymentMethod.cashOnDelivery,
    this.paymentStatus = PaymentStatus.pending,
    this.paymentRef,
    this.paymentDueBy,
    this.address,
    this.deliveryDate,
    this.deliverySlot,
    this.isGift = false,
    this.giftMessage,
    this.hidePrices = false,
    this.status = OrderStatus.pending,
    this.cancelReason,
    this.orderType = OrderType.standard,
    this.refundedCredits = 0,
    this.refundedBalance = 0,
    this.referralCredited = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// GG-YYMM-#####
  final String orderNumber;
  final String userId;
  final List<String> storeIds;
  final List<OrderItem> items;
  final int subtotal;
  final int discount;
  final String? promoCode;
  final int creditsUsed;
  final int walletUsed;
  final int deliveryFee;
  final int total;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final String? paymentRef;

  /// Gateway orders (Phase 9, ZainCash): unpaid after this → cancelled (SRS §6.7).
  final DateTime? paymentDueBy;
  final AddressModel? address;

  /// Local calendar date (stored as "yyyy-MM-dd").
  final DateTime? deliveryDate;
  final String? deliverySlot;
  final bool isGift;
  final String? giftMessage;
  final bool hidePrices;
  final OrderStatus status;
  final String? cancelReason;
  final OrderType orderType;

  /// Returned to the customer's wallet on cancellation / refund (Phase 7).
  final int refundedCredits;
  final int refundedBalance;

  /// The referrer's order bonus was paid for this order (SRS §5.19).
  final bool referralCredited;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get itemCount => items.fold(0, (n, i) => n + i.line.qty);

  /// Amount still to collect on delivery (cash on delivery).
  int get amountDue => total;

  int get refundedTotal => refundedCredits + refundedBalance;

  factory OrderModel.fromMap(String id, Map<String, dynamic> map) {
    final address = map['address'];
    return OrderModel(
      id: id,
      orderNumber: map['orderNumber'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      storeIds: FirestoreParse.stringList(map['storeIds']),
      items: FirestoreParse.mapList(map['items']).map(OrderItem.fromMap).toList(),
      subtotal: FirestoreParse.integer(map['subtotal']),
      discount: FirestoreParse.integer(map['discount']),
      promoCode: FirestoreParse.stringOrNull(map['promoCode']),
      creditsUsed: FirestoreParse.integer(map['creditsUsed']),
      walletUsed: FirestoreParse.integer(map['walletUsed']),
      deliveryFee: FirestoreParse.integer(map['deliveryFee']),
      total: FirestoreParse.integer(map['total']),
      paymentMethod: FirestoreParse.enumValue(PaymentMethod.values, map['paymentMethod'], PaymentMethod.cashOnDelivery),
      paymentStatus: FirestoreParse.enumValue(PaymentStatus.values, map['paymentStatus'], PaymentStatus.pending),
      paymentRef: FirestoreParse.stringOrNull(map['paymentRef']),
      paymentDueBy: FirestoreParse.date(map['paymentDueBy']),
      address: address is Map ? AddressModel.fromMap('', Map<String, dynamic>.from(address)) : null,
      deliveryDate: FirestoreParse.date(map['deliveryDate']),
      deliverySlot: FirestoreParse.stringOrNull(map['deliverySlot']),
      isGift: FirestoreParse.boolean(map['isGift']),
      giftMessage: FirestoreParse.stringOrNull(map['giftMessage']),
      hidePrices: FirestoreParse.boolean(map['hidePrices']),
      status: FirestoreParse.enumValue(OrderStatus.values, map['status'], OrderStatus.pending),
      cancelReason: FirestoreParse.stringOrNull(map['cancelReason']),
      orderType: FirestoreParse.enumValue(OrderType.values, map['orderType'], OrderType.standard),
      refundedCredits: FirestoreParse.integer(map['refundedCredits']),
      refundedBalance: FirestoreParse.integer(map['refundedBalance']),
      referralCredited: FirestoreParse.boolean(map['referralCredited']),
      createdAt: FirestoreParse.date(map['createdAt']),
      updatedAt: FirestoreParse.date(map['updatedAt']),
    );
  }
}

/// `orders/{id}/status_history/{id}` (SRS §6.7).
class StatusHistoryEntry {
  const StatusHistoryEntry({required this.status, this.byRole, this.note, this.at});
  final OrderStatus status;
  final String? byRole;
  final String? note;
  final DateTime? at;

  factory StatusHistoryEntry.fromMap(Map<String, dynamic> map) => StatusHistoryEntry(
        status: FirestoreParse.enumValue(OrderStatus.values, map['status'], OrderStatus.pending),
        byRole: FirestoreParse.stringOrNull(map['byRole']),
        note: FirestoreParse.stringOrNull(map['note']),
        at: FirestoreParse.date(map['at']),
      );
}
