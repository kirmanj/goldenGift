import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/store_model.dart';

import '../../../core/data/audit_log.dart';

/// Filters of the Orders table (SRS §9: status, store, date, city, payment).
class OrderFilters {
  const OrderFilters({this.status, this.storeId, this.cityId, this.paymentMethod, this.from, this.to});

  final OrderStatus? status;
  final String? storeId;
  final String? cityId;
  final PaymentMethod? paymentMethod;

  /// Inclusive day range on createdAt.
  final DateTime? from;
  final DateTime? to;

  OrderFilters copyWith({
    OrderStatus? status,
    bool clearStatus = false,
    String? storeId,
    bool clearStore = false,
    String? cityId,
    bool clearCity = false,
    PaymentMethod? paymentMethod,
    bool clearPayment = false,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
  }) =>
      OrderFilters(
        status: clearStatus ? null : (status ?? this.status),
        storeId: clearStore ? null : (storeId ?? this.storeId),
        cityId: clearCity ? null : (cityId ?? this.cityId),
        paymentMethod: clearPayment ? null : (paymentMethod ?? this.paymentMethod),
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
      );

  @override
  bool operator ==(Object other) =>
      other is OrderFilters &&
      other.status == status &&
      other.storeId == storeId &&
      other.cityId == cityId &&
      other.paymentMethod == paymentMethod &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(status, storeId, cityId, paymentMethod, from, to);
}

class AdminOrdersRepository {
  AdminOrdersRepository(this._db);
  final FirebaseFirestore _db;

  static const pageSize = 50;

  /// One query per filter combination: equality filters + createdAt order
  /// (indexes in mobile/firestore.indexes.json).
  Query<Map<String, dynamic>> query(OrderFilters f) {
    Query<Map<String, dynamic>> q = _db.collection(FirestorePaths.orders);
    if (f.status != null) q = q.where('status', isEqualTo: f.status!.name);
    if (f.storeId != null) q = q.where('storeIds', arrayContains: f.storeId);
    if (f.cityId != null) q = q.where('address.city', isEqualTo: f.cityId);
    if (f.paymentMethod != null) q = q.where('paymentMethod', isEqualTo: f.paymentMethod!.name);
    if (f.from != null) {
      q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(f.from!.year, f.from!.month, f.from!.day)));
    }
    if (f.to != null) {
      q = q.where('createdAt', isLessThan: Timestamp.fromDate(DateTime(f.to!.year, f.to!.month, f.to!.day + 1)));
    }
    return q.orderBy('createdAt', descending: true);
  }

  Stream<List<OrderModel>> watch(OrderFilters filters, {int limit = pageSize}) => query(filters)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) OrderModel.fromMap(d.id, d.data())]);

  Stream<OrderModel?> watchOne(String id) => _db
      .doc(FirestorePaths.orderDoc(id))
      .snapshots()
      .map((d) => d.exists ? OrderModel.fromMap(d.id, d.data()!) : null);

  Stream<List<StatusHistoryEntry>> watchHistory(String orderId) => _db
      .collection(FirestorePaths.orderHistory(orderId))
      .orderBy('at')
      .snapshots()
      .map((s) => [for (final d in s.docs) StatusHistoryEntry.fromMap(d.data())]);

  /// Moves the order (and every line) to [next]. The `onOrderStatusChange`
  /// function writes the timeline entry from statusNote / statusUpdatedBy and
  /// notifies the customer.
  ///
  /// Runs in a transaction on a FRESH read of the order: the transition is
  /// re-checked against the stored status, and `items` is rebuilt from the
  /// stored lines (only each line's `status` changes), so a stale [order]
  /// never brings back old data — e.g. the upload URLs that `placeOrder`
  /// rewrites to `orders/{id}/…` after placement. The audit entry is written
  /// in the same transaction.
  Future<void> changeStatus({
    required OrderModel order,
    required OrderStatus next,
    required String adminUid,
    String? note,
  }) async {
    final ref = _db.doc(FirestorePaths.orderDoc(order.id));
    final cleanNote = (note?.trim().isEmpty ?? true) ? null : note!.trim();
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) throw StateError('Order ${order.id} no longer exists');
      final current = OrderStatus.values.where((s) => s.name == data['status']).firstOrNull ?? OrderStatus.pending;
      if (!current.allowedNext.contains(next)) {
        throw StateError('${current.name} → ${next.name} is not allowed');
      }
      // Lines a seller already cancelled (stock released, money refunded) stay
      // cancelled when the rest of the order moves along the delivery flow.
      final onFlow = OrderStatusX.flow.contains(next);
      final items = [
        for (final item in (data['items'] as List? ?? const []))
          if (item is Map)
            {
              ...Map<String, dynamic>.from(item),
              'status': onFlow && _lineOffFlow(item) ? item['status'] : next.name,
            },
      ];
      tx.update(ref, {
        'status': next.name,
        'statusNote': cleanNote,
        'statusUpdatedBy': adminUid,
        'statusUpdatedByRole': 'admin',
        'items': items,
        'updatedAt': FieldValue.serverTimestamp(),
        if (next == OrderStatus.cancelledBySeller) 'cancelReason': cleanNote,
      });
      AuditLog.addTx(tx, _db,
          adminUid: adminUid,
          action: 'order.status',
          target: 'orders/${order.id}',
          before: {'status': current.name},
          after: {'status': next.name, 'note': cleanNote});
    });
  }
}

bool _lineOffFlow(Map<dynamic, dynamic> item) =>
    item['stockReleased'] == true ||
    const {'cancelledBySeller', 'cancelledByBuyer', 'returned', 'refunded'}.contains(item['status']);

final adminOrdersRepositoryProvider =
    Provider<AdminOrdersRepository>((ref) => AdminOrdersRepository(ref.watch(firestoreProvider)));

final adminOrdersProvider = StreamProvider.autoDispose.family<List<OrderModel>, (OrderFilters, int)>(
  (ref, args) => ref.watch(adminOrdersRepositoryProvider).watch(args.$1, limit: args.$2),
);

final adminOrderProvider = StreamProvider.autoDispose.family<OrderModel?, String>(
  (ref, id) => ref.watch(adminOrdersRepositoryProvider).watchOne(id),
);

final adminOrderHistoryProvider = StreamProvider.autoDispose.family<List<StatusHistoryEntry>, String>(
  (ref, id) => ref.watch(adminOrdersRepositoryProvider).watchHistory(id),
);

/// Stores for the Orders "store" filter.
final orderStoreFilterProvider = StreamProvider.autoDispose<List<StoreModel>>((ref) => ref
    .watch(firestoreProvider)
    .collection(FirestorePaths.stores)
    .snapshots()
    .map((s) => [for (final d in s.docs) StoreModel.fromMap(d.id, d.data())]..sort((a, b) => a.name.en.compareTo(b.name.en))));
