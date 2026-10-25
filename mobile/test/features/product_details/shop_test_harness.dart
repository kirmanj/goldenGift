import 'dart:async';
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/cart/data/cart_stores.dart';
import 'package:golden_gift/features/cart/presentation/providers/cart_controller.dart';
import 'package:golden_gift/features/cart/presentation/providers/cart_lines.dart';
import 'package:golden_gift/features/cart/presentation/screens/cart_screen.dart';
import 'package:golden_gift/features/product_details/data/photo_service.dart';
import 'package:golden_gift/features/product_details/data/product_repository.dart';
import 'package:golden_gift/features/product_details/domain/product_configuration.dart';
import 'package:golden_gift/features/product_details/presentation/screens/product_details_screen.dart';
import 'package:golden_gift/features/wishlist/presentation/screens/wishlist_screen.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/store_model.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_fakes.dart';

/// Firebase-free harness for the Phase 4 shopping screens (Product Details,
/// Cart, Wishlist) inside a real GoRouter.
///
/// Other paths render a stub showing where navigation went:
/// `/main?tab=1` → "main tab 1", `/sign-in` → "/sign-in", `/checkout` → "/checkout".

/// In-memory [CartStore] (as in cart_logic_test.dart).
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

/// A valid 1×1 PNG, so thumbnails decode like real photos.
final testPhotoBytes =
    base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

PickedPhoto testPhoto() => PickedPhoto(testPhotoBytes);

class UploadCall {
  UploadCall(this.uid, this.cartItemId, this.photosByGroup);
  final String uid;
  final String cartItemId;
  final Map<String, List<PickedPhoto>> photosByGroup;
}

/// Records picks and uploads; never touches the device or Storage.
class FakePhotoService implements PhotoService {
  Object? pickError;
  Object? uploadError;
  bool cancelPick = false;
  final picks = <ImageSource>[];
  final uploads = <UploadCall>[];

  @override
  Future<PickedPhoto?> pick(ImageSource source) async {
    picks.add(source);
    if (pickError != null) throw pickError!;
    return cancelPick ? null : testPhoto();
  }

  @override
  Future<Map<String, List<String>>> upload({
    required String uid,
    required String cartItemId,
    required Map<String, List<PickedPhoto>> photosByGroup,
    ValueChanged<double>? onProgress,
  }) async {
    uploads.add(UploadCall(uid, cartItemId, photosByGroup));
    if (uploadError != null) throw uploadError!;
    onProgress?.call(0.5);
    onProgress?.call(1);
    return {
      for (final e in photosByGroup.entries)
        e.key: [
          for (var i = 0; i < e.value.length; i++)
            'https://storage.test/uploads/$uid/$cartItemId/${e.key}-${i + 1}.jpg',
        ],
    };
  }
}

const testCities = [
  CityModel(id: 'erbil', name: LocalizedText('Erbil', ar: 'أربيل', ku: 'هەولێر')),
  CityModel(id: 'duhok', name: LocalizedText('Duhok', ar: 'دهوك', ku: 'دهۆک')),
];

/// A frame using all 8 option types (SRS §5.9 table).
ProductModel allOptionsProduct({
  bool photosRequired = true,
  bool outOfStock = false,
  bool discounted = false,
  List<String> availableCities = const [],
  int preparationDays = 2,
}) =>
    ProductModel(
      id: 'frame',
      title: const LocalizedText(
        'Personalized Magnetic Photo Frame',
        ar: 'إطار صور مغناطيسي مخصص',
        ku: 'چوارچێوەی وێنەی موگناتیسی تایبەت',
      ),
      description: const LocalizedText(
        'Create a beautiful memory display with our Personalized Magnetic Photo Frame, featuring 4 '
        'removable photo magnets and your own message.\nHandmade in Erbil.\nGift wrapped.',
        ar: 'اصنع عرضًا جميلًا لذكرياتك مع إطار الصور المغناطيسي المخصص، مع أربع صور مغناطيسية '
            'قابلة للإزالة ورسالتك الخاصة.\nمصنوع يدويًا في أربيل.',
        ku: 'پیشانگایەکی جوانی یادەوەری دروست بکە لەگەڵ چوارچێوەی وێنەی موگناتیسی تایبەت، '
            'لەگەڵ چوار وێنەی موگناتیسی و پەیامی خۆت.\nبە دەست دروستکراوە لە هەولێر.',
      ),
      storeId: 's1',
      images: const [],
      price: 35000,
      compareAtPrice: discounted ? 40000 : null,
      isFeatured: true,
      availability: outOfStock ? ProductAvailability.outOfStock : ProductAvailability.preparationDays,
      preparationDays: preparationDays,
      availableCities: availableCities,
      optionGroups: [
        const OptionGroup(
          id: 'frame',
          type: OptionType.imageVariant,
          label: LocalizedText('Frame Color', ar: 'لون الإطار', ku: 'ڕەنگی چوارچێوە'),
          required: true,
          sortOrder: 0,
          values: [
            OptionValue(
              id: 'walnut',
              label: LocalizedText('Walnut', ar: 'جوز', ku: 'گوێز'),
              priceDelta: 5000,
              preparationDaysOverride: 4,
            ),
            OptionValue(id: 'black', label: LocalizedText('Black', ar: 'أسود', ku: 'ڕەش')),
            OptionValue(id: 'gold', label: LocalizedText('Gold', ar: 'ذهبي', ku: 'ئاڵتوونی'), stock: 0),
          ],
        ),
        const OptionGroup(
          id: 'size',
          type: OptionType.textVariant,
          label: LocalizedText('Size', ar: 'الحجم', ku: 'قەبارە'),
          sortOrder: 1,
          values: [
            OptionValue(id: 's30', label: LocalizedText('30x30cm')),
            OptionValue(id: 's40', label: LocalizedText('40x40cm'), priceDelta: 3000, stock: 3),
          ],
        ),
        const OptionGroup(
          id: 'ink',
          type: OptionType.colorSwatch,
          label: LocalizedText('Text Color', ar: 'لون النص', ku: 'ڕەنگی دەق'),
          sortOrder: 2,
          values: [
            OptionValue(id: 'red', label: LocalizedText('Red', ar: 'أحمر', ku: 'سوور'), hex: '#E53935'),
            OptionValue(id: 'gold', label: LocalizedText('Gold'), hex: '#E3C04A'),
            OptionValue(id: 'black', label: LocalizedText('Black'), hex: '#222222'),
            OptionValue(id: 'white', label: LocalizedText('White'), hex: '#FFFFFF', stock: 0),
          ],
        ),
        const OptionGroup(
          id: 'text1',
          type: OptionType.text,
          label: LocalizedText('Text 1', ar: 'النص 1', ku: 'دەقی 1'),
          required: true,
          maxLength: 12,
          sortOrder: 3,
        ),
        const OptionGroup(
          id: 'notes',
          type: OptionType.longText,
          label: LocalizedText('Notes', ar: 'ملاحظات', ku: 'تێبینی'),
          maxLength: 500,
          sortOrder: 4,
        ),
        const OptionGroup(
          id: 'date',
          type: OptionType.date,
          label: LocalizedText('Date', ar: 'التاريخ', ku: 'بەروار'),
          sortOrder: 5,
        ),
        OptionGroup(
          id: 'photos',
          type: OptionType.photoUpload,
          label: const LocalizedText('Upload your photos', ar: 'حمّل صورك', ku: 'وێنەکانت باربکە'),
          required: photosRequired,
          minPhotos: photosRequired ? 2 : null,
          maxPhotos: 4,
          sortOrder: 6,
        ),
        const OptionGroup(
          id: 'qty',
          type: OptionType.quantity,
          label: LocalizedText('Quantity'),
          sortOrder: 7,
        ),
      ],
    );

StoreModel testStore(String id, String name) =>
    StoreModel(id: id, name: LocalizedText(name), status: StoreStatus.active);

class ShopHarness {
  ShopHarness({
    required this.container,
    required this.router,
    required this.local,
    required this.remote,
    required this.photos,
    required this.analytics,
    required this.firestore,
  });

  final ProviderContainer container;
  final GoRouter router;
  final MemoryCartStore local;
  final MemoryCartStore remote;
  final FakePhotoService photos;
  final FakeAnalytics analytics;
  final FakeFirebaseFirestore firestore;

  /// The cart lines of whoever is using the app.
  List<CartItemModel> get cartItems => container.read(cartControllerProvider).items;
}

Future<ShopHarness> pumpShop(
  WidgetTester tester, {
  required String initialPath,
  ProductModel? product,
  Stream<ProductModel?> Function(String id)? productStream,
  List<CartItemModel> cartItems = const [],
  Map<String, ProductModel> cartProducts = const {},
  Future<Map<String, ProductModel>> Function()? loadCartProducts,
  Map<String, StoreModel> stores = const {},
  User? user,
  FakeFirebaseFirestore? firestore,
  FakePhotoService? photos,
  List<CityModel> cities = testCities,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 3200),
  double textScale = 1,
  Map<String, Object> prefs = const {},

  /// Extra provider overrides (e.g. a profile, a wallet).
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();

  final local = MemoryCartStore();
  final remote = MemoryCartStore();
  for (final item in cartItems) {
    (user == null ? local : remote).items[item.id] = item;
  }
  final photoService = photos ?? FakePhotoService();
  final analytics = FakeAnalytics();
  final db = firestore ?? FakeFirebaseFirestore();

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sharedPrefs),
    analyticsServiceProvider.overrideWithValue(analytics),
    firestoreProvider.overrideWithValue(db),
    authStateProvider.overrideWith((ref) => Stream.value(user)),
    citiesProvider.overrideWith((ref) => Stream.value(cities)),
    photoServiceProvider.overrideWithValue(photoService),
    productByIdProvider.overrideWith((ref, id) => productStream?.call(id) ?? Stream.value(product)),
    cartControllerProvider.overrideWith((ref) {
      final controller = CartController(
        remoteStore: (_) => remote,
        localStore: local,
        analytics: ref.read(analyticsServiceProvider),
      );
      ref.listen(authStateProvider, (_, next) {
        if (!next.isLoading) controller.onAuthChanged(next.valueOrNull?.uid);
      }, fireImmediately: true);
      return controller;
    }),
    cartProductsProvider.overrideWith((ref) => loadCartProducts?.call() ?? Future.value(cartProducts)),
    cartStoresProvider.overrideWith((ref) async => stores),
    ...overrides,
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: initialPath,
    routes: [
      GoRoute(
        path: AppRoutes.productDetails,
        builder: (_, state) => ProductDetailsScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(path: AppRoutes.products, builder: (_, state) => Scaffold(body: Text('products ${state.uri}'))),
      GoRoute(path: AppRoutes.wishlists, builder: (_, __) => const WishlistScreen()),
      GoRoute(
        path: AppRoutes.main,
        builder: (_, state) => Scaffold(body: Text('main tab ${state.uri.queryParameters['tab']}')),
      ),
      for (final path in [AppRoutes.signIn, AppRoutes.signUp, AppRoutes.checkout])
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
  return ShopHarness(
    container: container,
    router: router,
    local: local,
    remote: remote,
    photos: photoService,
    analytics: analytics,
    firestore: db,
  );
}

AppLocalizations l10nFor(String code) => lookupAppLocalizations(Locale(code));
