import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/services/callable.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/ai_search/data/ai_search_repository.dart';
import 'package:golden_gift/features/ai_search/presentation/screens/ai_gift_search_screen.dart';
import 'package:golden_gift/features/products/data/datasources/product_sources.dart';
import 'package:golden_gift/features/products/data/product_search_repository.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/features/secret_santa/presentation/providers/secret_santa_providers.dart';
import 'package:golden_gift/features/secret_santa/presentation/screens/secret_santa_group_screen.dart';
import 'package:golden_gift/features/secret_santa/presentation/screens/secret_santa_join_screen.dart';
import 'package:golden_gift/features/secret_santa/presentation/screens/secret_santa_screen.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import '../../helpers/auth_fakes.dart';

/// Firebase-free harness for the Phase 9 screens (AI Gift Search, Secret
/// Santa) inside a real GoRouter with the app's paths. Stub routes show where
/// navigation went: `/product/p1` → "product p1", `/products?…` →
/// "products price=0,1", `/sign-in` → "/sign-in", `/main?tab=0` → "main tab 0".

/// Scripted Cloud Functions: one handler per callable name; a name without a
/// handler fails like an undeployed function (`not-found` / "NOT_FOUND").
class FakeCallables {
  final calls = <(String, Map<String, dynamic>)>[];
  final handlers = <String, FutureOr<Object?> Function(Map<String, dynamic> data)>{};

  Future<Object?> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    final handler = handlers[name];
    if (handler == null) throw FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND');
    return await handler(data);
  }

  List<Map<String, dynamic>> callsTo(String name) => [for (final c in calls) if (c.$1 == name) c.$2];
}

class SharedText {
  SharedText(this.text, this.subject);
  final String text;
  final String? subject;
}

class Phase9Harness {
  Phase9Harness({
    required this.container,
    required this.router,
    required this.firestore,
    required this.callables,
    required this.analytics,
    required this.shared,
  });

  final ProviderContainer container;
  final GoRouter router;
  final FakeFirebaseFirestore firestore;
  final FakeCallables callables;
  final FakeAnalytics analytics;
  final List<SharedText> shared;

  String get location => router.state.uri.toString();
}

UserModel testProfile({String uid = 'u1', String name = 'Sara Ahmed'}) =>
    UserModel(uid: uid, name: name, phone: '+9647501234567');

Future<Phase9Harness> pumpPhase9(
  WidgetTester tester, {
  required String initialPath,
  User? user,
  bool guest = false,
  UserModel? profile,
  FakeFirebaseFirestore? firestore,
  FakeCallables? callables,
  DateTime? now,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 2400),
  double textScale = 1,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = firestore ?? FakeFirebaseFirestore();
  final fns = callables ?? FakeCallables();
  final signedIn = guest ? null : (user ?? FakeUser(uid: 'u1'));
  final shared = <SharedText>[];
  final clock = now ?? DateTime(2026, 10, 21, 9);
  final CallableInvoker invoker = fns.call;

  final container = ProviderContainer(overrides: [
    ...appTestOverridesSync(prefs, firestore: db, user: signedIn),
    callableInvokerProvider.overrideWithValue(invoker),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(signedIn == null ? null : (profile ?? testProfile()))),
    aiSearchRepositoryProvider.overrideWithValue(AiSearchRepository(
      db,
      invoker,
      ProductSearchRepository(
        firestore: FirestoreProductSource(db),
        searchSettings: () async => const SearchSettings(),
        httpClient: http.Client(),
      ),
    )),
    secretSantaShareProvider.overrideWithValue((text, {subject, origin}) async => shared.add(SharedText(text, subject))),
    secretSantaClockProvider.overrideWithValue(() => clock),
    ...overrides,
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: initialPath,
    routes: [
      GoRoute(path: AppRoutes.aiGiftSearch, builder: (_, __) => const AiGiftSearchScreen()),
      GoRoute(path: AppRoutes.secretSanta, builder: (_, __) => const SecretSantaScreen()),
      GoRoute(
        path: AppRoutes.secretSantaGroup,
        builder: (_, state) => SecretSantaGroupScreen(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.secretSantaJoinLink,
        builder: (_, state) => SecretSantaJoinScreen(code: state.pathParameters['code']!),
      ),
      GoRoute(
        path: AppRoutes.productDetails,
        builder: (_, state) => Scaffold(body: Text('product ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: AppRoutes.products,
        builder: (_, state) => Scaffold(body: Text('products price=${state.uri.queryParameters['price']}')),
      ),
      GoRoute(
        path: AppRoutes.main,
        builder: (_, state) => Scaffold(body: Text('main tab ${state.uri.queryParameters['tab']}')),
      ),
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
  return Phase9Harness(
    container: container,
    router: router,
    firestore: db,
    callables: fns,
    analytics: container.read(analyticsServiceProvider) as FakeAnalytics,
    shared: shared,
  );
}

AppLocalizations l10nFor(String code) => lookupAppLocalizations(Locale(code));

/// An active product doc the keyword fallback can find.
Future<void> seedProduct(FakeFirebaseFirestore db, String id, String title, int price) =>
    db.doc(FirestorePaths.productDoc(id)).set({
      'title': title,
      'titleAr': '$title (ar)',
      'titleKu': '$title (ku)',
      'storeId': 's1',
      'price': price,
      'isActive': true,
      'availability': ProductAvailability.sameDay.name,
      'searchKeywords': title.toLowerCase().split(' '),
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      'salesCount': 0,
    });
