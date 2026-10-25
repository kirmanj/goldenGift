import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift_admin/core/router/admin_routes.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/core/theme/admin_theme.dart';
import 'package:golden_gift_admin/features/products/data/products_admin_repository.dart';
import 'package:golden_gift_admin/features/products/product_editor_screen.dart';
import 'package:golden_gift_admin/features/products/products_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testAdmin = AdminSession(
  uid: 'admin-1',
  email: 'ops@goldengift.test',
  name: 'Ops',
  role: AdminRole.superAdmin,
);

/// Fake Firestore that records the operations of every committed batch, so
/// tests can check that a change and its audit entry went out together.
class RecordingFirestore extends FakeFirebaseFirestore {
  final commits = <List<String>>[];

  @override
  WriteBatch batch() => _RecordingBatch(super.batch(), commits);
}

class _RecordingBatch implements WriteBatch {
  _RecordingBatch(this._inner, this._commits);
  final WriteBatch _inner;
  final List<List<String>> _commits;
  final _ops = <String>[];

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    _ops.add('set ${document.path}');
    _inner.set(document, data, options);
  }

  @override
  void update(DocumentReference document, Map<String, dynamic> data) {
    _ops.add('update ${document.path}');
    _inner.update(document, data);
  }

  @override
  void delete(DocumentReference document) {
    _ops.add('delete ${document.path}');
    _inner.delete(document);
  }

  @override
  Future<void> commit() async {
    _commits.add(List.of(_ops));
    _ops.clear();
    await _inner.commit();
  }
}

/// `testWidgets` that ignores ONE known core issue: AdminScaffold's nav
/// header Row (core/widgets/admin_scaffold.dart, not this module) overflows
/// with the square-glyph test font at desktop widths. Every other error —
/// including any overflow in the products screens — still fails the test.
void productsTestWidgets(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final coreNavOverflow = details.exceptionAsString().contains('overflowed') &&
          details.toString().contains('core/widgets/admin_scaffold.dart');
      if (!coreNavOverflow) previous?.call(details);
    };
    try {
      await body(tester);
    } finally {
      FlutterError.onError = previous;
    }
  });
}

/// A store, two categories and two cities — what the editor's pickers read.
Future<void> seedCatalogueBasics(FirebaseFirestore db) async {
  await db.doc('stores/golden-gift-home').set({'name': 'Golden Gift Home', 'status': 'active'});
  await db.doc('categories/frames').set({'title': 'Frames', 'sortOrder': 1, 'isActive': true});
  await db.doc('categories/mugs').set({'title': 'Mugs', 'sortOrder': 0, 'isActive': true});
  await db.doc('app_settings/cities').set({
    'items': [
      {'id': 'erbil', 'name': 'Erbil', 'deliveryFee': 3000, 'isActive': true},
      {'id': 'duhok', 'name': 'Duhok', 'deliveryFee': 4000, 'isActive': true},
    ],
  });
}

/// Writes [p] the way the dashboard does, with an explicit `createdAt`.
Future<void> seedProduct(FirebaseFirestore db, ProductModel p, {required DateTime createdAt}) =>
    db.doc('products/${p.id}').set({
      ...ProductsAdminRepository.productData(p),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(createdAt),
    });

Future<List<Map<String, dynamic>>> auditEntries(FirebaseFirestore db) async =>
    [for (final d in (await db.collection('admin_audit_log').get()).docs) d.data()];

/// The products routes of the real router (incl. the unsaved-changes
/// `onExit`), signed in as [testAdmin], on a desktop-sized window.
Future<GoRouter> pumpProductsApp(
  WidgetTester tester,
  FirebaseFirestore db, {
  String initialLocation = AdminRoutes.products,
  Size size = const Size(1280, 2400),
  ThemeMode themeMode = ThemeMode.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: initialLocation, routes: [
    GoRoute(path: AdminRoutes.products, builder: (_, __) => const ProductsScreen()),
    GoRoute(
      path: AdminRoutes.productNew,
      onExit: ProductEditorGuard.onExit,
      builder: (_, __) => const ProductEditorScreen(),
    ),
    GoRoute(
      path: AdminRoutes.productEdit,
      onExit: ProductEditorGuard.onExit,
      builder: (_, state) => ProductEditorScreen(productId: state.pathParameters['id']),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      firestoreProvider.overrideWithValue(db),
      adminAuthProvider.overrideWith((ref) => Stream.value(testAdmin)),
    ],
    child: MaterialApp.router(
      theme: AdminTheme.light(),
      darkTheme: AdminTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}
