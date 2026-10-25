import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/core/theme/admin_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared by the categories, banners and settings tests: an in-memory
/// Firestore and a signed-in admin, so AdminScaffold lets the page through.
const testAdmin = AdminSession(
  uid: 'admin-1',
  email: 'admin@goldengift.test',
  name: 'Test Admin',
  role: AdminRole.superAdmin,
);

Future<List<Override>> adminOverrides(FakeFirebaseFirestore db, {AdminSession session = testAdmin}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    firestoreProvider.overrideWithValue(db),
    adminAuthProvider.overrideWith((ref) => Stream.value(session)),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ];
}

/// Pumps [screen] at [size] logical pixels in light or dark mode.
Future<void> pumpAdminScreen(
  WidgetTester tester,
  Widget screen, {
  required FakeFirebaseFirestore db,
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(800, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides = await adminOverrides(db);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AdminTheme.light(),
      darkTheme: AdminTheme.dark(),
      themeMode: mode,
      home: screen,
    ),
  ));
  await settle(tester);
}

/// Lets Firestore streams deliver (pumpAndSettle would spin on progress indicators).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Runs [body] collecting Flutter errors instead of failing on the first, and
/// returns those not caused by the known core issue: AdminScaffold's nav
/// header Row (admin_scaffold.dart) overflows with the square-glyph test font
/// at desktop widths, where the 248 px side nav is shown.
Future<List<FlutterErrorDetails>> errorsOutsideCoreNav(Future<void> Function() body) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors.where((e) => !e.toString().contains('core/widgets/admin_scaffold.dart')).toList();
}

Future<List<Map<String, dynamic>>> auditEntries(FakeFirebaseFirestore db) async =>
    [for (final d in (await db.collection(FirestorePaths.adminAuditLog).get()).docs) d.data()];
