import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/core/widgets/main_shell.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/features/profile/presentation/screens/profile_screen.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import 'profile_test_harness.dart';

late SharedPreferences _prefs;

/// The Profile tab inside the real MainShell (floating bottom nav, extendBody).
Widget _shell({required bool signedIn, String locale = 'en', ThemeMode mode = ThemeMode.light}) {
  final appLocale = Locale(locale);
  return ProviderScope(
    overrides: [
        ...appTestOverridesSync(_prefs),
      isSignedInProvider.overrideWithValue(signedIn),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(signedIn ? testUser() : null)),
      referralSettingsProvider.overrideWith((ref) => Stream.value(const ReferralSettings(orderBonus: 5000))),
      paymentSettingsProvider.overrideWith((ref) => Stream.value(const PaymentSettings(card: true))),
    ],
    child: MaterialApp(
      locale: appLocale,
      theme: AppTheme.lightTheme(appLocale),
      darkTheme: AppTheme.darkTheme(appLocale),
      themeMode: mode,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...KurdishFallbackLocalizations.delegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainShell(initialIndex: 2),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('the last row scrolls clear of the floating bottom nav', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final en = l10nFor('en');

    await tester.pumpWidget(_shell(signedIn: true));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.dragUntilVisible(
      find.text(en.logout),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.fling(find.byType(Scrollable).first, const Offset(0, -2000), 3000);
    await tester.pumpAndSettle();

    final logoutBottom = tester.getBottomLeft(find.text(en.logout)).dy;
    final navTop = tester.getTopLeft(find.text(en.profile)).dy; // nav label
    expect(logoutBottom, lessThan(navTop));
  });

  for (final (locale, mode) in [('en', ThemeMode.dark), ('ar', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
    testWidgets('guest Profile tab renders in the shell ($locale, ${mode.name})', (tester) async {
      await tester.pumpWidget(_shell(signedIn: false, locale: locale, mode: mode));
      await tester.pumpAndSettle();
      expect(find.text(l10nFor(locale).guestProfileTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
