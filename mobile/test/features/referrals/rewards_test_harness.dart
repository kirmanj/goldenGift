import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/features/promo_codes/presentation/screens/promo_codes_screen.dart';
import 'package:golden_gift/features/referrals/presentation/providers/referral_providers.dart';
import 'package:golden_gift/features/referrals/presentation/screens/invite_earn_screen.dart';
import 'package:golden_gift/features/wallet/presentation/screens/wallet_screen.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import '../../helpers/auth_fakes.dart';

/// Firebase-free harness for the Phase 7 screens (My Wallet, Invite & Earn,
/// Promo Codes) inside a real GoRouter, on a seeded [FakeFirebaseFirestore]
/// (via `appTestOverridesSync`). `/main?tab=N` renders "main tab N";
/// `/sign-in`, `/sign-up` render their path.

class SharedText {
  SharedText(this.text, this.subject);
  final String text;
  final String? subject;
}

class RewardsHarness {
  RewardsHarness(this.container, this.router, this.db, this.prefs, this.shares, this.clipboard);
  final ProviderContainer container;
  final GoRouter router;
  final FakeFirebaseFirestore db;
  final SharedPreferences prefs;
  final List<SharedText> shares;
  final List<String> clipboard;

  FakeAnalytics get analytics => container.read(analyticsServiceProvider) as FakeAnalytics;
  String get location => router.state.uri.toString();
}

// ─── Seeding ────────────────────────────────────────────────────────────────

Future<void> seedReferralSettings(
  FakeFirebaseFirestore db, {
  int joinBonus = 5000,
  int orderBonus = 5000,
  int maxPerMonth = 0,
  int expiryDays = 0,
}) =>
    db.doc(FirestorePaths.settingsDoc('referral')).set({
      'joinBonus': joinBonus,
      'orderBonus': orderBonus,
      'maxReferralsPerMonth': maxPerMonth,
      'creditsExpiryDays': expiryDays,
    });

Future<void> seedWallet(FakeFirebaseFirestore db, {String uid = 'u1', int balance = 0, int credits = 0}) =>
    db.doc(FirestorePaths.walletDoc(uid)).set({'balance': balance, 'credits': credits, 'currency': 'IQD'});

Future<void> seedTxn(
  FakeFirebaseFirestore db,
  String id, {
  String uid = 'u1',
  required int amount,
  String type = 'referralCredit',
  String bucket = 'credits',
  String? title,
  String? titleAr,
  String? titleKu,
  DateTime? at,
}) =>
    db.collection(FirestorePaths.walletTxns(uid)).doc(id).set({
      'type': type,
      'amount': amount,
      'bucket': bucket,
      if (title != null) 'title': title,
      if (titleAr != null) 'titleAr': titleAr,
      if (titleKu != null) 'titleKu': titleKu,
      'balanceAfter': 0,
      'creditsAfter': 0,
      'createdAt': Timestamp.fromDate(at ?? DateTime(2026, 10, 1, 9, 30)),
    });

Future<void> seedPromo(
  FakeFirebaseFirestore db,
  String code, {
  String type = 'percent',
  int value = 10,
  bool isPublic = true,
  bool isActive = true,
  DateTime? expiresAt,
  int? minOrder,
  int? maxDiscount,
  int? usageLimit,
  int usageCount = 0,
  int perUserLimit = 1,
  bool firstOrderOnly = false,
  List<String> categoryIds = const [],
  String? description,
}) =>
    db.doc('${FirestorePaths.promoCodes}/$code').set({
      'code': code,
      'title': 'Title $code',
      'description': description ?? 'Use $code at checkout and save.',
      'descriptionAr': 'استخدم $code عند الدفع',
      'descriptionKu': '$code لە کاتی پارەداندا بەکاربهێنە',
      'type': type,
      'value': value,
      'isPublic': isPublic,
      'isActive': isActive,
      'perUserLimit': perUserLimit,
      'usageCount': usageCount,
      'firstOrderOnly': firstOrderOnly,
      'categoryIds': categoryIds,
      if (minOrder != null) 'minOrder': minOrder,
      if (maxDiscount != null) 'maxDiscount': maxDiscount,
      if (usageLimit != null) 'usageLimit': usageLimit,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
    });

Future<void> seedReferral(
  FakeFirebaseFirestore db,
  String id, {
  String referrer = 'u1',
  String status = 'pending',
  String? name,
  DateTime? at,
}) =>
    db.doc('${FirestorePaths.referrals}/$id').set({
      'referrerUid': referrer,
      'referredUid': id,
      'code': 'ZQC8YC',
      'status': status,
      if (name != null) 'referredName': name,
      'createdAt': Timestamp.fromDate(at ?? DateTime(2026, 10, 2)),
    });

UserModel rewardsUser({String? referralCode = 'ZQC8YC', int totalOrders = 0}) => UserModel(
    uid: 'u1', name: 'Krmanj Mzuri', phone: '7505448229', referralCode: referralCode, totalOrders: totalOrders);

// ─── Pump ───────────────────────────────────────────────────────────────────

Future<RewardsHarness> pumpRewardsApp(
  WidgetTester tester, {
  required String initialPath,
  List<String> push = const [],
  User? user,
  UserModel? profile,
  FakeFirebaseFirestore? firestore,
  Map<String, Object> prefs = const {},
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 2400),
  double textScale = 1,
  Object? shareError,

  /// False while something animates forever (e.g. a skeleton shimmer).
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final db = firestore ?? FakeFirebaseFirestore();
  final shares = <SharedText>[];
  final clipboard = <String>[];

  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

  final container = ProviderContainer(overrides: [
    ...appTestOverridesSync(sharedPrefs, firestore: db, user: user),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(user == null ? null : (profile ?? rewardsUser()))),
    shareTextProvider.overrideWithValue((text, {subject, origin}) async {
      if (shareError != null) throw shareError;
      shares.add(SharedText(text, subject));
    }),
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: initialPath,
    routes: [
      GoRoute(path: AppRoutes.wallet, builder: (_, __) => const WalletScreen()),
      GoRoute(path: AppRoutes.inviteAndEarn, builder: (_, __) => const InviteEarnScreen()),
      GoRoute(path: AppRoutes.promoCodes, builder: (_, __) => const PromoCodesScreen()),
      GoRoute(
        path: AppRoutes.main,
        builder: (_, state) => Scaffold(body: Text('main tab ${state.uri.queryParameters['tab']}')),
      ),
      for (final path in [AppRoutes.signIn, AppRoutes.signUp])
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(path))),
    ],
  );
  addTearDown(router.dispose);

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
  for (final path in push) {
    unawaited(router.push(path));
    await tester.pump();
  }
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  return RewardsHarness(container, router, db, sharedPrefs, shares, clipboard);
}

AppLocalizations l10nFor(String code) => lookupAppLocalizations(Locale(code));

/// Colour of the first [Text] matching [text] (exact).
Color? textColor(WidgetTester tester, String text) => tester.widget<Text>(find.text(text).first).style?.color;
