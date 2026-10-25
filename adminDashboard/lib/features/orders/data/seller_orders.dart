import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/services/callable.dart';
import 'package:golden_gift/models/order_model.dart';

import '../../stores/data/callable_errors.dart';
import '../../stores/data/stores_admin_repository.dart' show storeLines;

/// A partner's view of an order (SRS §9 "Seller view", §10 Phase 8): only
/// their own lines, amounts limited to those lines, no other store's prices,
/// no customer account id. Delivery info (address, date, gift message) stays.
///
/// [packingSlip] forces `hidePrices` (the seller's printout never shows
/// amounts — the courier collects the whole order's total).
OrderModel sellerOrderView(OrderModel order, String storeId, {bool packingSlip = false}) {
  final lines = storeLines(order, storeId);
  final total = lines.fold(0, (n, i) => n + i.line.lineTotal);
  return OrderModel(
    id: order.id,
    orderNumber: order.orderNumber,
    userId: '',
    storeIds: [storeId],
    items: lines,
    subtotal: total,
    total: total,
    paymentMethod: order.paymentMethod,
    paymentStatus: order.paymentStatus,
    address: order.address,
    deliveryDate: order.deliveryDate,
    deliverySlot: order.deliverySlot,
    isGift: order.isGift,
    giftMessage: order.giftMessage,
    hidePrices: packingSlip || order.hidePrices,
    status: order.status,
    cancelReason: order.cancelReason,
    orderType: order.orderType,
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
  );
}

/// The status of a seller's lines: the least advanced line still on the
/// main flow (pending → delivered); when every line left it (cancelled,
/// returned, refunded), the first line's status. Null without lines.
OrderStatus? sellerLinesStatus(List<OrderItem> lines) {
  if (lines.isEmpty) return null;
  const flow = OrderStatusX.flow;
  final onFlow = lines.where((l) => flow.contains(l.status)).toList();
  if (onFlow.isEmpty) return lines.first.status;
  return onFlow.map((l) => l.status).reduce((a, b) => flow.indexOf(a) <= flow.indexOf(b) ? a : b);
}

/// What a seller may set for their lines: the shared [OrderStatusX.allowedNext]
/// minus refunds (money is handled by Golden Gift's finance team). A seller
/// never moves the whole order — the function derives it from the lines.
List<OrderStatus> sellerTransitions(OrderStatus? current) =>
    current == null ? const [] : current.allowedNext.where((s) => s != OrderStatus.refunded).toList();

/// `updateOrderItems` (seller): sets the caller's lines to [status] and
/// derives the order status as the least advanced line status.
class SellerOrdersRepository {
  SellerOrdersRepository(this._call);
  final CallableInvoker _call;

  static Map<String, dynamic> payload({required String orderId, required OrderStatus status, String? note}) => {
        'orderId': orderId,
        'status': status.name,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      };

  /// Returns the order's derived status (null when the server didn't say).
  Future<OrderStatus?> updateItems({required String orderId, required OrderStatus status, String? note}) async {
    final data = callableMap(await _call('updateOrderItems', payload(orderId: orderId, status: status, note: note)));
    final s = data['status'];
    return OrderStatus.values.where((v) => v.name == s).firstOrNull;
  }
}

final sellerOrdersRepositoryProvider = Provider<SellerOrdersRepository>((ref) => SellerOrdersRepository(lazyCallable(ref)));
