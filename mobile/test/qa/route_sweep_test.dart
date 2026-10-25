import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/auth/presentation/providers/auth_flow.dart';
import 'package:golden_gift/features/auth/presentation/providers/otp_controller.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/categories/presentation/widgets/coming_soon_category.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_test_overrides.dart';
import 'qa_harness.dart';

/// Phase 10 route sweep (SRS §8, §10): every route of the real router, on a
/// seeded world, in {en, ar, ckb} × {light, dark} × {390×844 @100 %,
/// 320×640 @130 %}, plus guest mode for the account screens. Fails on ANY
/// FlutterError (overflow, exception, missing localization) and on text that
/// leaks a raw l10n key, "null" or an unreplaced placeholder.
///
/// Run alone: `flutter test test/qa/route_sweep_test.dart`.

class SweepRoute {
  const SweepRoute(this.location, {this.extra, this.guest = false, this.label});
  final String location;
  final Object? extra;
  final bool guest;
  final String? label;

  String get name => '${label ?? location}${guest ? ' (guest)' : ''}';
}

const _otpArgs = OtpArgs(
  purpose: OtpPurpose.signUp,
  session: PhoneCodeSession(phoneE164: '+9647501234567'),
  displayPhone: '+964 750 123 4567',
);

const _prefill = ProfilePrefill(method: SignInMethod.google, name: 'Sara Ahmed', email: 'sara.ahmed@example.com');

/// One entry per screen state worth checking. Signed-in as `u1` unless guest.
const sweepRoutes = <SweepRoute>[
  // Start-up and auth
  SweepRoute(AppRoutes.splash, label: '/ (splash → main)'),
  SweepRoute(AppRoutes.onboarding, guest: true),
  SweepRoute(AppRoutes.maintenance),
  SweepRoute(AppRoutes.updateRequired),
  SweepRoute('${AppRoutes.signUp}?ref=ZQC8YC', guest: true),
  SweepRoute(AppRoutes.signIn, guest: true),
  SweepRoute(AppRoutes.otp, extra: _otpArgs, guest: true),
  SweepRoute(AppRoutes.completeProfile, extra: _prefill),
  // Main shell tabs
  SweepRoute('${AppRoutes.main}?tab=0', label: '/main Home'),
  SweepRoute('${AppRoutes.main}?tab=1', label: '/main Cart'),
  SweepRoute('${AppRoutes.main}?tab=2', label: '/main Profile'),
  SweepRoute('${AppRoutes.main}?tab=3', label: '/main Reels'),
  SweepRoute('${AppRoutes.main}?tab=0', label: '/main Home', guest: true),
  SweepRoute('${AppRoutes.main}?tab=1', label: '/main Cart', guest: true),
  SweepRoute('${AppRoutes.main}?tab=2', label: '/main Profile', guest: true),
  SweepRoute('${AppRoutes.main}?tab=3', label: '/main Reels', guest: true),
  // Catalogue
  SweepRoute(AppRoutes.categories),
  SweepRoute(AppRoutes.products),
  SweepRoute('${AppRoutes.products}?category=birthdays&sort=priceHighLow'),
  SweepRoute('${AppRoutes.products}?for=companies&category=frames', label: '/products gift for (SRS §5.8a)'),
  SweepRoute('${AppRoutes.products}?q=mug'),
  SweepRoute('${AppRoutes.products}?category=$qaComingSoonCategory', label: '/products coming soon (SRS §5.7a)'),
  SweepRoute('${AppRoutes.products}?category=$qaComingSoonSubcategory', label: '/products coming soon via parent'),
  SweepRoute('/product/frame'),
  SweepRoute('/product/mug'),
  SweepRoute('/product/soldout'),
  SweepRoute('/p/mug', label: '/p/:id share link'),
  SweepRoute(AppRoutes.aiGiftSearch),
  // Shopping & orders
  SweepRoute(AppRoutes.wishlists),
  SweepRoute(AppRoutes.checkout),
  SweepRoute('/order-success/o1'),
  SweepRoute(AppRoutes.orders),
  SweepRoute('/orders/o1', label: '/orders/:id pending'),
  SweepRoute('/orders/o2', label: '/orders/:id out for delivery'),
  SweepRoute('/orders/o3', label: '/orders/:id delivered'),
  SweepRoute('/orders/o4', label: '/orders/:id cancelled + refund'),
  SweepRoute('/orders/o5', label: '/orders/:id gift card'),
  SweepRoute(AppRoutes.addresses),
  SweepRoute('${AppRoutes.addresses}?select=1'),
  SweepRoute(AppRoutes.addressForm),
  SweepRoute('${AppRoutes.addressForm}?id=a1'),
  SweepRoute(AppRoutes.notifications),
  // Profile area
  SweepRoute(AppRoutes.editProfile),
  SweepRoute(AppRoutes.changePhone),
  SweepRoute(AppRoutes.settings),
  SweepRoute(AppRoutes.wallet),
  SweepRoute(AppRoutes.inviteAndEarn),
  SweepRoute('/r/ZQC8YC', label: '/r/:code referral link'),
  SweepRoute(AppRoutes.promoCodes),
  SweepRoute(AppRoutes.savedCards),
  SweepRoute(AppRoutes.contactUs),
  SweepRoute(AppRoutes.becomePartner),
  // Gift cards, special requests, Secret Santa
  SweepRoute(AppRoutes.giftCards),
  SweepRoute(AppRoutes.giftCardsShop),
  SweepRoute('/gift-cards/design/t1'),
  SweepRoute(AppRoutes.specialRequests),
  SweepRoute('/special-requests/r1', label: '/special-requests/:id quoted'),
  SweepRoute('/special-requests/r3', label: '/special-requests/:id rejected'),
  SweepRoute('/special-requests/r1/accept'),
  SweepRoute(AppRoutes.secretSanta),
  SweepRoute('/secret-santa/g1', label: '/secret-santa/:id open (organiser)'),
  SweepRoute('/secret-santa/g2', label: '/secret-santa/:id drawn'),
  SweepRoute('/s/ABCD2345', label: '/s/:code join link'),
  SweepRoute('/payment/ps1', label: '/payment/:sid unknown session'),
  SweepRoute('/orders/o6', label: '/orders/:id awaiting ZainCash (Pay now)'),
  SweepRoute('/payment/zc-pending', label: '/payment/:sid waiting'),
  SweepRoute('/payment/zc-failed', label: '/payment/:sid failed'),
  SweepRoute('/payment/zc-topup', label: '/payment/:sid top-up paid'),
  // Guest mode for the account screens (SRS AUTH-5)
  SweepRoute(AppRoutes.orders, guest: true),
  SweepRoute(AppRoutes.wishlists, guest: true),
  SweepRoute(AppRoutes.addresses, guest: true),
  SweepRoute(AppRoutes.notifications, guest: true),
  SweepRoute(AppRoutes.wallet, guest: true),
  SweepRoute(AppRoutes.inviteAndEarn, guest: true),
  SweepRoute(AppRoutes.promoCodes, guest: true),
  SweepRoute(AppRoutes.giftCards, guest: true),
  SweepRoute(AppRoutes.specialRequests, guest: true),
  SweepRoute(AppRoutes.secretSanta, guest: true),
  SweepRoute(AppRoutes.becomePartner, guest: true),
  SweepRoute(AppRoutes.checkout, guest: true),
];

/// Router paths deliberately not swept.
const _notSwept = {
  AppRoutes.devGallery: 'debug-only widget gallery, not shipped',
};

/// Screens with lists, opened on an empty world (new customer, empty
/// catalogue): every empty state at 320×640 @130 % in the three languages.
const emptyStateRoutes = <SweepRoute>[
  SweepRoute('${AppRoutes.main}?tab=0', label: '/main Home'),
  SweepRoute('${AppRoutes.main}?tab=1', label: '/main Cart'),
  SweepRoute('${AppRoutes.main}?tab=2', label: '/main Profile'),
  SweepRoute('${AppRoutes.main}?tab=3', label: '/main Reels'),
  SweepRoute(AppRoutes.categories),
  SweepRoute(AppRoutes.products),
  SweepRoute('${AppRoutes.products}?q=nothing'),
  SweepRoute('/product/missing', label: '/product/:id missing'),
  SweepRoute(AppRoutes.wishlists),
  SweepRoute(AppRoutes.orders),
  SweepRoute('/orders/missing', label: '/orders/:id missing'),
  SweepRoute(AppRoutes.addresses),
  SweepRoute(AppRoutes.notifications),
  SweepRoute(AppRoutes.wallet),
  SweepRoute(AppRoutes.inviteAndEarn),
  SweepRoute(AppRoutes.promoCodes),
  SweepRoute(AppRoutes.giftCards),
  SweepRoute(AppRoutes.giftCardsShop),
  SweepRoute('/gift-cards/design/missing', label: '/gift-cards/design/:id missing'),
  SweepRoute(AppRoutes.specialRequests),
  SweepRoute('/special-requests/missing', label: '/special-requests/:id missing'),
  SweepRoute(AppRoutes.secretSanta),
  SweepRoute('/secret-santa/missing', label: '/secret-santa/:id missing'),
  SweepRoute('/s/ZZZZ9999', label: '/s/:code unknown'),
  SweepRoute('/order-success/missing', label: '/order-success/:id missing'),
];

/// Key screens checked on an iPad (SRS §8: tablets render the phone layouts
/// in a centred column of at most 600 px — MaxWidthFrame).
const tabletRoutes = <SweepRoute>[
  SweepRoute('${AppRoutes.main}?tab=0', label: '/main Home'),
  SweepRoute('${AppRoutes.main}?tab=1', label: '/main Cart'),
  SweepRoute('${AppRoutes.main}?tab=2', label: '/main Profile'),
  SweepRoute('${AppRoutes.main}?tab=3', label: '/main Reels'),
  SweepRoute(AppRoutes.categories),
  SweepRoute('${AppRoutes.products}?category=birthdays'),
  SweepRoute('${AppRoutes.products}?category=$qaComingSoonCategory', label: '/products coming soon'),
  SweepRoute('/product/frame'),
  SweepRoute(AppRoutes.checkout),
  SweepRoute('/orders/o2'),
  SweepRoute(AppRoutes.wallet),
  SweepRoute('/gift-cards/design/t1'),
  SweepRoute('/secret-santa/g2'),
  SweepRoute(AppRoutes.signIn, guest: true),
];

void main() {
  setUpAll(loadAppFonts);

  test('the sweep covers every route of the app router', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final routerProvider = Provider<GoRouter>((ref) => buildAppRouter(ref));
    final container = ProviderContainer(overrides: appTestOverridesSync(prefs));
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    addTearDown(router.dispose);
    final paths = <String>[];
    void walk(List<RouteBase> routes) {
      for (final r in routes) {
        if (r is GoRoute) paths.add(r.path);
        walk(r.routes);
      }
    }

    walk(router.configuration.routes);
    final swept = [for (final r in sweepRoutes) Uri.parse(r.location).path];
    final missing = [
      for (final p in paths)
        if (!_notSwept.containsKey(p) &&
            !swept.any((s) => RegExp('^${p.replaceAll(RegExp(r':\w+'), r'[^/]+')}\$').hasMatch(s)))
          p,
    ];
    expect(missing, isEmpty, reason: 'Add these routes to sweepRoutes (test/qa/route_sweep_test.dart)');
  });

  group('empty world', () {
    for (final route in emptyStateRoutes) {
      for (final locale in qaLocales) {
        testWidgets('${route.name} · $locale · empty · ${QaViewport.smallLargeText}', (tester) async {
          final problems = <String>{};
          final errors = await captureFlutterErrors(() async {
            final app = await pumpQaApp(tester,
                location: route.location,
                locale: locale,
                theme: locale == 'ar' ? ThemeMode.dark : ThemeMode.light,
                viewport: QaViewport.smallLargeText,
                firestore: await seedQaWorld(null, true));
            problems.addAll(textProblems(tester));
            await scrollThrough(tester, onStep: () => problems.addAll(textProblems(tester)));
            await unmountQaApp(tester, app);
          });
          expect(describeErrors(errors), isEmpty);
          expect(problems, isEmpty);
        });
      }
    }
  });

  // Home ▸ Discover with the coming-soon chip selected (SRS §5.4 item 12,
  // §5.7a): the inline card in every language, theme and size.
  group('Discover coming-soon card', () {
    const titles = {'en': 'Easter Day', 'ar': 'عيد الفصح', 'ckb': 'جەژنی ئیستەر'};
    for (final locale in qaLocales) {
      for (final theme in qaThemes) {
        for (final viewport in [QaViewport.phone, QaViewport.smallLargeText]) {
          testWidgets('/main Home · Discover $qaComingSoonCategory · $locale · ${theme.name} · $viewport', (tester) async {
            final problems = <String>{};
            final errors = await captureFlutterErrors(() async {
              final app = await pumpQaApp(tester,
                  location: '${AppRoutes.main}?tab=0', locale: locale, theme: theme, viewport: viewport);
              final home = find
                  .descendant(of: find.byKey(const PageStorageKey('home-scroll')), matching: find.byType(Scrollable))
                  .first;
              // The Discover chips are the only category chips on Home.
              final chip = find.widgetWithText(CategoryChip, titles[locale]!);
              await tester.scrollUntilVisible(chip, 250, scrollable: home);
              await Scrollable.ensureVisible(tester.element(chip), alignment: 0.3);
              await settle(tester);
              await tester.tap(chip);
              await settle(tester);
              expect(find.byType(ComingSoonInlineCard), findsOneWidget);
              problems.addAll(textProblems(tester));
              await scrollThrough(tester, onStep: () => problems.addAll(textProblems(tester)));
              await unmountQaApp(tester, app);
            });
            expect(describeErrors(errors), isEmpty);
            expect(problems, isEmpty);
          });
        }
      }
    }
  });

  group('tablet 1024×1366', () {
    for (final route in tabletRoutes) {
      for (final locale in ['en', 'ar']) {
        for (final theme in qaThemes) {
          testWidgets('${route.name} · $locale · ${theme.name} · ${QaViewport.tablet}', (tester) async {
            final problems = <String>{};
            final widths = <double>{};
            final errors = await captureFlutterErrors(() async {
              final app = await pumpQaApp(tester,
                  location: route.location,
                  guest: route.guest,
                  locale: locale,
                  theme: theme,
                  viewport: QaViewport.tablet);
              void check() {
                problems.addAll(textProblems(tester));
                widths.addAll(find.byType(Scaffold).evaluate().map((e) => e.size!.width));
              }

              check();
              await scrollThrough(tester, onStep: check);
              await unmountQaApp(tester, app);
            });
            expect(describeErrors(errors), isEmpty);
            expect(problems, isEmpty);
            // Nothing stretches past the 600 px column.
            expect(widths, isNotEmpty);
            expect(widths.where((w) => w > 600), isEmpty, reason: 'Scaffold wider than the 600 px frame');
          });
        }
      }
    }
  });

  for (final route in sweepRoutes) {
    for (final locale in qaLocales) {
      for (final theme in qaThemes) {
        for (final viewport in [QaViewport.phone, QaViewport.smallLargeText]) {
          testWidgets('${route.name} · $locale · ${theme.name} · $viewport', (tester) async {
            final problems = <String>{};
            final errors = await captureFlutterErrors(() async {
              final app = await pumpQaApp(
                tester,
                location: route.location,
                extra: route.extra,
                guest: route.guest,
                locale: locale,
                theme: theme,
                viewport: viewport,
              );
              problems.addAll(textProblems(tester));
              await scrollThrough(tester, onStep: () => problems.addAll(textProblems(tester)));
              await unmountQaApp(tester, app);
            });
            expect(describeErrors(errors), isEmpty);
            expect(problems, isEmpty);
          });
        }
      }
    }
  }
}
