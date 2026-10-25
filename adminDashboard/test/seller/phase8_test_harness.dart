import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/services/callable.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/core/theme/admin_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../categories/admin_test_harness.dart';

export '../categories/admin_test_harness.dart' show auditEntries, errorsOutsideCoreNav, settle, testAdmin;

/// Records callable invocations; answers from [responses] or throws [errors].
class FakeCallables {
  final calls = <(String, Map<String, dynamic>)>[];
  final responses = <String, Object?>{};
  final errors = <String, Object>{};

  Future<Object?> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    final error = errors[name];
    if (error != null) throw error;
    return responses[name] ?? const <String, dynamic>{};
  }

  List<Map<String, dynamic>> payloadsFor(String name) => [for (final (n, d) in calls) if (n == name) d];
}

/// A partner signed in with claim `seller == store-a`.
const sellerSession = AdminSession(
  uid: 'seller-1',
  email: 'owner@partner.test',
  name: 'Store A owner',
  role: AdminRole.seller,
  storeId: 'store-a',
);

AdminSession staffSession(AdminRole role) =>
    AdminSession(uid: 'staff-${role.name}', email: '${role.name}@goldengift.test', name: 'Staff ${role.name}', role: role);

/// Pumps [screen] at `/` in a router whose other paths render "visited: …"
/// (so links / context.go can be asserted), with a fake Firestore, the given
/// session and fake callables.
Future<void> pumpPhase8(
  WidgetTester tester,
  Widget screen, {
  required FakeFirebaseFirestore db,
  AdminSession session = testAdmin,
  FakeCallables? calls,
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(1280, 1000),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final fake = calls ?? FakeCallables();
  Widget visited(GoRouterState s) => Scaffold(body: Text('visited: ${s.uri}'));
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(path: '/', builder: (_, __) => screen),
    GoRoute(path: '/:a', builder: (_, s) => visited(s)),
    GoRoute(path: '/:a/:b', builder: (_, s) => visited(s)),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      adminAuthProvider.overrideWith((ref) => Stream.value(session)),
      sharedPreferencesProvider.overrideWithValue(prefs),
      callableInvokerProvider.overrideWithValue(fake.call),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AdminTheme.light(),
      darkTheme: AdminTheme.dark(),
      themeMode: mode,
      routerConfig: router,
    ),
  ));
  await settle(tester);
}

/// Every layout the dashboard must survive (SRS §2.3: light + dark; narrow + desktop).
const layoutMatrix = [
  (ThemeMode.light, Size(800, 1200)),
  (ThemeMode.dark, Size(800, 1200)),
  (ThemeMode.light, Size(1440, 1000)),
  (ThemeMode.dark, Size(1440, 1000)),
];

Future<void> seedStore(
  FirebaseFirestore db,
  String id, {
  String name = 'Store',
  String status = 'active',
  double commission = 10,
  String? ownerUid,
  String? city = 'erbil',
  DateTime? createdAt,
}) =>
    db.doc(FirestorePaths.storeDoc(id)).set({
      'name': name,
      'description': 'Hand made',
      'status': status,
      'commissionPercent': commission,
      'ownerUid': ownerUid ?? 'owner-$id',
      'phone': '+9647501234567',
      'city': city,
      'productCount': 3,
      'ordersCount': 2,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 1)),
    });

Map<String, dynamic> orderLine(String id, String storeId,
        {String title = 'Mug', int unitPrice = 10000, int qty = 1, String status = 'pending'}) =>
    {
      'id': id,
      'productId': 'p-$id',
      'storeId': storeId,
      'titleSnapshot': title,
      'unitPrice': unitPrice,
      'qty': qty,
      'lineTotal': unitPrice * qty,
      'status': status,
      'selections': const [],
    };

/// A two-store order: store-a's engraved mug + store-b's frame.
Map<String, dynamic> multiStoreOrder({
  String number = 'GG-2610-00001',
  String status = 'pending',
  String aStatus = 'pending',
  String bStatus = 'pending',
  DateTime? createdAt,
}) =>
    {
      'orderNumber': number,
      'userId': 'customer-1',
      'storeIds': ['store-a', 'store-b'],
      'items': [
        orderLine('l1', 'store-a', title: 'Engraved Mug', unitPrice: 15000, qty: 2, status: aStatus),
        orderLine('l2', 'store-b', title: 'Walnut Frame', unitPrice: 42000, status: bStatus),
      ],
      'subtotal': 72000,
      'deliveryFee': 5000,
      'total': 77000,
      'paymentMethod': 'cashOnDelivery',
      'paymentStatus': 'pending',
      'address': {'name': 'Sara', 'phone': '+9647501234567', 'city': 'erbil', 'area': 'Ankawa', 'street': '100m'},
      'deliveryDate': '2026-10-25',
      'isGift': false,
      'hidePrices': false,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 20, 12)),
    };
