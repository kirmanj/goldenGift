import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/models/order_model.dart';

import '../../stores/data/stores_admin_repository.dart' show closedLineStatuses, storeLines;

/// A partner's own KPIs (SRS §9 "Seller view" → Dashboard), computed from
/// ONLY their lines of the orders that contain their store.
class SellerKpis {
  const SellerKpis({
    required this.ordersToday,
    required this.pending,
    required this.inProgress,
    required this.revenue,
    required this.ordersInWindow,
  });

  /// Orders placed today (local day) that contain the store.
  final int ordersToday;

  /// Orders with at least one of the seller's lines still `pending` (to confirm).
  final int pending;

  /// Orders with a line confirmed / preparing / ready / out for delivery.
  final int inProgress;

  /// Σ lineTotal of the seller's lines in the window, without cancelled /
  /// returned / refunded lines.
  final int revenue;
  final int ordersInWindow;

  static const windowDays = 30;
  static const maxOrders = 500;

  static const _inProgress = {
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.readyForDelivery,
    OrderStatus.outForDelivery,
  };

  factory SellerKpis.of(List<OrderModel> orders, String storeId, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    var ordersToday = 0, pending = 0, inProgress = 0, revenue = 0, count = 0;
    for (final o in orders) {
      final lines = storeLines(o, storeId);
      if (lines.isEmpty) continue;
      count++;
      final placed = o.createdAt?.toLocal();
      if (placed != null && !placed.isBefore(today)) ordersToday++;
      if (lines.any((l) => l.status == OrderStatus.pending)) pending++;
      if (lines.any((l) => _inProgress.contains(l.status))) inProgress++;
      for (final l in lines) {
        if (!closedLineStatuses.contains(l.status)) revenue += l.line.lineTotal;
      }
    }
    return SellerKpis(
      ordersToday: ordersToday,
      pending: pending,
      inProgress: inProgress,
      revenue: revenue,
      ordersInWindow: count,
    );
  }
}

/// Orders containing the store in the last [SellerKpis.windowDays] days
/// (index `storeIds` CONTAINS + `createdAt`, already deployed for Orders).
final sellerRecentOrdersProvider = StreamProvider.autoDispose.family<List<OrderModel>, String>((ref, storeId) {
  final since = DateTime.now().subtract(const Duration(days: SellerKpis.windowDays));
  return ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.orders)
      .where('storeIds', arrayContains: storeId)
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
      .orderBy('createdAt', descending: true)
      .limit(SellerKpis.maxOrders)
      .snapshots()
      .map((s) => [for (final d in s.docs) OrderModel.fromMap(d.id, d.data())]);
});

/// The store's products (single-field `storeId` filter, aggregate count).
final sellerProductCountProvider = FutureProvider.autoDispose.family<int, String>((ref, storeId) async {
  final snap =
      await ref.watch(firestoreProvider).collection(FirestorePaths.products).where('storeId', isEqualTo: storeId).count().get();
  return snap.count ?? 0;
});
