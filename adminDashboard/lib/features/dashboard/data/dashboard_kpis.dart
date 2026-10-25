import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/models/product_model.dart';

import '../../stores/data/stores_admin_repository.dart' show closedLineStatuses;

/// The current instant; tests pin it.
final dashboardClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// One Iraq calendar day (UTC+3, no DST — [AppDates.iraqNow]) as a UTC range.
class IraqDay {
  const IraqDay(this.year, this.month, this.day);

  /// The Iraq day that contains [now].
  factory IraqDay.of(DateTime now) {
    final t = AppDates.iraqNow(now);
    return IraqDay(t.year, t.month, t.day);
  }

  final int year;
  final int month;
  final int day;

  /// Iraq midnight, as a UTC instant (21:00 UTC the evening before).
  DateTime get startUtc => DateTime.utc(year, month, day).subtract(const Duration(hours: 3));
  DateTime get endUtc => DateTime.utc(year, month, day + 1).subtract(const Duration(hours: 3));

  /// [days] calendar days later (negative = earlier).
  IraqDay plus(int days) {
    final d = DateTime.utc(year, month, day + days);
    return IraqDay(d.year, d.month, d.day);
  }

  /// A date-only DateTime for labels.
  DateTime get date => DateTime(year, month, day);

  @override
  bool operator ==(Object other) => other is IraqDay && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => AppDates.isoDate(date);
}

class DayCount {
  const DayCount(this.day, this.count);
  final IraqDay day;
  final int count;
}

/// Statuses whose orders count towards revenue: every status except the
/// cancelled / returned / refunded ones (same rule as the seller KPIs).
final revenueStatuses = [
  for (final s in OrderStatus.values)
    if (!closedLineStatuses.contains(s)) s.name,
];

/// The staff dashboard's numbers (SRS §9 Dashboard). Counts and sums are
/// server-side aggregate queries (1 read per 1000 index entries), never a
/// download of the documents; only the two product lists read documents.
class DashboardRepository {
  DashboardRepository(this._db);
  final FirebaseFirestore _db;

  static const chartDays = 14;
  static const topProductsLimit = 10;
  static const lowStockThreshold = 5;
  static const lowStockLimit = 50;

  Query<Map<String, dynamic>> _ordersOn(IraqDay day) => _db
      .collection(FirestorePaths.orders)
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(day.startUtc))
      .where('createdAt', isLessThan: Timestamp.fromDate(day.endUtc));

  /// Orders placed today (Iraq day), whatever their status.
  Future<int> ordersToday(DateTime now) async => (await _ordersOn(IraqDay.of(now)).count().get()).count ?? 0;

  /// Σ `total` of today's orders, without cancelled / returned / refunded
  /// ones (`status in […]` + createdAt range: index `status + createdAt`).
  Future<int> revenueToday(DateTime now) async {
    final snap =
        await _ordersOn(IraqDay.of(now)).where('status', whereIn: revenueStatuses).aggregate(sum('total')).get();
    return (snap.getSum('total') ?? 0).round();
  }

  /// Orders still waiting for confirmation (any day).
  Future<int> pendingOrders() async =>
      (await _db.collection(FirestorePaths.orders).where('status', isEqualTo: OrderStatus.pending.name).count().get())
          .count ??
      0;

  /// Accounts created today (`users.createdAt`).
  Future<int> newUsersToday(DateTime now) async =>
      (await _db
              .collection(FirestorePaths.users)
              .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(IraqDay.of(now).startUtc))
              .count()
              .get())
          .count ??
      0;

  /// AI Gift Searches logged today (`ai_searches.at`, written by `aiGiftSearch`).
  Future<int> aiSearchesToday(DateTime now) async =>
      (await _db
              .collection(FirestorePaths.aiSearches)
              .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(IraqDay.of(now).startUtc))
              .count()
              .get())
          .count ??
      0;

  /// Orders per Iraq day for the last [days] days, oldest first (today last):
  /// one count aggregate per day.
  Future<List<DayCount>> ordersPerDay(DateTime now, {int days = chartDays}) async {
    final today = IraqDay.of(now);
    final range = [for (var i = days - 1; i >= 0; i--) today.plus(-i)];
    final counts = await Future.wait([for (final d in range) _ordersOn(d).count().get().then((s) => s.count ?? 0)]);
    return [for (var i = 0; i < range.length; i++) DayCount(range[i], counts[i])];
  }

  /// Best sellers by `salesCount` (products that sold at least once).
  Future<List<ProductModel>> topProducts({int limit = topProductsLimit}) async {
    final snap = await _db
        .collection(FirestorePaths.products)
        .where('salesCount', isGreaterThan: 0)
        .orderBy('salesCount', descending: true)
        .limit(limit)
        .get();
    return [for (final d in snap.docs) ProductModel.fromMap(d.id, d.data())];
  }

  /// Products with `stock ≤ 5`, lowest first. Products without a stock
  /// (`null` = unlimited) never match an inequality, so they're excluded.
  Future<List<ProductModel>> lowStock({int threshold = lowStockThreshold, int limit = lowStockLimit}) async {
    final snap = await _db
        .collection(FirestorePaths.products)
        .where('stock', isLessThanOrEqualTo: threshold)
        .orderBy('stock')
        .limit(limit)
        .get();
    return [for (final d in snap.docs) ProductModel.fromMap(d.id, d.data())];
  }
}

final dashboardRepositoryProvider =
    Provider<DashboardRepository>((ref) => DashboardRepository(ref.watch(firestoreProvider)));

DateTime _now(Ref ref) => ref.watch(dashboardClockProvider)();

final kpiOrdersTodayProvider =
    FutureProvider.autoDispose<int>((ref) => ref.watch(dashboardRepositoryProvider).ordersToday(_now(ref)));
final kpiRevenueTodayProvider =
    FutureProvider.autoDispose<int>((ref) => ref.watch(dashboardRepositoryProvider).revenueToday(_now(ref)));
final kpiPendingOrdersProvider =
    FutureProvider.autoDispose<int>((ref) => ref.watch(dashboardRepositoryProvider).pendingOrders());
final kpiNewUsersProvider =
    FutureProvider.autoDispose<int>((ref) => ref.watch(dashboardRepositoryProvider).newUsersToday(_now(ref)));
final kpiAiSearchesProvider =
    FutureProvider.autoDispose<int>((ref) => ref.watch(dashboardRepositoryProvider).aiSearchesToday(_now(ref)));
final ordersPerDayProvider =
    FutureProvider.autoDispose<List<DayCount>>((ref) => ref.watch(dashboardRepositoryProvider).ordersPerDay(_now(ref)));
final topProductsProvider =
    FutureProvider.autoDispose<List<ProductModel>>((ref) => ref.watch(dashboardRepositoryProvider).topProducts());
final lowStockProvider =
    FutureProvider.autoDispose<List<ProductModel>>((ref) => ref.watch(dashboardRepositoryProvider).lowStock());
