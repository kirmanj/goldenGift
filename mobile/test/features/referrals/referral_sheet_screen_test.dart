import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/features/referrals/presentation/providers/referral_providers.dart';
import 'package:golden_gift/features/referrals/presentation/widgets/referral_reward_sheet.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import '../../helpers/auth_fakes.dart';
import 'rewards_test_harness.dart';

/// One "process start": a fresh ProviderContainer (so the open counter runs
/// again) over the same SharedPreferences, with Home = a ReferralSheetGate.
class _Run {
  _Run(this.container, this.router, this.shares);
  final ProviderContainer container;
  final GoRouter router;
  final List<SharedText> shares;
  FakeAnalytics get analytics => container.read(analyticsServiceProvider) as FakeAnalytics;
}

var _runs = 0;

Future<_Run> _open(
  WidgetTester tester,
  SharedPreferences prefs, {
  required FakeFirebaseFirestore db,
  User? user,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 1400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final shares = <SharedText>[];
  final container = ProviderContainer(overrides: [
    ...appTestOverridesSync(prefs, firestore: db, user: user),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(user == null ? null : rewardsUser())),
    shareTextProvider.overrideWithValue((text, {subject, origin}) async => shares.add(SharedText(text, subject))),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: AppRoutes.main,
    routes: [
      GoRoute(
        path: AppRoutes.main,
        builder: (_, __) => const Scaffold(body: ReferralSheetGate(child: Center(child: Text('home')))),
      ),
      GoRoute(path: AppRoutes.inviteAndEarn, builder: (_, __) => const Scaffold(body: Text('/invite'))),
    ],
  );
  addTearDown(router.dispose);
  final appLocale = Locale(locale);
  await tester.pumpWidget(UncontrolledProviderScope(
    key: ValueKey(_runs++),
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
  return _Run(container, router, shares);
}

void main() {
  final en = l10nFor('en');
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<FakeFirebaseFirestore> settings({int join = 5000, int order = 5000}) async {
    final db = FakeFirebaseFirestore();
    await seedReferralSettings(db, joinBonus: join, orderBonus: order);
    return db;
  }

  final sheet = find.byType(ReferralRewardSheet);

  group('once per install, from the 2nd open', () {
    testWidgets('signed in: not on the 1st open, shown on the 2nd, never again', (tester) async {
      final db = await settings();
      await _open(tester, prefs, db: db, user: FakeUser());
      expect(sheet, findsNothing);
      expect(prefs.getInt(ReferralSheetTracker.opensKey), 1);

      await _open(tester, prefs, db: db, user: FakeUser());
      expect(sheet, findsOneWidget);
      expect(prefs.getBool(ReferralSheetTracker.shownKey), isTrue);
      await tester.tap(find.byKey(const ValueKey('referral-sheet-later')));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);

      await _open(tester, prefs, db: db, user: FakeUser());
      expect(sheet, findsNothing);
      expect(prefs.getInt(ReferralSheetTracker.opensKey), 3);
    });

    testWidgets('never for guests; shown at the first signed-in open after that', (tester) async {
      final db = await settings();
      await _open(tester, prefs, db: db);
      await _open(tester, prefs, db: db);
      expect(sheet, findsNothing);
      expect(prefs.getBool(ReferralSheetTracker.shownKey), isNull);

      await _open(tester, prefs, db: db, user: FakeUser());
      expect(sheet, findsOneWidget);
    });

    testWidgets('never when both bonuses are 0', (tester) async {
      final db = await settings(join: 0, order: 0);
      await _open(tester, prefs, db: db, user: FakeUser());
      await _open(tester, prefs, db: db, user: FakeUser());
      expect(sheet, findsNothing);
      expect(prefs.getBool(ReferralSheetTracker.shownKey), isNull);
    });

    testWidgets('the keys survive logout (they do not start with cart_)', (tester) async {
      expect(ReferralSheetTracker.opensKey.startsWith('cart_'), isFalse);
      expect(ReferralSheetTracker.shownKey.startsWith('cart_'), isFalse);
    });
  });

  group('content and actions', () {
    Future<_Run> secondOpen(WidgetTester tester, FakeFirebaseFirestore db) async {
      await prefs.setInt(ReferralSheetTracker.opensKey, 1);
      return _open(tester, prefs, db: db, user: FakeUser());
    }

    testWidgets('chip, title, the two reward tiles and how it works', (tester) async {
      await secondOpen(tester, await settings(join: 5000, order: 10000));
      expect(find.text(en.referralRewardsChip), findsOneWidget);
      expect(find.text(en.referralSheetTitle), findsOneWidget);
      expect(find.text(en.referralSheetBody), findsOneWidget);
      expect(find.text('5,000 IQD'), findsOneWidget);
      expect(find.text(en.referralFriendJoins), findsOneWidget);
      expect(find.text('10,000 IQD'), findsOneWidget);
      expect(find.text(en.referralFirstPaidOrder), findsOneWidget);
      expect(find.text(en.referralShareLinkTitle), findsOneWidget);
      expect(find.text(en.referralWatchBoth('5,000 IQD', '10,000 IQD')), findsOneWidget);
      expect(find.text(en.referralMyRewards), findsOneWidget);
      expect(find.text(en.referralInvite), findsOneWidget);
      expect(find.text(en.referralMaybeLater), findsOneWidget);
    });

    testWidgets('a 0 join bonus hides the "Friend joins" tile and rewords the explanation', (tester) async {
      await secondOpen(tester, await settings(join: 0, order: 7000));
      expect(find.text(en.referralFriendJoins), findsNothing);
      expect(find.text(en.referralFirstPaidOrder), findsOneWidget);
      expect(find.text(en.referralWatchYou('7,000 IQD')), findsOneWidget);
    });

    testWidgets('Invite opens the share sheet with the code and logs referral_share', (tester) async {
      final run = await secondOpen(tester, await settings());
      await tester.tap(find.byKey(const ValueKey('referral-sheet-invite')));
      await tester.pumpAndSettle();
      expect(run.shares.single.text, contains('https://goldengift.app/r/ZQC8YC'));
      expect(run.analytics.events[AnalyticsEvents.referralShare], {'method': 'share'});
    });

    testWidgets('My Rewards closes the sheet and opens Invite & Earn', (tester) async {
      final run = await secondOpen(tester, await settings());
      await tester.tap(find.byKey(const ValueKey('referral-sheet-rewards')));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(run.router.state.uri.toString(), AppRoutes.inviteAndEarn);
    });

    for (final (locale, mode) in [
      ('ar', ThemeMode.dark),
      ('ckb', ThemeMode.light),
      ('ckb', ThemeMode.dark),
      ('en', ThemeMode.dark)
    ]) {
      testWidgets('fits at 320 px with 130 % text ($locale, ${mode.name})', (tester) async {
        await prefs.setInt(ReferralSheetTracker.opensKey, 1);
        await _open(
          tester,
          prefs,
          db: await settings(join: 1250000, order: 1250000),
          user: FakeUser(),
          locale: locale,
          themeMode: mode,
          size: const Size(320, 1400),
          textScale: 1.3,
        );
        final l10n = l10nFor(locale);
        expect(find.text(l10n.referralSheetTitle), findsOneWidget);
        if (locale != 'en') expect(Directionality.of(tester.element(sheet)), TextDirection.rtl);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('referral link opened while signed in', () {
    testWidgets('Home explains that codes are for new accounts and links to Invite & Earn', (tester) async {
      final run = await _open(tester, prefs, db: await settings(), user: FakeUser());
      run.container.read(referralLinkNoticeProvider.notifier).state = true;
      await tester.pumpAndSettle();
      expect(find.text(en.referralLinkSignedIn), findsOneWidget);
      expect(run.container.read(referralLinkNoticeProvider), isFalse);
      await tester.tap(find.text(en.inviteAndEarn));
      await tester.pumpAndSettle();
      expect(run.router.state.uri.toString(), AppRoutes.inviteAndEarn);
    });

    Future<(String, bool)> redirect(User? user) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(overrides: [
        ...appTestOverridesSync(await SharedPreferences.getInstance(), user: user),
      ]);
      addTearDown(container.dispose);
      await container.read(authStateProvider.future);
      final target = container.read(Provider((ref) => referralLinkRedirect(ref, 'ABC123')));
      await Future<void>.delayed(Duration.zero); // the notice is set in a microtask
      return (target, container.read(referralLinkNoticeProvider));
    }

    test('/r/{code}: guests go to Sign Up with the code', () async {
      expect(await redirect(null), ('${AppRoutes.signUp}?ref=ABC123', false));
    });

    test('/r/{code}: a signed-in customer goes to Main with the notice', () async {
      expect(await redirect(FakeUser()), (AppRoutes.main, true));
    });
  });
}
