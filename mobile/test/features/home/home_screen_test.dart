import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/config/app_features.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/home/presentation/providers/home_providers.dart';
import 'package:golden_gift/features/home/presentation/screens/home_screen.dart';
import 'package:golden_gift/features/home/presentation/widgets/discover_section.dart';
import 'package:golden_gift/features/home/presentation/widgets/home_header.dart';
import 'package:golden_gift/features/home/presentation/widgets/home_sections.dart';
import 'package:golden_gift/features/home/presentation/widgets/profile_completion_card.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/products/presentation/screens/products_screen.dart';
import 'package:golden_gift/features/referrals/presentation/providers/referral_providers.dart';
import 'package:golden_gift/features/referrals/presentation/widgets/referral_reward_sheet.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/app_settings_model.dart';

import '../../helpers/auth_fakes.dart';

import '../../widgets/test_app.dart' show testApp;
import '../products/catalogue_test_harness.dart';

Finder _banner(BannerPlacement placement) => find.descendant(
      of: find.byWidgetPredicate((w) => w is HomeBannerSection && w.placement == placement),
      matching: find.byType(BannerCarousel),
    );

Finder _inCategoryGrid(String text) => find.descendant(of: find.byType(HomeCategoryGrid), matching: find.text(text));

Finder _inDiscover(Finder matching) => find.descendant(of: find.byType(DiscoverSection), matching: matching);

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder.first).dy;

const _tall = Size(390, 6000);

void main() {
  final en = l10nFor('en');

  group('sections', () {
    testWidgets('appear in SRS §5.4 order', (tester) async {
      await pumpCatalogueApp(
        tester,
        size: _tall,
        data: CatalogueData(offline: true, profile: () => Stream.value(testProfile())),
      );

      final order = <String, Finder>{
        'header': find.byType(HomeHeader),
        'offline': find.byType(OfflineChip),
        'homeTop': _banner(BannerPlacement.homeTop),
        'categories': _inCategoryGrid('Flowers'),
        'shopFor': find.text(en.shopForTitle),
        'popular': find.text(en.popular),
        'homeMid1': _banner(BannerPlacement.homeMid1),
        'featured': find.text(en.featured),
        'homeMid2': _banner(BannerPlacement.homeMid2),
        'forYou': find.text(en.forYou),
        'homeBottom': _banner(BannerPlacement.homeBottom),
        'profileCard': find.text(en.profileCompletionTitle),
        'discover': find.text(en.discover),
        'discoverGrid': find.text('Gift all-0'),
      };
      var previous = double.negativeInfinity;
      for (final entry in order.entries) {
        expect(entry.value, findsWidgets, reason: entry.key);
        final top = _top(tester, entry.value);
        expect(top, greaterThan(previous), reason: '${entry.key} should come after the previous section');
        previous = top;
      }
      expect(find.text('Gift pop0'), findsOneWidget);
      expect(find.text('Gift feat0'), findsOneWidget);
      expect(find.text('Gift fy0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty sections are hidden', (tester) async {
      await pumpCatalogueApp(
        tester,
        size: _tall,
        data: CatalogueData(
          banners: () => Stream.value(testBanners(only: {BannerPlacement.homeTop})),
          featured: () => Stream.value(const []),
          forYou: () => Stream.value(const []),
          homeCategories: () => Stream.value(const []),
        ),
      );

      expect(_banner(BannerPlacement.homeTop), findsOneWidget);
      expect(_banner(BannerPlacement.homeMid1), findsNothing);
      expect(_banner(BannerPlacement.homeMid2), findsNothing);
      expect(_banner(BannerPlacement.homeBottom), findsNothing);
      expect(find.text(en.featured), findsNothing);
      expect(find.text(en.forYou), findsNothing);
      expect(find.byType(CategoryTile), findsNothing);
      expect(find.byType(OfflineChip), findsNothing);
      expect(find.text(en.profileCompletionTitle), findsNothing); // guest
      expect(find.text(en.popular), findsOneWidget);
      expect(find.text(en.discover), findsOneWidget);
      // No category chips without categories, but the "All" grid still loads.
      expect(_inDiscover(find.byType(CategoryChip)), findsNothing);
      expect(find.text('Gift all-0'), findsOneWidget);
    });

    testWidgets('a failing section leaves the others visible', (tester) async {
      await pumpCatalogueApp(
        tester,
        size: _tall,
        data: CatalogueData(
          popular: () => Stream.error(Exception('permission-denied')),
          banners: () => Stream.error(Exception('offline')),
        ),
      );

      expect(find.text(en.popular), findsNothing);
      expect(find.byType(BannerCarousel), findsNothing);
      expect(find.byType(HomeHeader), findsOneWidget);
      expect(_inCategoryGrid('Flowers'), findsOneWidget);
      expect(find.text(en.featured), findsOneWidget);
      expect(find.text(en.forYou), findsOneWidget);
      expect(find.text('Gift all-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing Discover list shows Retry and the rest of Home stays', (tester) async {
      final repo = FakeProductRepository()..error = Exception('unavailable');
      await pumpCatalogueApp(tester, size: _tall, data: CatalogueData(repository: repo));

      expect(_inDiscover(find.byType(ErrorState)), findsOneWidget);
      expect(find.text(en.popular), findsOneWidget);

      repo.error = null;
      await tester.tap(_inDiscover(find.text(en.retry)));
      await tester.pumpAndSettle();
      expect(_inDiscover(find.byType(ErrorState)), findsNothing);
      expect(find.text('Gift all-0'), findsOneWidget);
    });

    testWidgets('loading sections show skeletons, not blank space', (tester) async {
      await pumpCatalogueApp(
        tester,
        settle: false,
        data: CatalogueData(
          popular: () => const Stream.empty(),
          homeCategories: () => const Stream.empty(),
        ),
      );
      await tester.pump();
      expect(find.byType(SkeletonLoader), findsWidgets);
      expect(find.text(en.popular), findsOneWidget); // header above its skeleton
      expect(find.byType(CategoryTile), findsNothing);
    });

    testWidgets('without a backend every data section hides and Home still renders', (tester) async {
      // No overrides at all: Firebase isn't initialised in tests, so every
      // provider fails the way a broken backend would.
      await tester.pumpWidget(const ProviderScope(child: _Bare()));
      await tester.pumpAndSettle();
      expect(find.byType(HomeHeader), findsOneWidget);
      expect(find.text(en.guest), findsOneWidget);
      expect(find.byType(BannerCarousel), findsNothing);
      expect(find.byType(CategoryTile), findsNothing);
      expect(find.byType(ErrorState), findsOneWidget); // Discover offers Retry
      expect(tester.takeException(), isNull);
    });
  });

  group('header', () {
    testWidgets('greets the signed-in user by first name; bell opens notifications', (tester) async {
      final router = await pumpCatalogueApp(
        tester,
        data: CatalogueData(profile: () => Stream.value(testProfile())),
      );
      final greetings = {en.goodMorning, en.goodAfternoon, en.goodEvening};
      expect(
        find.byWidgetPredicate((w) => w is Text && greetings.contains(w.data)),
        findsOneWidget,
      );
      expect(find.text('Krmanj'), findsOneWidget);

      await tester.tap(find.byTooltip(en.notifications));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.notifications);
    });

    testWidgets('guests are greeted as Guest', (tester) async {
      await pumpCatalogueApp(tester);
      expect(find.text(en.guest), findsOneWidget);
    });

    testWidgets('AI Gift Search is hidden while switched off (AppFeatures)', (tester) async {
      await pumpCatalogueApp(tester);
      expect(AppFeatures.aiGiftSearch, isFalse);
      expect(find.byType(AiGiftSearchBar), findsNothing);
    });

    test('greeting follows the local time', () {
      expect(greetingFor(DateTime(2026, 1, 1, 8)), Greeting.morning);
      expect(greetingFor(DateTime(2026, 1, 1, 13)), Greeting.afternoon);
      expect(greetingFor(DateTime(2026, 1, 1, 21)), Greeting.evening);
    });
  });

  group('navigation', () {
    testWidgets('Shop for: For him / For her / For companies open the filtered list (SRS §5.8a)', (tester) async {
      final router = await pumpCatalogueApp(tester, size: _tall);
      for (final (label, audience) in [
        (en.giftForMen, GiftAudience.men),
        (en.giftForWomen, GiftAudience.women),
        (en.giftForCompanies, GiftAudience.companies),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(locationOf(router), AppRoutes.productsFor(ProductQuery(giftFor: audience)));
        router.pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('only the first 7 categories + More; tiles and More navigate', (tester) async {
      final router = await pumpCatalogueApp(tester, size: _tall);
      expect(find.descendant(of: find.byType(HomeCategoryGrid), matching: find.byType(CategoryTile)),
          findsNWidgets(HomeCategoryGrid.shownCategories + 1));
      expect(_inCategoryGrid('Candles'), findsOneWidget); // 7th
      expect(_inCategoryGrid('Keychains'), findsNothing); // 8th
      expect(_inCategoryGrid(en.more), findsOneWidget);

      await tester.tap(_inCategoryGrid('Flowers'));
      await tester.pumpAndSettle();
      expect(locationOf(router), '/products?category=flowers');
      expect(tester.widget<ProductsScreen>(find.byType(ProductsScreen)).initialQuery,
          const ProductQuery(categoryId: 'flowers'));

      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(_inCategoryGrid(en.more));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.categories);
    });

    testWidgets('Popular "View All" opens the products list with the popular query', (tester) async {
      final data = CatalogueData();
      final router = await pumpCatalogueApp(tester, size: _tall, data: data);
      final popularHeader = find.ancestor(of: find.text(en.popular), matching: find.byType(SectionHeader));
      await tester.tap(find.descendant(of: popularHeader, matching: find.text(en.viewAll)));
      await tester.pumpAndSettle();

      expect(locationOf(router), AppRoutes.productsFor(HomeQueries.popular));
      expect(tester.widget<ProductsScreen>(find.byType(ProductsScreen)).initialQuery, HomeQueries.popular);
      expect(data.repository.queries.last, HomeQueries.popular);
    });

    testWidgets('Featured and For you "View All" use their queries', (tester) async {
      final router = await pumpCatalogueApp(tester, size: _tall);
      for (final (title, query) in [(en.featured, HomeQueries.featured), (en.forYou, HomeQueries.forYou)]) {
        final header = find.ancestor(of: find.text(title), matching: find.byType(SectionHeader));
        await tester.tap(find.descendant(of: header, matching: find.text(en.viewAll)));
        await tester.pumpAndSettle();
        expect(locationOf(router), AppRoutes.productsFor(query));
        router.pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a product card opens Product Details', (tester) async {
      final router = await pumpCatalogueApp(tester, size: _tall);
      await tester.tap(find.text('Gift pop1'));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.product('pop1'));
    });

    testWidgets('a banner runs its action', (tester) async {
      final router = await pumpCatalogueApp(
        tester,
        data: CatalogueData(banners: () => Stream.value(testBanners(only: {BannerPlacement.homeTop}))),
      );
      await tester.tap(_banner(BannerPlacement.homeTop));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.specialRequests);
    });
  });

  group('profile completion card', () {
    testWidgets('shows for an incomplete signed-in profile and opens Edit Profile', (tester) async {
      final router = await pumpCatalogueApp(
        tester,
        size: _tall,
        data: CatalogueData(profile: () => Stream.value(testProfile(completed: false))),
      );
      expect(find.byType(ProfileCompletionCard), findsOneWidget);
      expect(find.text(en.profileCompletionTitle), findsOneWidget);

      await tester.tap(find.text(en.goToProfile));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.editProfile);
    });

    testWidgets('is hidden for a completed profile', (tester) async {
      await pumpCatalogueApp(
        tester,
        size: _tall,
        data: CatalogueData(profile: () => Stream.value(testProfile(completed: true))),
      );
      expect(find.text(en.profileCompletionTitle), findsNothing);
    });

    testWidgets('is hidden for guests', (tester) async {
      await pumpCatalogueApp(tester, size: _tall);
      expect(find.text(en.profileCompletionTitle), findsNothing);
    });
  });

  group('Discover', () {
    testWidgets('a chip changes the query sent to the repository', (tester) async {
      final data = CatalogueData();
      await pumpCatalogueApp(tester, size: _tall, data: data);
      expect(data.repository.queries, contains(DiscoverSection.queryFor(null)));
      expect(DiscoverSection.queryFor(null), const ProductQuery(sort: ProductSort.newest));

      final mugsChip = _inDiscover(find.widgetWithText(CategoryChip, 'Mugs'));
      await tester.tap(mugsChip);
      await tester.pumpAndSettle();

      const mugs = ProductQuery(categoryId: 'mugs', sort: ProductSort.newest);
      expect(data.repository.queries, contains(mugs));
      expect(tester.widget<CategoryChip>(mugsChip).selected, isTrue);
      expect(tester.widget<CategoryChip>(_inDiscover(find.widgetWithText(CategoryChip, en.all))).selected, isFalse);
      expect(find.text('Gift mugs-0'), findsOneWidget);
      expect(find.text('Gift all-0'), findsNothing);
    });

    testWidgets('scrolling near the end requests the next page', (tester) async {
      final data = CatalogueData();
      await pumpCatalogueApp(tester, data: data); // phone height
      final all = DiscoverSection.queryFor(null);
      expect(data.repository.requestsFor(all), hasLength(1));
      expect(data.repository.requestsFor(all).single.$2, isNull);

      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      final requests = data.repository.requestsFor(all);
      expect(requests.length, greaterThanOrEqualTo(2));
      expect(requests[1].$2?.value, 20);
      expect(find.text('Gift all-20', skipOffstage: false), findsOneWidget);
    });

    testWidgets('a failed next page shows "Couldn\'t load more" with Retry', (tester) async {
      final data = CatalogueData(repository: FakeProductRepository()..loadMoreError = Exception('flaky'));
      await pumpCatalogueApp(tester, data: data);
      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.text(en.loadMoreFailed), findsOneWidget);
      final requestsBefore = data.repository.requests.length;
      // No automatic retry loop while the error is shown.
      position.jumpTo(position.maxScrollExtent - 1);
      await tester.pumpAndSettle();
      expect(data.repository.requests.length, requestsBefore);

      data.repository.loadMoreError = null;
      await tester.tap(find.text(en.retry));
      await tester.pumpAndSettle();
      expect(find.text(en.loadMoreFailed), findsNothing);
      expect(find.text('Gift all-20', skipOffstage: false), findsOneWidget);
    });

    testWidgets('pull-to-refresh reloads Discover from the first page', (tester) async {
      final data = CatalogueData();
      await pumpCatalogueApp(tester, data: data);
      final before = data.repository.requests.length;
      await tester.fling(find.byType(HomeHeader), const Offset(0, 500), 1000);
      await tester.pumpAndSettle();
      expect(data.repository.requests.length, greaterThan(before));
      expect(data.repository.requests.last.$2, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('locales, themes, sizes', () {
    for (final (locale, mode) in [
      ('ar', ThemeMode.light),
      ('ckb', ThemeMode.light),
      ('en', ThemeMode.dark),
      ('ar', ThemeMode.dark),
      ('ckb', ThemeMode.dark),
    ]) {
      testWidgets('renders in $locale / ${mode.name}', (tester) async {
        await pumpCatalogueApp(
          tester,
          size: _tall,
          locale: locale,
          themeMode: mode,
          data: CatalogueData(offline: true, profile: () => Stream.value(testProfile())),
        );
        final l10n = l10nFor(locale);
        expect(find.text(l10n.popular), findsOneWidget);
        expect(find.text(l10n.discover), findsOneWidget);
        expect(Directionality.of(tester.element(find.byType(HomeScreen))),
            locale == 'en' ? TextDirection.ltr : TextDirection.rtl);
        expect(tester.takeException(), isNull);
      });
    }

    for (final locale in ['en', 'ar', 'ckb']) {
      testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
        await pumpCatalogueApp(
          tester,
          size: const Size(320, 7000),
          textScale: 1.3,
          locale: locale,
          data: CatalogueData(offline: true, profile: () => Stream.value(testProfile())),
        );
        expect(find.text(l10nFor(locale).profileCompletionTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('referral sheet (SRS §5.4 item 13)', () {
    List<Override> signedIn({int join = 5000, int order = 5000}) => [
          authStateProvider.overrideWith((ref) => Stream.value(FakeUser())),
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          referralSettingsProvider
              .overrideWith((ref) => Stream.value(ReferralSettings(joinBonus: join, orderBonus: order))),
        ];
    const secondOpen = {ReferralSheetTracker.opensKey: 1};

    testWidgets('shows over Home on the second open for a signed-in customer, once', (tester) async {
      await pumpCatalogueApp(tester, prefs: secondOpen, overrides: signedIn());
      expect(find.byType(ReferralRewardSheet), findsOneWidget);
      expect(find.text(en.referralSheetTitle), findsOneWidget);
      // The sheet scrolls when it is taller than the screen.
      await tester.ensureVisible(find.text(en.referralMaybeLater));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.referralMaybeLater));
      await tester.pumpAndSettle();
      expect(find.byType(ReferralRewardSheet), findsNothing);
      expect(find.byType(HomeHeader), findsOneWidget);
    });

    testWidgets('not on the first open', (tester) async {
      await pumpCatalogueApp(tester, overrides: signedIn());
      expect(find.byType(ReferralRewardSheet), findsNothing);
    });

    testWidgets('not for guests', (tester) async {
      await pumpCatalogueApp(tester, prefs: secondOpen);
      expect(find.byType(ReferralRewardSheet), findsNothing);
    });

    testWidgets('not when both bonuses are 0', (tester) async {
      await pumpCatalogueApp(tester, prefs: secondOpen, overrides: signedIn(join: 0, order: 0));
      expect(find.byType(ReferralRewardSheet), findsNothing);
    });
  });

  testWidgets('OfflineChip renders in both themes', (tester) async {
    await tester.pumpWidget(testApp(const OfflineChip()));
    expect(find.text(en.offlineChip), findsOneWidget);
    await tester.pumpWidget(testApp(const OfflineChip(), dark: true, locale: const Locale('ckb')));
    expect(find.text(l10nFor('ckb').offlineChip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// HomeScreen with the real theme and localizations and no provider overrides.
class _Bare extends StatelessWidget {
  const _Bare();

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.lightTheme(const Locale('en')),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...KurdishFallbackLocalizations.delegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: HomeScreen()),
      );
}
