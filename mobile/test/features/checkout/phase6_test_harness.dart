import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/addresses/presentation/screens/address_form_screen.dart';
import 'package:golden_gift/features/addresses/presentation/screens/addresses_screen.dart';
import 'package:golden_gift/features/cart/data/cart_stores.dart';
import 'package:golden_gift/features/cart/presentation/providers/cart_controller.dart';
import 'package:golden_gift/features/cart/presentation/providers/cart_lines.dart';
import 'package:golden_gift/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:golden_gift/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:golden_gift/features/checkout/presentation/screens/order_success_screen.dart';
import 'package:golden_gift/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:golden_gift/features/orders/data/orders_repository.dart';
import 'package:golden_gift/features/orders/presentation/screens/order_details_screen.dart';
import 'package:golden_gift/features/orders/presentation/screens/orders_screen.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_platform_providers.dart';
import 'package:golden_gift/features/support/presentation/screens/contact_us_screen.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/address_model.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import '../../helpers/auth_fakes.dart';

/// Firebase-free harness for the Phase 6 screens (Checkout, Order Success,
/// Orders, Order Details, Addresses, Notifications, Contact Us) inside a real
/// GoRouter. Stub routes render where navigation went:
/// `/main?tab=1` → "main tab 1", `/product/p1` → "product p1",
/// `/sign-in` → "/sign-in". `/picker` pushes `/addresses?select=1` and shows
/// the returned address ("picked: Home").

/// In-memory [CartStore].
class MemoryCartStore implements CartStore {
  final items = <String, CartItemModel>{};
  final _changes = StreamController<List<CartItemModel>>.broadcast();
  List<CartItemModel> get _list => items.values.toList();

  @override
  Stream<List<CartItemModel>> watch() async* {
    yield _list;
    yield* _changes.stream;
  }

  @override
  Future<List<CartItemModel>> read() async => _list;

  @override
  Future<void> upsert(CartItemModel item) async {
    items[item.id] = item;
    _changes.add(_list);
  }

  @override
  Future<void> remove(String itemId) async {
    items.remove(itemId);
    _changes.add(_list);
  }

  @override
  Future<void> clear() async {
    items.clear();
    _changes.add(_list);
  }
}

/// Real Firestore reads (same queries as [OrdersRepository], on the fake),
/// scripted `placeOrder` / `cancelOrder`. Independent of the repository's
/// constructor (Firebase Functions / callable invoker).
class FakeOrdersRepository extends Fake implements OrdersRepository {
  FakeOrdersRepository(this._db);
  final FirebaseFirestore _db;

  @override
  Stream<List<OrderModel>> watchMine(String uid) => _db
      .collection(FirestorePaths.orders)
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => [for (final d in s.docs) OrderModel.fromMap(d.id, d.data())]);

  @override
  Stream<OrderModel?> watch(String orderId) => _db
      .doc(FirestorePaths.orderDoc(orderId))
      .snapshots()
      .map((s) => s.exists ? OrderModel.fromMap(s.id, s.data()!) : null);

  @override
  Stream<List<StatusHistoryEntry>> watchHistory(String orderId) => _db
      .collection(FirestorePaths.orderHistory(orderId))
      .orderBy('at')
      .snapshots()
      .map((s) => [for (final d in s.docs) StatusHistoryEntry.fromMap(d.data())]);

  final placeRequests = <PlaceOrderRequest>[];
  final cancelCalls = <(String, String?)>[];

  /// Results for successive `placeOrder` calls: a [PlacedOrder] or an error
  /// to throw. When empty, the call succeeds with [defaultPlaced].
  final placeResults = <Object>[];
  PlacedOrder defaultPlaced = const PlacedOrder(orderId: 'o-new', orderNumber: 'GG-2610-00042', total: 75000);

  /// Holds `placeOrder` open until completed (to see the overlay).
  Completer<void>? placeGate;
  Object? cancelError;

  @override
  Future<PlacedOrder> placeOrder(PlaceOrderRequest request) async {
    placeRequests.add(request);
    if (placeGate != null) await placeGate!.future;
    final next = placeResults.isEmpty ? defaultPlaced : placeResults.removeAt(0);
    if (next is PlacedOrder) return next;
    throw next;
  }

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    cancelCalls.add((orderId, reason));
    if (cancelError != null) throw cancelError!;
  }
}

const testCities = [
  CityModel(id: 'erbil', name: LocalizedText('Erbil', ar: 'أربيل', ku: 'هەولێر'), deliveryFee: 5000),
  CityModel(id: 'duhok', name: LocalizedText('Duhok', ar: 'دهوك', ku: 'دهۆک'), deliveryFee: 4000),
  CityModel(id: 'baghdad', name: LocalizedText('Baghdad', ar: 'بغداد', ku: 'بەغدا'), isActive: false),
];

ProductModel testProduct(String id, {List<String> availableCities = const [], int price = 35000}) => ProductModel(
      id: id,
      title: LocalizedText(id == 'box' ? 'Gift Box' : 'Photo Mug', ar: 'هدية $id', ku: 'دیاری $id'),
      storeId: 's1',
      price: price,
      availableCities: availableCities,
    );

CartItemModel testLine(String id, String productId,
        {int unitPrice = 35000, int qty = 1, int preparationDays = 0, List<CartSelection> selections = const []}) =>
    CartItemModel(
      id: id,
      productId: productId,
      storeId: 's1',
      titleSnapshot: LocalizedText(productId == 'box' ? 'Gift Box' : 'Photo Mug', ar: 'هدية', ku: 'دیاری'),
      unitPrice: unitPrice,
      qty: qty,
      preparationDays: preparationDays,
      selections: selections,
    );

AddressModel testAddress(String id, {String label = 'Home', String city = 'erbil', bool isDefault = false}) =>
    AddressModel(
      id: id,
      label: label,
      name: 'Sara Ahmed',
      phone: '+9647501234567',
      city: city,
      area: 'Ankawa',
      street: '100m Road',
      building: 'B12',
      isDefault: isDefault,
    );

Future<void> seedAddress(FakeFirebaseFirestore db, AddressModel a, {String uid = 'u1'}) =>
    db.doc('users/$uid/addresses/${a.id}').set(a.toMap());

class Phase6Harness {
  Phase6Harness({
    required this.container,
    required this.router,
    required this.orders,
    required this.firestore,
    required this.cart,
    required this.openedLinks,
  });

  final ProviderContainer container;
  final GoRouter router;
  final FakeOrdersRepository orders;
  final FakeFirebaseFirestore firestore;
  final MemoryCartStore cart;
  final List<Uri> openedLinks;

  FakeAnalytics get analytics => container.read(analyticsServiceProvider) as FakeAnalytics;

  /// The top-most page's location (including pushed pages).
  String get location => router.state.uri.toString();
}

Future<Phase6Harness> pumpPhase6(
  WidgetTester tester, {
  required String initialPath,
  bool guest = false,
  FakeFirebaseFirestore? firestore,
  List<CartItemModel> cartItems = const [],
  Map<String, ProductModel> cartProducts = const {},
  List<CityModel> cities = testCities,
  GeneralSettings settings = const GeneralSettings(),
  PaymentSettings payments = const PaymentSettings(),
  DateTime? now,
  Future<bool> Function(Uri uri)? opener,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 2400),
  double textScale = 1,

  /// Extra overrides (providers not overridden above), e.g. a fake callable invoker.
  List<Override> overrides = const [],

  /// Extra pages next to the Phase 6 ones (e.g. the payment status page).
  List<RouteBase> extraRoutes = const [],
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = firestore ?? FakeFirebaseFirestore();
  final User? user = guest ? null : FakeUser(uid: 'u1');
  final orders = FakeOrdersRepository(db);
  final cart = MemoryCartStore();
  for (final item in cartItems) {
    cart.items[item.id] = item;
  }
  final opened = <Uri>[];
  final clock = now ?? DateTime(2026, 10, 21, 9);

  final container = ProviderContainer(overrides: [
    ...appTestOverridesSync(prefs, firestore: db, user: user),
    citiesProvider.overrideWith((ref) => Stream.value(cities)),
    generalSettingsProvider.overrideWith((ref) => Stream.value(settings)),
    paymentSettingsProvider.overrideWith((ref) => Stream.value(payments)),
    ordersRepositoryProvider.overrideWithValue(orders),
    checkoutClockProvider.overrideWithValue(() => clock),
    externalLinkOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return opener == null ? true : await opener(uri);
    }),
    cartControllerProvider.overrideWith((ref) {
      // [cart] is the guest's local cart or the signed-in user's remote one.
      final controller = guest
          ? CartController(remoteStore: (_) => MemoryCartStore(), localStore: cart)
          : CartController(remoteStore: (_) => cart, localStore: MemoryCartStore());
      ref.listen(authStateProvider, (_, next) {
        if (!next.isLoading) controller.onAuthChanged(next.valueOrNull?.uid);
      }, fireImmediately: true);
      return controller;
    }),
    cartProductsProvider.overrideWith((ref) async => cartProducts),
    cartStoresProvider.overrideWith((ref) async => const {}),
    ...overrides,
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: initialPath,
    routes: [
      GoRoute(path: AppRoutes.checkout, builder: (_, __) => const CheckoutScreen()),
      GoRoute(
        path: AppRoutes.orderSuccess,
        builder: (_, state) => OrderSuccessScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(path: AppRoutes.orders, builder: (_, __) => const OrdersScreen()),
      GoRoute(
        path: AppRoutes.orderDetails,
        builder: (_, state) => OrderDetailsScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.addresses,
        builder: (_, state) => AddressesScreen(selectMode: state.uri.queryParameters['select'] == '1'),
      ),
      GoRoute(
        path: AppRoutes.addressForm,
        builder: (_, state) => AddressFormScreen(addressId: state.uri.queryParameters['id']),
      ),
      GoRoute(path: AppRoutes.notifications, builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: AppRoutes.contactUs, builder: (_, __) => const ContactUsScreen()),
      GoRoute(
        path: AppRoutes.main,
        builder: (_, state) => Scaffold(body: Text('main tab ${state.uri.queryParameters['tab']}')),
      ),
      GoRoute(
        path: AppRoutes.productDetails,
        builder: (_, state) => Scaffold(body: Text('product ${state.pathParameters['id']}')),
      ),
      GoRoute(path: '/picker', builder: (_, __) => const _AddressPicker()),
      ...extraRoutes,
      for (final path in [AppRoutes.signIn, AppRoutes.signUp])
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(path))),
    ],
  );

  final appLocale = Locale(locale);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      locale: appLocale,
      theme: AppTheme.lightTheme(appLocale),
      darkTheme: AppTheme.darkTheme(appLocale),
      themeMode: themeMode,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...KurdishFallbackLocalizations.delegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return Phase6Harness(
    container: container,
    router: router,
    orders: orders,
    firestore: db,
    cart: cart,
    openedLinks: opened,
  );
}

class _AddressPicker extends StatefulWidget {
  const _AddressPicker();

  @override
  State<_AddressPicker> createState() => _AddressPickerState();
}

class _AddressPickerState extends State<_AddressPicker> {
  String _picked = 'none';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            Text('picked: $_picked'),
            TextButton(
              onPressed: () async {
                final a = await context.push<AddressModel>('${AppRoutes.addresses}?select=1');
                setState(() => _picked = a?.label ?? 'null');
              },
              child: const Text('open picker'),
            ),
          ],
        ),
      );
}

AppLocalizations l10nFor(String code) => lookupAppLocalizations(Locale(code));

/// The [ElevatedButton] inside the PrimaryButton with [key].
ElevatedButton primaryButton(WidgetTester tester, Key key) =>
    tester.widget<ElevatedButton>(find.descendant(of: find.byKey(key), matching: find.byType(ElevatedButton)));

/// Seeds an `orders/{id}` doc for user u1.
Future<void> seedOrder(
  FakeFirebaseFirestore db,
  String id, {
  String status = 'pending',
  String number = 'GG-2610-00001',
  DateTime? createdAt,
  List<Map<String, dynamic>>? items,
  Map<String, dynamic> extra = const {},
}) =>
    db.doc('orders/$id').set({
      'orderNumber': number,
      'userId': 'u1',
      'subtotal': 70000,
      'deliveryFee': 5000,
      'total': 75000,
      'status': status,
      'paymentMethod': 'cashOnDelivery',
      'paymentStatus': 'pending',
      'createdAt': createdAt ?? DateTime(2026, 10, 20, 12),
      'deliveryDate': '2026-10-22',
      'deliverySlot': 'evening',
      'address': testAddress('a1').toMap(),
      'items': items ??
          [
            {
              'id': 'l1',
              'productId': 'box',
              'storeId': 's1',
              'titleSnapshot': 'Gift Box',
              'unitPrice': 35000,
              'qty': 2,
              'status': status,
            },
          ],
      ...extra,
    });
