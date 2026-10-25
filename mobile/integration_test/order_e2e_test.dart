// End-to-end Phase 6 exit check (SRS §8 "integration test for sign-up → order",
// §10): a new customer signs up with phone OTP, puts a product in the cart,
// places a cash-on-delivery order through the real Checkout screen, and the
// order moves through its statuses with a timeline entry and a notification
// each time (written by `placeOrder` / `onOrderStatusChange`).
//
// Runs the real app on a simulator against the local Emulator Suite with the
// dev-data seed (cities, delivery fees, settings):
//   (repo root)        firebase emulators:start --only auth,firestore,functions,storage --project goldengift-iq
//   (mobile/functions) npm run seed:emulator
//   (mobile)           flutter test integration_test/order_e2e_test.dart -d <simulator> --dart-define=USE_EMULATOR=true
//
// The emulators enforce the PRODUCTION rules, so the steps only staff may do
// (creating the test product, moving the order through its statuses) go
// through the Firestore emulator's REST API as `owner`, which bypasses rules —
// the same writes the dashboard makes.
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/config/app_env.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/widgets/main_shell.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/addresses/data/address_repository.dart';
import 'package:golden_gift/features/cart/presentation/providers/cart_controller.dart';
import 'package:golden_gift/features/checkout/presentation/screens/order_success_screen.dart';
import 'package:golden_gift/firebase_options.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/main.dart';
import 'package:golden_gift/models/address_model.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emulator_admin.dart';

final _db = FirebaseFirestore.instance;
const _server = GetOptions(source: Source.server);

/// Polls the server until [read] returns a value (functions run asynchronously).
Future<T> _eventually<T>(Future<T?> Function() read, String what,
    {int tries = 80}) async {
  for (var i = 0; i < tries; i++) {
    final v = await read();
    if (v != null) return v;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError(
      'timed out waiting for $what — is the functions emulator up?');
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder,
    {int maxTries = 120}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw StateError('timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(AppEnv.useEmulator, isTrue,
        reason: 'run with --dart-define=USE_EMULATOR=true');
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await configureFirebase();
  });

  testWidgets(
      'sign up → cart → cash-on-delivery order → statuses + notifications',
      (tester) async {
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setBool('onboarding_done', true);
    await prefs.setString('locale', 'en');
    final l10n = lookupAppLocalizations(const Locale('en'));

    // ── Sign up ──
    final national = '750${Random().nextInt(9000000) + 1000000}';
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const GoldenGiftApp(),
    ));
    await _pumpUntil(tester, find.text(l10n.createYourAccount));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'E2E Order User');
    await tester.enterText(fields.at(2), national);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.scrollUntilVisible(find.byType(PrimaryButton), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PrimaryButton));
    await _pumpUntil(tester, find.text(l10n.otpTitle));
    await tester.enterText(
        find.byType(TextField), await emulatorCode('+964$national'));
    await _pumpUntil(tester, find.byType(MainShell));
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await _eventually(
        () async =>
            (await _db.doc(FirestorePaths.walletDoc(uid)).get(_server)).exists
                ? true
                : null,
        'onUserCreate');

    // ── A product with one unit left, no options ──
    final productId = 'e2e-${DateTime.now().millisecondsSinceEpoch}';
    await adminWrite(FirestorePaths.productDoc(productId), {
      'title': 'E2E Engraved Pen',
      'titleAr': 'قلم محفور',
      'titleKu': 'قەڵەمی هەڵکۆڵراو',
      'description': 'Integration test product',
      'storeId': 'golden-gift-home',
      'categoryIds': <String>[],
      'images': <String>[],
      'price': 25000,
      'currency': 'IQD',
      'isActive': true,
      'isFeatured': false,
      'availability': 'sameDay',
      'preparationDays': 0,
      'availableCities': <String>[],
      'stock': 1,
      'salesCount': 0,
      'optionGroups': <Map<String, dynamic>>[],
      'createdAt': DateTime.now(),
    });

    // ── Cart + address through the app's own providers ──
    final container =
        ProviderScope.containerOf(tester.element(find.byType(MainShell)));
    await container.read(cartControllerProvider.notifier).add(CartItemModel(
          id: 'line-$productId',
          productId: productId,
          storeId: 'golden-gift-home',
          titleSnapshot: const LocalizedText('E2E Engraved Pen'),
          unitPrice: 25000,
          qty: 1,
        ));
    await container.read(addressRepositoryProvider).save(
          uid,
          AddressModel(
            id: '',
            label: 'Home',
            name: 'E2E Order User',
            phone: '+964$national',
            city: 'erbil',
            area: 'Ankawa',
            street: '100m Road',
            isDefault: true,
          ),
        );

    // ── Checkout → Place order ──
    container.read(appRouterProvider).push(AppRoutes.checkout);
    const place = ValueKey('place-order');
    await _pumpUntil(tester, find.byKey(place));
    await tester.pump(
        const Duration(seconds: 1)); // settings / cities / address streams
    await tester.tap(find.byKey(place));
    await _pumpUntil(tester, find.byType(OrderSuccessScreen), maxTries: 160);

    final orders = await _db
        .collection(FirestorePaths.orders)
        .where('userId', isEqualTo: uid)
        .get(_server);
    expect(orders.docs, hasLength(1));
    final orderRef = orders.docs.single.reference;
    final order = orders.docs.single.data();
    expect(order['orderNumber'], matches(RegExp(r'^GG-\d{4}-\d{5}$')));
    expect(order['status'], 'pending');
    expect(order['paymentMethod'], 'cashOnDelivery');
    expect(order['subtotal'], 25000);
    expect(order['deliveryFee'], greaterThan(0),
        reason: 'Erbil fee from the seeded app_settings/cities');
    expect(order['total'], 25000 + (order['deliveryFee'] as num));
    expect((order['items'] as List).single['status'], 'pending');
    expect(
        (await _db.doc(FirestorePaths.productDoc(productId)).get(_server))
            .data()!['stock'],
        0);
    expect(
        (await _db.collection(FirestorePaths.cartItems(uid)).get(_server)).docs,
        isEmpty);
    expect(find.textContaining(order['orderNumber'] as String), findsWidgets);

    // ── Ops moves it through every status; each change → timeline + notification ──
    final flow = [
      'confirmed',
      'preparing',
      'readyForDelivery',
      'outForDelivery',
      'delivered'
    ];
    for (var i = 0; i < flow.length; i++) {
      final items = [
        for (final it in (order['items'] as List))
          {...(it as Map<String, dynamic>), 'status': flow[i]}
      ];
      await adminWrite(orderRef.path, {
        'status': flow[i],
        'statusNote': 'E2E step ${i + 1}',
        'statusUpdatedBy': 'e2e-admin',
        'statusUpdatedByRole': 'admin',
        'items': items,
        'updatedAt': DateTime.now(),
      });
      await _eventually(() async {
        final h = await orderRef
            .collection(FirestorePaths.statusHistory)
            .get(_server);
        return h.docs.length >= i + 2 ? true : null;
      }, 'status_history for ${flow[i]}');
    }
    final history = (await orderRef
            .collection(FirestorePaths.statusHistory)
            .orderBy('at')
            .get(_server))
        .docs
        .map((d) => d.data()['status'])
        .toList();
    expect(history, ['pending', ...flow]);

    final delivered = await _eventually(() async {
      final d = (await orderRef.get(_server)).data()!;
      return d['paymentStatus'] == 'paid' ? d : null;
    }, 'COD paid on delivery');
    expect(delivered['status'], 'delivered');

    final notes = await _eventually(() async {
      final n = await _db
          .collection(FirestorePaths.notifications)
          .where('userId', isEqualTo: uid)
          .get(_server);
      return n.docs.length >= flow.length ? n.docs : null;
    }, 'order notifications');
    expect(
        notes.every((d) =>
            (d.data()['data'] as Map)['route'] == AppRoutes.order(orderRef.id)),
        isTrue);
  });
}
