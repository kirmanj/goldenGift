import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/providers/connectivity_provider.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/categories/presentation/providers/categories_providers.dart';
import 'package:golden_gift/features/categories/presentation/screens/all_categories_screen.dart';
import 'package:golden_gift/features/home/presentation/providers/home_providers.dart';
import 'package:golden_gift/features/home/presentation/screens/home_screen.dart';
import 'package:golden_gift/features/products/data/datasources/product_sources.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/products/data/product_search_repository.dart';
import 'package:golden_gift/features/products/presentation/screens/products_screen.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/banner_model.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Catalogue fakes and a router harness for the Home / All Categories /
/// Products screens. Nothing touches Firebase or the network: products and
/// banners have no image URLs, every provider is overridden.

ProductModel testProduct(String id, {int price = 25000, String? title}) => ProductModel(
      id: id,
      storeId: 's1',
      title: LocalizedText(title ?? 'Gift $id', ar: 'هدية $id', ku: 'دیاری $id'),
      price: price,
    );

List<ProductModel> testProducts(String prefix, int count) =>
    [for (var i = 0; i < count; i++) testProduct('$prefix$i')];

/// Categories with all three languages (Arabic / Kurdish spellings differ).
const testCategories = [
  CategoryModel(id: 'flowers', title: LocalizedText('Flowers', ar: 'زهور', ku: 'گوڵ'), sortOrder: 1),
  CategoryModel(id: 'mugs', title: LocalizedText('Mugs', ar: 'أكواب', ku: 'کوپ'), sortOrder: 2),
  CategoryModel(id: 'birthdays', title: LocalizedText('Birthdays', ar: 'أعياد الميلاد', ku: 'ڕۆژی لەدایکبوون'), sortOrder: 3),
  CategoryModel(id: 'magnets', title: LocalizedText('Magnets', ar: 'مغناطيس', ku: 'مەگنەت'), sortOrder: 4),
  CategoryModel(id: 'leather', title: LocalizedText('Leather', ar: 'جلود', ku: 'چەرم'), sortOrder: 5),
  CategoryModel(id: 'frames', title: LocalizedText('Frames', ar: 'إطارات', ku: 'چوارچێوە'), sortOrder: 6),
  CategoryModel(id: 'candles', title: LocalizedText('Candles', ar: 'شموع', ku: 'مۆم'), sortOrder: 7),
  CategoryModel(id: 'keychains', title: LocalizedText('Keychains', ar: 'ميداليات', ku: 'کلیلدان'), sortOrder: 8),
  CategoryModel(id: 'kurdistan', title: LocalizedText('Kurdistan', ar: 'كردستان', ku: 'کوردستان'), sortOrder: 9),
];

const testCities = [
  CityModel(id: 'erbil', name: LocalizedText('Erbil', ar: 'أربيل', ku: 'هەولێر')),
  CityModel(id: 'duhok', name: LocalizedText('Duhok', ar: 'دهوك', ku: 'دهۆک')),
];

BannerModel testBanner(String id, BannerPlacement placement,
        {BannerActionType action = BannerActionType.route, String value = '/special-requests'}) =>
    BannerModel(id: id, imageUrl: '', placement: placement, actionType: action, actionValue: value);

Map<BannerPlacement, List<BannerModel>> testBanners({Set<BannerPlacement>? only}) => {
      for (final p in BannerPlacement.values)
        p: (only == null || only.contains(p)) ? [testBanner('b-${p.name}', p)] : const <BannerModel>[],
    };

UserModel testProfile({bool completed = false, String name = 'Krmanj Mzuri'}) =>
    UserModel(uid: 'u1', name: name, phone: '7505448229', profileCompleted: completed);

/// Serves [total] products per query in pages, recording every request.
/// Products are named `<prefix><index>` where the prefix encodes the query
/// (category id or "all"), so tests can tell lists apart.
class FakeProductRepository implements ProductSearchRepository {
  FakeProductRepository({this.total = 45});

  int total;

  /// Total per query, overriding [total] (e.g. 0 to make a query empty).
  int Function(ProductQuery query)? totalFor;
  Object? error;
  Object? loadMoreError;
  bool fromCache = false;
  bool ignoredFilters = false;
  final requests = <(ProductQuery, ProductCursor?)>[];

  List<ProductQuery> get queries => [for (final r in requests) r.$1];
  List<(ProductQuery, ProductCursor?)> requestsFor(ProductQuery q) => [
        for (final r in requests)
          if (r.$1 == q) r,
      ];

  static String prefixOf(ProductQuery q) => '${q.categoryId ?? 'all'}-';

  @override
  Future<ProductPage> fetch(ProductQuery query, {ProductCursor? cursor, int pageSize = 20}) async {
    requests.add((query, cursor));
    final start = (cursor?.value as int?) ?? 0;
    if (error != null) throw error!;
    if (start > 0 && loadMoreError != null) throw loadMoreError!;
    final count = totalFor?.call(query) ?? total;
    final end = (start + pageSize).clamp(0, count);
    return ProductPage(
      items: [for (var i = start; i < end; i++) testProduct('${prefixOf(query)}$i')],
      hasMore: end < count,
      cursor: ProductCursor(SearchEngine.firestore, end),
      fromCache: fromCache,
      ignoredFilters: ignoredFilters,
    );
  }
}

/// What every catalogue test can tune.
class CatalogueData {
  CatalogueData({
    Stream<Map<BannerPlacement, List<BannerModel>>> Function()? banners,
    Stream<List<CategoryModel>> Function()? homeCategories,
    Stream<List<CategoryModel>> Function()? allCategories,
    Stream<List<ProductModel>> Function()? popular,
    Stream<List<ProductModel>> Function()? featured,
    Stream<List<ProductModel>> Function()? forYou,
    Stream<UserModel?> Function()? profile,
    this.offline = false,
    FakeProductRepository? repository,
  })  : banners = banners ?? (() => Stream.value(testBanners())),
        homeCategories = homeCategories ?? (() => Stream.value(testCategories)),
        allCategories = allCategories ?? (() => Stream.value(testCategories)),
        popular = popular ?? (() => Stream.value(testProducts('pop', 6))),
        featured = featured ?? (() => Stream.value(testProducts('feat', 6))),
        forYou = forYou ?? (() => Stream.value(testProducts('fy', 6))),
        profile = profile ?? (() => Stream.value(null)),
        repository = repository ?? FakeProductRepository();

  final Stream<Map<BannerPlacement, List<BannerModel>>> Function() banners;
  final Stream<List<CategoryModel>> Function() homeCategories;
  final Stream<List<CategoryModel>> Function() allCategories;
  final Stream<List<ProductModel>> Function() popular;
  final Stream<List<ProductModel>> Function() featured;
  final Stream<List<ProductModel>> Function() forYou;
  final Stream<UserModel?> Function() profile;
  final bool offline;
  final FakeProductRepository repository;
}

/// Paths rendered as a stub page showing the full location.
const _stubPaths = [
  '/product/:id',
  AppRoutes.inviteAndEarn,
  AppRoutes.notifications,
  AppRoutes.editProfile,
  AppRoutes.specialRequests,
  AppRoutes.aiGiftSearch,
];

/// Pumps the catalogue screens inside a real GoRouter: `/main` = HomeScreen
/// (in a Scaffold, like the shell tab), `/categories`, `/products?…` are the
/// real screens; other destinations show their location as text.
Future<GoRouter> pumpCatalogueApp(
  WidgetTester tester, {
  String initialPath = AppRoutes.main,
  CatalogueData? data,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool settle = true,

  /// System "reduce motion": the coming-soon hero (SRS §5.7a) stops looping,
  /// so pumpAndSettle can settle on it.
  bool disableAnimations = false,
  Map<String, Object> prefs = const {},

  /// Extra provider overrides (e.g. a signed-in user for the referral sheet).
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final d = data ?? CatalogueData();
  final appLocale = Locale(locale);

  final router = GoRouter(
    initialLocation: initialPath,
    routes: [
      GoRoute(path: AppRoutes.main, builder: (_, __) => const Scaffold(body: HomeScreen())),
      GoRoute(path: AppRoutes.categories, builder: (_, __) => const AllCategoriesScreen()),
      GoRoute(
        path: AppRoutes.products,
        builder: (_, state) => ProductsScreen(
          initialQuery: ProductQuery.fromQueryParameters(state.uri.queryParameters),
          focusSearch: state.uri.queryParameters['focus'] == '1',
        ),
      ),
      for (final path in _stubPaths)
        GoRoute(path: path, builder: (_, state) => Scaffold(body: Text('stub:${state.uri}'))),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      homeBannersProvider.overrideWith((ref) => d.banners()),
      homeCategoriesProvider.overrideWith((ref) => d.homeCategories()),
      allCategoriesProvider.overrideWith((ref) => d.allCategories()),
      popularProductsProvider.overrideWith((ref) => d.popular()),
      featuredProductsProvider.overrideWith((ref) => d.featured()),
      forYouProductsProvider.overrideWith((ref) => d.forYou()),
      currentUserProfileProvider.overrideWith((ref) => d.profile()),
      isOfflineProvider.overrideWith((ref) => Stream.value(d.offline)),
      activeCitiesProvider.overrideWithValue(const AsyncValue.data(testCities)),
      productSearchRepositoryProvider.overrideWithValue(d.repository),
      ...overrides,
    ],
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
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: disableAnimations),
        child: child!,
      ),
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return router;
}

/// Location of the top-most page (pushed ones included), e.g. `/products?category=flowers`.
String locationOf(GoRouter router) => router.state.uri.toString();

AppLocalizations l10nFor(String code) => lookupAppLocalizations(Locale(code));

/// A Stream that never emits (a provider stuck loading).
Stream<T> pending<T>() => const Stream.empty();
