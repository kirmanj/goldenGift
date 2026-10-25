import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/core/theme/admin_theme.dart';
import 'package:golden_gift_admin/features/notifications/broadcast_screen.dart';
import 'package:golden_gift_admin/features/notifications/data/broadcast_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../categories/admin_test_harness.dart';

class FakeCalls {
  final sent = <(String, Map<String, dynamic>)>[];
  Object? response = {'notificationId': 'n1', 'sent': 3};
  Object? error;

  Future<Object?> call(String name, Map<String, dynamic> data) async {
    sent.add((name, data));
    if (error != null) throw error!;
    return response;
  }
}

Future<void> pumpBroadcast(WidgetTester tester, FakeFirebaseFirestore db, FakeCalls calls,
    {AdminSession session = testAdmin, Size size = const Size(900, 1400), ThemeMode mode = ThemeMode.light}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      adminAuthProvider.overrideWith((ref) => Stream.value(session)),
      sharedPreferencesProvider.overrideWithValue(prefs),
      broadcastRepositoryProvider.overrideWithValue(BroadcastRepository(db, calls.call)),
    ],
    child: MaterialApp(theme: AdminTheme.light(), darkTheme: AdminTheme.dark(), themeMode: mode, home: const BroadcastScreen()),
  ));
  await settle(tester);
}

/// The English title / message fields (first of each trilingual row).
Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

void main() {
  group('BroadcastRepository', () {
    test('payload keeps every language and drops empty route / image', () {
      final p = BroadcastRepository.payload(
        title: const LocalizedText('Sale', ar: 'تخفيضات', ku: 'داشکاندن'),
        body: const LocalizedText('20% off'),
        route: '  ',
        imageUrl: '',
      );
      expect(p, {
        'title': {'en': 'Sale', 'ar': 'تخفيضات', 'ku': 'داشکاندن'},
        'body': {'en': '20% off', 'ar': null, 'ku': null},
      });
    });

    test('send calls sendBroadcast and reads the result', () async {
      final calls = FakeCalls();
      final repo = BroadcastRepository(FakeFirebaseFirestore(), calls.call);
      final r = await repo.send(title: const LocalizedText('Hi'), body: const LocalizedText('There'), route: '/orders');
      expect(calls.sent.single.$1, 'sendBroadcast');
      expect(calls.sent.single.$2['route'], '/orders');
      expect(r.notificationId, 'n1');
      expect(r.sent, 3);
    });

    test('history lists only broadcasts, newest first', () async {
      final db = FakeFirebaseFirestore();
      Future<void> add(String id, String userId, DateTime at) => db.doc('${FirestorePaths.notifications}/$id').set({
            'userId': userId,
            'title': 'T-$id',
            'body': 'B',
            'type': 'broadcast',
            'createdAt': Timestamp.fromDate(at),
            'sentCount': 7,
          });
      await add('a', 'all', DateTime(2026, 10, 1));
      await add('b', 'u1', DateTime(2026, 10, 2));
      await add('c', 'all', DateTime(2026, 10, 3));
      final list = await BroadcastRepository(db, FakeCalls().call).watchHistory().first;
      expect(list.map((r) => r.notification.id), ['c', 'a']);
      expect(list.first.sentCount, 7);
    });
  });

  group('BroadcastScreen', () {
    testWidgets('requires an English title and message', (tester) async {
      final calls = FakeCalls();
      await pumpBroadcast(tester, FakeFirebaseFirestore(), calls);
      await tester.tap(find.text('Send to all customers'));
      await settle(tester);
      expect(find.text('Required'), findsNWidgets(2));
      expect(calls.sent, isEmpty);
    });

    testWidgets('confirms, sends the trilingual payload and clears the form', (tester) async {
      final calls = FakeCalls();
      await pumpBroadcast(tester, FakeFirebaseFirestore(), calls);
      await tester.enterText(field('Title · English *'), 'Valentine gifts');
      await tester.enterText(field('Title · العربية'), 'هدايا عيد الحب');
      await tester.enterText(field('Message · English *'), 'Order by Feb 12');
      await settle(tester);
      expect(find.text('Valentine gifts'), findsWidgets); // preview

      await tester.tap(find.text('Send to all customers'));
      await settle(tester);
      expect(find.text('Send to every customer?'), findsOneWidget);
      await tester.tap(find.text('Send now'));
      await settle(tester);

      expect(calls.sent, hasLength(1));
      final data = calls.sent.single.$2;
      expect(data['title'], {'en': 'Valentine gifts', 'ar': 'هدايا عيد الحب', 'ku': null});
      expect(data['body'], {'en': 'Order by Feb 12', 'ar': null, 'ku': null});
      expect(data.containsKey('route'), isFalse);
      expect(find.text('Sent to 3 device(s).'), findsOneWidget);
      expect(tester.widget<TextField>(field('Title · English *')).controller!.text, isEmpty);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final calls = FakeCalls();
      await pumpBroadcast(tester, FakeFirebaseFirestore(), calls);
      await tester.enterText(field('Title · English *'), 'Hello');
      await tester.enterText(field('Message · English *'), 'World');
      await tester.tap(find.text('Send to all customers'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(calls.sent, isEmpty);
    });

    testWidgets('explains when the function is not deployed', (tester) async {
      final calls = FakeCalls()..error = FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND');
      await pumpBroadcast(tester, FakeFirebaseFirestore(), calls);
      await tester.enterText(field('Title · English *'), 'Hello');
      await tester.enterText(field('Message · English *'), 'World');
      await tester.tap(find.text('Send to all customers'));
      await settle(tester);
      await tester.tap(find.text('Send now'));
      await settle(tester);
      expect(find.text('The sendBroadcast function is not deployed yet.'), findsOneWidget);
      // The draft is kept so it can be sent later.
      expect(tester.widget<TextField>(field('Title · English *')).controller!.text, 'Hello');
    });

    testWidgets('finance admins cannot send', (tester) async {
      final calls = FakeCalls();
      await pumpBroadcast(tester, FakeFirebaseFirestore(), calls,
          session: const AdminSession(uid: 'f', email: 'f@x', name: 'F', role: AdminRole.finance));
      expect(find.text('Your role cannot send broadcasts.'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text('Send to all customers'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
      expect(button.onPressed, isNull);
    });

    testWidgets('wide dark layout shows history beside the composer', (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('${FirestorePaths.notifications}/n1').set({
        'userId': 'all',
        'title': 'Eid offers',
        'body': 'Up to 30%',
        'type': 'broadcast',
        'data': {'route': '/products?sale=1'},
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1, 9)),
        'sentCount': 120,
      });
      final errors = await errorsOutsideCoreNav(() async {
        await pumpBroadcast(tester, db, FakeCalls(), size: const Size(1440, 1000), mode: ThemeMode.dark);
        expect(find.text('Eid offers'), findsOneWidget);
        expect(find.textContaining('120 device(s)'), findsOneWidget);
      });
      expect(errors, isEmpty);
    });
  });
}
