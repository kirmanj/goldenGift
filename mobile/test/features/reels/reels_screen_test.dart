import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/core/widgets/main_shell.dart';
import 'package:golden_gift/features/home/presentation/screens/home_screen.dart';
import 'package:golden_gift/features/reels/data/reel_derived.dart';
import 'package:golden_gift/features/reels/data/reels_repository.dart';
import 'package:golden_gift/features/reels/presentation/providers/reels_providers.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import '../../helpers/fake_video_player.dart';

/// Reels tab (SRS §5.27) end to end on an in-memory Firestore and a fake
/// video platform.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  late FakeFirebaseFirestore db;
  late FakeVideoPlayerPlatform videos;
  late GoRouter router;
  late ProviderContainer container;

  String url(String id) => 'https://video.test/$id.mp4';

  Future<void> seedReel(
    String id, {
    required int minutesAgo,
    bool active = true,
    List<String> categories = const ['mugs'],
    List<GiftAudience> giftFor = const [GiftAudience.women],
    int price = 30000,
    String? caption,
  }) async {
    final product = ProductModel(
      id: 'p-$id',
      storeId: 's1',
      title: LocalizedText('Gift $id'),
      price: price,
      categoryIds: categories,
      giftFor: giftFor,
    );
    await db.collection('reels').doc(id).set({
      'productId': product.id,
      'videoUrl': url(id),
      if (caption != null) 'caption': caption,
      'isActive': active,
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 24, 12).subtract(Duration(minutes: minutesAgo))),
      ...ReelDerived.fieldsFor(isActive: active, product: product),
    });
  }

  Future<void> frames(WidgetTester tester, [int count = 6]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpReels(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    router = GoRouter(initialLocation: AppRoutes.mainTab(MainTab.reels), routes: [
      GoRoute(
        path: AppRoutes.main,
        builder: (_, state) => MainShell(
          initialIndex: (int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0).clamp(0, MainTab.count - 1),
        ),
      ),
      GoRoute(
        path: AppRoutes.productDetails,
        builder: (_, state) => Scaffold(body: Text('product ${state.pathParameters['id']}')),
      ),
    ]);
    const locale = Locale('en');
    await tester.pumpWidget(ProviderScope(
      overrides: appTestOverridesSync(prefs, firestore: db),
      child: MaterialApp.router(
        locale: locale,
        theme: AppTheme.lightTheme(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...KurdishFallbackLocalizations.delegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    ));
    await frames(tester);
    container = ProviderScope.containerOf(tester.element(find.byType(MainShell)));
  }

  Future<void> swipeUp(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(0, -600), 2000);
    await frames(tester, 10);
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    videos = FakeVideoPlayerPlatform.install();
  });

  testWidgets('newest visible reel first and playing; hidden reels never appear; swipe moves playback',
      (tester) async {
    await seedReel('old', minutesAgo: 30, caption: 'Hand-poured for her');
    await seedReel('new', minutesAgo: 5);
    await seedReel('hidden', minutesAgo: 1, active: false);
    await pumpReels(tester);

    expect(find.text('Gift new'), findsOneWidget);
    expect(find.text('Gift hidden'), findsNothing);
    expect(videos.playingUrls, {url('new')});
    // The next reel is prepared, not playing.
    expect(videos.liveUrls, containsAll([url('new'), url('old')]));

    await swipeUp(tester);
    expect(find.text('Gift old'), findsOneWidget);
    expect(find.text('Hand-poured for her'), findsOneWidget);
    expect(videos.playingUrls, {url('old')});
    expect(find.text('Gift hidden'), findsNothing);
  });

  testWidgets('another tab or a pushed screen pauses; coming back resumes; tap pauses and resumes', (tester) async {
    await seedReel('a', minutesAgo: 1);
    await pumpReels(tester);
    expect(videos.playingUrls, {url('a')});

    await tester.tap(find.text(en.home).last);
    await frames(tester);
    expect(find.byType(HomeScreen).hitTestable(), findsOneWidget);
    expect(videos.playingUrls, isEmpty);

    await tester.tap(find.text(en.reels).last);
    await frames(tester);
    expect(router.state.uri.toString(), AppRoutes.mainTab(MainTab.reels));
    expect(videos.playingUrls, {url('a')});

    // Tap on the video: pause, then play again.
    await tester.tap(find.bySemanticsLabel(en.reelsPause));
    await frames(tester, 2);
    expect(videos.playingUrls, isEmpty);
    await tester.tap(find.bySemanticsLabel(en.reelsPlay));
    await frames(tester, 2);
    expect(videos.playingUrls, {url('a')});

    // The product card opens Product Details; the reel pauses behind it.
    await tester.tap(find.text('Gift a'));
    await frames(tester);
    expect(find.text('product p-a'), findsOneWidget);
    expect(videos.playingUrls, isEmpty);
  });

  testWidgets('filter sheet: gift type narrows the feed; chips show it; Clear restores', (tester) async {
    await seedReel('her', minutesAgo: 2, giftFor: const [GiftAudience.women]);
    await seedReel('him', minutesAgo: 1, giftFor: const [GiftAudience.men]);
    await pumpReels(tester);
    expect(find.text('Gift him'), findsOneWidget);

    await tester.tap(find.byTooltip(en.filters));
    await frames(tester);
    await tester.tap(find.text(en.giftForWomen));
    await tester.pump();
    await tester.tap(find.text(en.reelsShowResults));
    await frames(tester);

    expect(container.read(reelsFilterProvider), const ReelFilter(giftFor: GiftAudience.women));
    expect(find.text('Gift her'), findsOneWidget);
    expect(find.text('Gift him'), findsNothing);
    expect(find.bySemanticsLabel('${en.giftForWomen}, ${en.reelsRemoveFilter}'), findsOneWidget);
    expect(videos.playingUrls, {url('her')});

    await tester.tap(find.text(en.clear));
    await frames(tester);
    expect(container.read(reelsFilterProvider).isEmpty, isTrue);
    expect(find.text('Gift him'), findsOneWidget);
  });

  testWidgets('category + price filters are one query; no match → message and Clear filters', (tester) async {
    await seedReel('mug', minutesAgo: 2, categories: const ['mugs'], price: 30000);
    await seedReel('frame', minutesAgo: 1, categories: const ['frames'], price: 120000);
    await pumpReels(tester);

    container.read(reelsFilterProvider.notifier).state = const ReelFilter(categoryId: 'frames', priceBands: {3});
    await frames(tester);
    expect(find.text('Gift frame'), findsOneWidget);
    expect(find.text('Gift mug'), findsNothing);

    container.read(reelsFilterProvider.notifier).state = const ReelFilter(categoryId: 'frames', priceBands: {0});
    await frames(tester);
    expect(find.text(en.reelsNoMatchTitle), findsOneWidget);
    await tester.tap(find.text(en.reelsClearFilters));
    await frames(tester);
    expect(find.text('Gift frame'), findsOneWidget);
  });

  testWidgets('no reels at all: friendly empty state', (tester) async {
    await pumpReels(tester);
    expect(find.text(en.reelsEmptyTitle), findsOneWidget);
    expect(find.text(en.reelsClearFilters), findsNothing);
  });

  testWidgets('a video that cannot play says so; its product card still works', (tester) async {
    videos = FakeVideoPlayerPlatform.install(failing: {url('broken')});
    await seedReel('broken', minutesAgo: 1);
    await pumpReels(tester);
    expect(find.text(en.reelsVideoError), findsOneWidget);
    await tester.tap(find.text('Gift broken'));
    await frames(tester);
    expect(find.text('product p-broken'), findsOneWidget);
  });

  testWidgets('sound is on in the apps; the toggle mutes every reel', (tester) async {
    await seedReel('a', minutesAgo: 2);
    await seedReel('b', minutesAgo: 3);
    await pumpReels(tester);
    expect(videos.volumes.values, everyElement(1.0));

    await tester.tap(find.byTooltip(en.reelsSoundOff));
    await frames(tester, 2);
    expect(container.read(reelsSoundOnProvider), isFalse);
    expect(videos.volumes.values, everyElement(0.0));
    expect(find.byTooltip(en.reelsSoundOn), findsOneWidget);
  });

  test('ReelFilter: badge count, all price bands = no price filter, value equality', () {
    expect(const ReelFilter().activeCount, 0);
    expect(const ReelFilter(categoryId: 'mugs', priceBands: {1, 2}, giftFor: GiftAudience.men).activeCount, 3);
    expect(const ReelFilter(priceBands: {0, 1, 2, 3, 4}).filtersPrice, isFalse);
    expect(const ReelFilter(priceBands: {1, 2}), const ReelFilter(priceBands: {2, 1}));
    expect(const ReelFilter(giftFor: GiftAudience.men).copyWith(clearGiftFor: true), const ReelFilter());
  });
}
