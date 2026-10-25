import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/profile/data/datasources/user_repository.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_fakes.dart';

/// Pumps [initial] inside a real GoRouter so navigation can be asserted:
/// every other path renders a Text with the path itself (e.g. find.text('/otp')).
Future<GoRouter> pumpAuthApp(
  WidgetTester tester, {
  required String initialPath,
  required Map<String, Widget Function(GoRouterState)> screens,
  required FakeAuthRepository auth,
  FakeUserRepository? users,
  FakeAnalytics? analytics,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  Map<String, Object> prefs = const {},
  List<Override> extraOverrides = const [],
}) async {
  // Phone width, tall enough that the whole auth form is built at once.
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  const stubPaths = ['/main', '/otp', '/sign-in', '/sign-up', '/complete-profile', '/onboarding'];
  final router = GoRouter(
    initialLocation: initialPath,
    routes: [
      for (final entry in screens.entries)
        GoRoute(path: entry.key, builder: (_, state) => entry.value(state)),
      for (final path in stubPaths.where((p) => !screens.containsKey(p)))
        GoRoute(path: path, builder: (_, state) => Scaffold(body: Text(path))),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(users ?? FakeUserRepository()),
      analyticsServiceProvider.overrideWithValue(analytics ?? FakeAnalytics()),
      ...extraOverrides,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: locale,
      theme: AppTheme.lightTheme(locale),
      darkTheme: AppTheme.darkTheme(locale),
      themeMode: themeMode,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...KurdishFallbackLocalizations.delegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}
