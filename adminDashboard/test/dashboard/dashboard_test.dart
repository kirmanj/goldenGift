import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift_admin/features/dashboard/dashboard_screen.dart';
import 'package:golden_gift_admin/features/dashboard/data/dashboard_kpis.dart';
import 'package:golden_gift_admin/features/dashboard/widgets/dashboard_widgets.dart';

import '../seller/phase8_test_harness.dart';

/// 12:00 in Iraq on 21 Oct 2026 (09:00 UTC).
final now = DateTime.utc(2026, 10, 21, 9);

Future<void> seedOrder(FirebaseFirestore db, String id, {required String status, required int total, required DateTime at}) =>
    db.doc(FirestorePaths.orderDoc(id)).set({
      ...multiStoreOrder(number: 'GG-$id', status: status, createdAt: at),
      'total': total,
    });

/// Orders around the Iraq midnight boundary, users, AI searches and products.
Future<FakeFirebaseFirestore> kpiWorld() async {
  final db = FakeFirebaseFirestore();
  // 23:59 Iraq time on the 20th → yesterday.
  await seedOrder(db, 'y1', status: 'delivered', total: 10000, at: DateTime.utc(2026, 10, 20, 20, 59));
  // 00:00 Iraq time on the 21st → today.
  await seedOrder(db, 't1', status: 'pending', total: 20000, at: DateTime.utc(2026, 10, 20, 21));
  await seedOrder(db, 't2', status: 'confirmed', total: 30000, at: DateTime.utc(2026, 10, 21, 8));
  await seedOrder(db, 't3', status: 'cancelledByBuyer', total: 40000, at: DateTime.utc(2026, 10, 21, 8, 30));
  await seedOrder(db, 't4', status: 'refunded', total: 5000, at: DateTime.utc(2026, 10, 21, 8, 45));
  await seedOrder(db, 'old', status: 'pending', total: 1000, at: DateTime.utc(2026, 10, 10, 10));

  await db.doc('users/new').set({'name': 'New', 'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 20, 21, 30))});
  await db.doc('users/yesterday').set({'name': 'Old', 'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 20, 20))});
  await db.doc('users/legacy').set({'name': 'No date'});

  for (final (id, at) in [
    ('a1', DateTime.utc(2026, 10, 21, 7)),
    ('a2', DateTime.utc(2026, 10, 20, 21, 1)),
    ('a0', DateTime.utc(2026, 10, 20, 20, 59)),
  ]) {
    await db.doc('${FirestorePaths.aiSearches}/$id').set({'query': 'gift for mum', 'locale': 'en', 'at': Timestamp.fromDate(at)});
  }

  for (var i = 0; i <= 12; i++) {
    await db.doc('products/sold-$i').set({'title': 'Product $i', 'storeId': 'store-a', 'price': 1000 * (i + 1), 'salesCount': i});
  }
  for (final (id, stock) in [('low-0', 0), ('low-5', 5), ('ok-6', 6), ('low-2', 2)]) {
    await db.doc('products/$id').set({'title': 'Stock $id', 'storeId': 'store-a', 'price': 5000, 'stock': stock});
  }
  await db.doc('products/unlimited').set({'title': 'Unlimited', 'storeId': 'store-a', 'price': 5000, 'stock': null});
  return db;
}

List<Override> pinnedClock() => [dashboardClockProvider.overrideWithValue(() => now)];

Finder inTile(String label, Finder matching) =>
    find.descendant(of: find.widgetWithText(KpiTile, label), matching: matching);

void main() {
  group('Iraq day', () {
    test('Iraq midnight is 21:00 UTC the evening before', () {
      final today = IraqDay.of(now);
      expect(today, const IraqDay(2026, 10, 21));
      expect(today.startUtc, DateTime.utc(2026, 10, 20, 21));
      expect(today.endUtc, DateTime.utc(2026, 10, 21, 21));
      expect(IraqDay.of(DateTime.utc(2026, 10, 20, 20, 59)), const IraqDay(2026, 10, 20));
      expect(IraqDay.of(DateTime.utc(2026, 10, 20, 21)), const IraqDay(2026, 10, 21));
      expect(today.plus(-21), const IraqDay(2026, 9, 30), reason: 'across a month');
      expect(const IraqDay(2026, 12, 31).plus(1), const IraqDay(2027, 1, 1));
    });
  });

  group('KPIs', () {
    test('today in Iraq time; revenue without cancelled / returned / refunded orders', () async {
      final repo = DashboardRepository(await kpiWorld());
      expect(await repo.ordersToday(now), 4);
      expect(await repo.revenueToday(now), 50000);
      expect(await repo.pendingOrders(), 2);
      expect(await repo.newUsersToday(now), 1);
      expect(await repo.aiSearchesToday(now), 2);
    });

    test('orders per day: 14 Iraq days, oldest first', () async {
      final days = await DashboardRepository(await kpiWorld()).ordersPerDay(now);
      expect(days, hasLength(14));
      expect(days.first.day, const IraqDay(2026, 10, 8));
      expect(days.last.day, const IraqDay(2026, 10, 21));
      expect([for (final d in days) d.count], [0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 4]);
    });

    test('top products by salesCount; low stock ≤ 5 lowest first, unlimited excluded', () async {
      final repo = DashboardRepository(await kpiWorld());
      final top = await repo.topProducts();
      expect(top, hasLength(10));
      expect(top.first.id, 'sold-12');
      expect(top.last.id, 'sold-3');
      expect(top.any((p) => p.salesCount == 0), isFalse);
      expect([for (final p in await repo.lowStock()) p.id], ['low-0', 'low-2', 'low-5']);
    });
  });

  group('screen', () {
    testWidgets('tiles, chart, top products and low stock', (tester) async {
      final db = await kpiWorld();
      await pumpPhase8(tester, const DashboardScreen(), db: db, size: const Size(1440, 1400), overrides: pinnedClock());
      expect(find.textContaining('Today · Wed, Oct 21 · Iraq time'), findsOneWidget);
      expect(inTile('Orders today', find.text('4')), findsOneWidget);
      expect(inTile('Revenue today', find.text('50,000 IQD')), findsOneWidget);
      expect(inTile('Pending orders', find.text('2')), findsOneWidget);
      expect(inTile('New users today', find.text('1')), findsOneWidget);
      expect(inTile('AI searches today', find.text('2')), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('6 total'), findsOneWidget, reason: 'orders in the 14-day chart');
      expect(find.text('Product 12'), findsOneWidget);
      expect(find.text('12 sold'), findsOneWidget);
      expect(find.text('Product 2'), findsNothing, reason: 'only the top 10');
      expect(find.text('Out of stock'), findsOneWidget);
      expect(find.text('2 left'), findsOneWidget);
      expect(find.text('Stock ok-6'), findsNothing);
      expect(find.text('Unlimited'), findsNothing);
      expect(inTile('Products', find.text('18')), findsOneWidget, reason: 'catalogue counts kept');

      await tester.tap(find.text('Product 12'));
      await settle(tester);
      expect(find.text('visited: /products/sold-12'), findsOneWidget);
    });

    testWidgets('a loading tile shows a skeleton; a failed one an inline error that retries', (tester) async {
      final db = await kpiWorld();
      var aiCalls = 0;
      await pumpPhase8(tester, const DashboardScreen(), db: db, size: const Size(1440, 1400), overrides: [
        ...pinnedClock(),
        kpiOrdersTodayProvider.overrideWith((ref) => Completer<int>().future),
        kpiAiSearchesProvider.overrideWith((ref) async {
          aiCalls++;
          if (aiCalls == 1) throw StateError('index missing');
          return 7;
        }),
      ]);
      expect(inTile('Orders today', find.byKey(const ValueKey('skeleton'))), findsOneWidget);
      expect(inTile('AI searches today', find.text('Couldn’t load')), findsOneWidget);
      expect(inTile('Revenue today', find.text('50,000 IQD')), findsOneWidget, reason: 'one failure never blanks the page');

      await tester.tap(inTile('AI searches today', find.text('Retry')));
      await settle(tester);
      expect(inTile('AI searches today', find.text('7')), findsOneWidget);
      expect(aiCalls, 2);
    });

    testWidgets('an empty project shows zeros and empty lists', (tester) async {
      await pumpPhase8(tester, const DashboardScreen(), db: FakeFirebaseFirestore(), overrides: pinnedClock());
      expect(inTile('Revenue today', find.text('0 IQD')), findsOneWidget);
      expect(find.text('No sales yet.'), findsOneWidget);
      expect(find.text('No products are low on stock.'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('partners keep their own KPIs (no platform numbers)', (tester) async {
      final db = await kpiWorld();
      await seedStore(db, 'store-a');
      await pumpPhase8(tester, const DashboardScreen(), db: db, session: sellerSession, overrides: pinnedClock());
      expect(find.text('To confirm'), findsOneWidget);
      expect(find.text('AI searches today'), findsNothing);
      expect(find.byType(BarChart), findsNothing);
    });

    for (final (mode, size) in layoutMatrix) {
      testWidgets('lays out in ${mode.name} at ${size.width.toInt()} px', (tester) async {
        final db = await kpiWorld();
        final errors = await errorsOutsideCoreNav(() async {
          await pumpPhase8(tester, const DashboardScreen(), db: db, mode: mode, size: size, overrides: pinnedClock());
          expect(find.byType(BarChart), findsOneWidget);
          await tester.drag(
              find.descendant(of: find.byType(StaffDashboardBody), matching: find.byType(ListView)), const Offset(0, -800));
          await settle(tester);
        });
        expect(errors, isEmpty);
      });
    }
  });
}
