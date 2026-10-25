import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift_admin/core/router/admin_routes.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/core/theme/admin_theme.dart';
import 'package:golden_gift_admin/features/promo_codes/promo_codes_screen.dart';
import 'package:golden_gift_admin/features/referrals/referrals_screen.dart';
import 'package:golden_gift_admin/features/users/data/users_admin_repository.dart';
import 'package:golden_gift_admin/features/users/user_detail_screen.dart';
import 'package:golden_gift_admin/features/users/users_screen.dart';

import '../categories/admin_test_harness.dart';

/// Records callable invocations; answers per function name or throws [error].
class FakeCalls {
  final sent = <(String, Map<String, dynamic>)>[];
  final responses = <String, Object?>{
    'adjustWallet': {'balance': 0, 'credits': 0, 'txnId': 't1'},
    'setUserBlocked': {'uid': 'u1', 'blocked': true},
  };
  Object? error;

  Future<Object?> call(String name, Map<String, dynamic> data) async {
    sent.add((name, data));
    if (error != null) throw error!;
    return responses[name];
  }
}

AdminSession sessionAs(AdminRole role) => AdminSession(uid: 'admin-${role.name}', email: '${role.name}@x', name: role.name, role: role);

/// One recorded batch: every operation, and whether it was committed.
class SpyBatch implements WriteBatch {
  SpyBatch(this._inner);
  final WriteBatch _inner;
  final ops = <(String, String, Object?)>[];
  bool committed = false;

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    ops.add(('set', document.path, data));
    _inner.set(document, data, options);
  }

  @override
  void update(DocumentReference document, Map<String, dynamic> data) {
    ops.add(('update', document.path, data));
    _inner.update(document, data);
  }

  @override
  void delete(DocumentReference document) {
    ops.add(('delete', document.path, null));
    _inner.delete(document);
  }

  @override
  Future<void> commit() async {
    await _inner.commit();
    committed = true;
  }
}

/// In-memory Firestore that records every batch.
class SpyFirestore extends FakeFirebaseFirestore {
  final batches = <SpyBatch>[];

  @override
  WriteBatch batch() {
    final b = SpyBatch(super.batch());
    batches.add(b);
    return b;
  }
}

Map<String, dynamic> userMap({
  String name = 'Sara Ahmed',
  String phone = '7501234567',
  String? email = 'sara@example.com',
  String? city = 'erbil',
  int totalOrders = 2,
  int totalSpent = 80000,
  bool isBlocked = false,
  bool isDeleted = false,
  String? deviceId = 'dev-1',
  String? referredBy,
  DateTime? createdAt,
}) =>
    {
      'name': name,
      'phone': phone,
      'countryCode': '+964',
      'email': email,
      'city': city,
      'locale': 'en',
      'role': 'customer',
      'referralCode': 'SARA12',
      'referredBy': referredBy,
      'notificationsEnabled': true,
      'fcmTokens': ['tok'],
      'totalOrders': totalOrders,
      'totalSpent': totalSpent,
      'isBlocked': isBlocked,
      'isDeleted': isDeleted,
      'deviceId': deviceId,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 1, 9)),
    };

Future<void> seedUser(FakeFirebaseFirestore db, String uid, Map<String, dynamic> data) =>
    db.doc(FirestorePaths.userDoc(uid)).set(data);

Future<void> seedWallet(FakeFirebaseFirestore db, String uid, {int balance = 20000, int credits = 5000}) =>
    db.doc(FirestorePaths.walletDoc(uid)).set({'balance': balance, 'credits': credits, 'currency': 'IQD'});

Map<String, dynamic> orderData({
  String number = 'GG-2610-00001',
  String userId = 'u1',
  String status = 'delivered',
  String? promoCode,
  int subtotal = 50000,
  int discount = 0,
  int total = 55000,
  DateTime? createdAt,
}) =>
    {
      'orderNumber': number,
      'userId': userId,
      'storeIds': ['s1'],
      'items': const [],
      'subtotal': subtotal,
      'discount': discount,
      'promoCode': promoCode,
      'deliveryFee': 5000,
      'total': total,
      'paymentMethod': 'cashOnDelivery',
      'paymentStatus': 'pending',
      'address': {'name': 'Sara', 'phone': '7501234567', 'city': 'erbil', 'area': 'Ankawa', 'street': '100m'},
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 20, 12)),
    };

Map<String, dynamic> referralData({
  required String referrer,
  required String referred,
  String status = 'pending',
  bool joinPaid = false,
  bool orderPaid = false,
  List<String> flags = const [],
  DateTime? createdAt,
}) =>
    {
      'referrerUid': referrer,
      'referredUid': referred,
      'code': 'SARA12',
      'status': status,
      'joinBonusPaid': joinPaid,
      'orderBonusPaid': orderPaid,
      'flags': flags,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 5)),
    };

/// Lets a page transition finish (settle alone is shorter than the animation).
Future<void> settleRoute(WidgetTester tester) async {
  await tester.pump(); // the frame that navigates
  await tester.pump(const Duration(milliseconds: 600)); // the transition
  await settle(tester);
}

/// Pumps [screen] with the admin overrides, [calls] for the callables and [session].
Future<void> pumpWith(
  WidgetTester tester,
  Widget screen, {
  required FakeFirebaseFirestore db,
  FakeCalls? calls,
  AdminSession session = testAdmin,
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(1440, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides = await adminOverrides(db, session: session);
  // A fresh scope each time: an existing ProviderScope keeps its first overrides.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...overrides,
      usersAdminRepositoryProvider.overrideWithValue(UsersAdminRepository(db, (calls ?? FakeCalls()).call)),
    ],
    child: MaterialApp(theme: AdminTheme.light(), darkTheme: AdminTheme.dark(), themeMode: mode, home: screen),
  ));
  await settle(tester);
}

/// Same, inside a GoRouter with this phase's routes, so links can be followed.
Future<GoRouter> pumpRouted(
  WidgetTester tester, {
  required String location,
  required FakeFirebaseFirestore db,
  FakeCalls? calls,
  AdminSession session = testAdmin,
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(1440, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides = await adminOverrides(db, session: session);
  final router = GoRouter(initialLocation: location, routes: [
    GoRoute(path: AdminRoutes.users, builder: (_, __) => const UsersScreen()),
    GoRoute(path: AdminRoutes.userDetail, builder: (_, s) => UserDetailScreen(uid: s.pathParameters['id']!)),
    GoRoute(path: AdminRoutes.promoCodes, builder: (_, __) => const PromoCodesScreen()),
    GoRoute(path: AdminRoutes.referrals, builder: (_, __) => const ReferralsScreen()),
    GoRoute(path: AdminRoutes.settings, builder: (_, __) => const Scaffold(body: Text('Settings page'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...overrides,
      usersAdminRepositoryProvider.overrideWithValue(UsersAdminRepository(db, (calls ?? FakeCalls()).call)),
    ],
    child: MaterialApp.router(
      theme: AdminTheme.light(),
      darkTheme: AdminTheme.dark(),
      themeMode: mode,
      routerConfig: router,
    ),
  ));
  await settle(tester);
  return router;
}
