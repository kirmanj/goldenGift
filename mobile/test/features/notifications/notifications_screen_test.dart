import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/notification_model.dart';

import '../checkout/phase6_test_harness.dart';

final _en = l10nFor('en');

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  final now = DateTime.now();
  Future<void> add(String id, String title, DateTime at, {bool read = false, String userId = 'u1', String? route}) =>
      db.doc('notifications/$id').set({
        'userId': userId,
        'title': title,
        'titleAr': 'عنوان $id',
        'body': 'Body of $title',
        'type': 'orderStatus',
        'isRead': read,
        'createdAt': at,
        if (route != null) 'data': {'route': route, 'id': 'p1'},
      });
  await add('n1', 'Order confirmed', now.subtract(const Duration(minutes: 5)), route: '/product/p1');
  await add('n2', 'Out for delivery', DateTime(now.year, now.month, now.day - 1, 12), read: true);
  await add('n3', 'Big sale', DateTime(now.year, now.month, now.day - 5, 12), userId: 'all');
  await add('x', 'Not mine', now, userId: 'someone-else');
  return db;
}

void main() {
  testWidgets('grouped by day: today / yesterday / date; only mine + broadcasts', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.notifications, firestore: await _seed());
    final now = DateTime.now();
    expect(find.text(_en.today), findsOneWidget);
    expect(find.text(_en.yesterday), findsOneWidget);
    expect(find.text(AppDates.display(DateTime(now.year, now.month, now.day - 5))), findsOneWidget);
    expect(find.text('Order confirmed'), findsOneWidget);
    expect(find.text('Big sale'), findsOneWidget);
    expect(find.text('Not mine'), findsNothing);
    // Unread rows carry the gold dot.
    expect(find.byKey(const ValueKey('unread-dot-n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-dot-n2')), findsNothing);
    expect(find.byKey(const ValueKey('unread-dot-n3')), findsOneWidget);
  });

  testWidgets('Mark all as read', (tester) async {
    final h = await pumpPhase6(tester, initialPath: AppRoutes.notifications, firestore: await _seed());
    await tester.tap(find.byKey(const ValueKey('mark-all-read')));
    await tester.pumpAndSettle();
    expect((await h.firestore.doc('notifications/n1').get()).data()!['isRead'], isTrue);
    expect(find.byKey(const ValueKey('unread-dot-n1')), findsNothing);
    expect(find.byKey(const ValueKey('unread-dot-n3')), findsNothing); // broadcast: read on this device
    expect(find.byKey(const ValueKey('mark-all-read')), findsNothing);
  });

  testWidgets('swipe deletes', (tester) async {
    final h = await pumpPhase6(tester, initialPath: AppRoutes.notifications, firestore: await _seed());
    await tester.drag(find.byKey(const ValueKey('notification-n2')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Out for delivery'), findsNothing);
    expect((await h.firestore.doc('notifications/n2').get()).exists, isFalse);
  });

  testWidgets('swipe works in RTL too', (tester) async {
    final h = await pumpPhase6(tester, initialPath: AppRoutes.notifications, firestore: await _seed(), locale: 'ar');
    await tester.drag(find.byKey(const ValueKey('notification-n2')), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect((await h.firestore.doc('notifications/n2').get()).exists, isFalse);
  });

  testWidgets('tap marks read and opens the route', (tester) async {
    final h = await pumpPhase6(tester, initialPath: AppRoutes.notifications, firestore: await _seed());
    await tester.tap(find.text('Order confirmed'));
    await tester.pumpAndSettle();
    expect(find.text('product p1'), findsOneWidget);
    expect((await h.firestore.doc('notifications/n1').get()).data()!['isRead'], isTrue);
  });

  testWidgets('a notification without a route only marks read', (tester) async {
    final h = await pumpPhase6(tester, initialPath: AppRoutes.notifications, firestore: await _seed());
    await tester.tap(find.text('Big sale'));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.notifications);
    expect(find.byKey(const ValueKey('unread-dot-n3')), findsNothing);
  });

  testWidgets('empty state', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.notifications);
    expect(find.text(_en.noNotificationsTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('mark-all-read')), findsNothing);
  });

  testWidgets('guests see the sign-in card', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.notifications, guest: true);
    expect(find.byKey(const ValueKey('guest-sign-in-card')), findsOneWidget);
  });

  test('day grouping is newest first; a pending timestamp counts as now', () {
    final now = DateTime(2026, 10, 21, 10);
    NotificationModel n(String id, DateTime? at) =>
        NotificationModel(id: id, userId: 'u1', title: LocalizedText(id), body: LocalizedText.empty, createdAt: at);
    final groups = groupNotificationsByDay([
      n('a', DateTime(2026, 10, 19, 23)),
      n('b', null),
      n('c', DateTime(2026, 10, 21, 1)),
    ], now);
    expect(groups.map((g) => g.$1), [DateTime(2026, 10, 21), DateTime(2026, 10, 19)]);
    expect(groups.first.$2.map((x) => x.id), ['b', 'c']);
    expect(notificationDayLabel(_en, DateTime(2026, 10, 20), now), _en.yesterday);
    expect(notificationDayLabel(_en, DateTime(2026, 10, 19), now), '19/10/2026');
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.light), ('ar', ThemeMode.dark), ('ckb', ThemeMode.dark)]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await pumpPhase6(tester,
            initialPath: AppRoutes.notifications, firestore: await _seed(), locale: locale, themeMode: mode);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('320 px, 1.3× text', (tester) async {
      await pumpPhase6(tester,
          initialPath: AppRoutes.notifications,
          firestore: await _seed(),
          locale: 'ckb',
          size: const Size(320, 1400),
          textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });
}
