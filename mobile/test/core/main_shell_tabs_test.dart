import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/core/widgets/main_shell.dart';
import 'package:golden_gift/features/cart/presentation/screens/cart_screen.dart';
import 'package:golden_gift/features/home/presentation/screens/home_screen.dart';
import 'package:golden_gift/features/reels/presentation/screens/reels_screen.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_test_overrides.dart';
import '../helpers/fake_video_player.dart';

/// `context.go(AppRoutes.mainTab(n))` must switch tabs even when /main is
/// already in the stack (e.g. "View cart" from a pushed page, Promo "Use").
void main() {
  late GoRouter router;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    router = GoRouter(initialLocation: AppRoutes.mainTab(0), routes: [
      GoRoute(
        path: AppRoutes.main,
        builder: (_, state) =>
            MainShell(initialIndex: (int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0).clamp(0, MainTab.count - 1)),
      ),
      GoRoute(
        path: '/pushed',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => context.go(AppRoutes.mainTab(1)), child: const Text('view cart')),
          ),
        ),
      ),
    ]);
    const locale = Locale('en');
    await tester.pumpWidget(ProviderScope(
      overrides: appTestOverridesSync(prefs),
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
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Router changes land a few frames later; Home has endless shimmers, so no pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool onstage<T extends Widget>(WidgetTester tester) => find.byType(T).hitTestable().evaluate().isNotEmpty;

  testWidgets('tab taps keep ?tab= in sync and go() from a pushed page switches tabs', (tester) async {
    await pump(tester);
    final en = lookupAppLocalizations(const Locale('en'));
    expect(onstage<HomeScreen>(tester), isTrue);

    await tester.tap(find.text(en.cart).last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.state.uri.toString(), AppRoutes.mainTab(1));
    expect(onstage<CartScreen>(tester), isTrue);

    // Back to Home by hand, then "View cart" from a pushed page.
    await tester.tap(find.text(en.home).last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.state.uri.toString(), AppRoutes.mainTab(0));
    router.push('/pushed');
    await settle(tester);
    await tester.tap(find.text('view cart'));
    await settle(tester);
    expect(onstage<CartScreen>(tester), isTrue);

    // Same again after another manual switch: still works.
    await tester.tap(find.text(en.home).last);
    await tester.pump(const Duration(milliseconds: 300));
    router.push('/pushed');
    await settle(tester);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('view cart'));
    await settle(tester);
    expect(onstage<CartScreen>(tester), isTrue);
  });

  testWidgets('Home · Reels · Cart · Profile; Reels has the stable id 3 and is built on first open', (tester) async {
    FakeVideoPlayerPlatform.install();
    await pump(tester);
    final en = lookupAppLocalizations(const Locale('en'));
    final labels = [en.home, en.reels, en.cart, en.profile];
    final xs = [for (final l in labels) tester.getCenter(find.text(l).last).dx];
    expect(xs, [...xs]..sort(), reason: 'visual order left to right');
    expect(find.byType(ReelsScreen, skipOffstage: false), findsNothing, reason: 'not built before it is opened');

    await tester.tap(find.text(en.reels).last);
    await settle(tester);
    expect(router.state.uri.toString(), AppRoutes.mainTab(MainTab.reels));
    expect(onstage<ReelsScreen>(tester), isTrue);

    // Old links keep their tabs: 1 is still Cart.
    router.go(AppRoutes.mainTab(MainTab.cart));
    await settle(tester);
    expect(onstage<CartScreen>(tester), isTrue);
    expect(find.byType(ReelsScreen, skipOffstage: false), findsOneWidget, reason: 'kept alive offstage once opened');
  });
}
