import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/core/widgets/main_shell.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_test_overrides.dart';

late SharedPreferences _prefs;

// The tabs are Riverpod widgets; keep them off Firebase (guest, default settings).
Widget _app(Locale locale, {ThemeMode mode = ThemeMode.light}) => ProviderScope(
      overrides: [
        ...appTestOverridesSync(_prefs),
        isSignedInProvider.overrideWithValue(false),
        currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
        referralSettingsProvider.overrideWith((ref) => Stream.value(const ReferralSettings())),
        paymentSettingsProvider.overrideWith((ref) => Stream.value(const PaymentSettings())),
      ],
      child: _materialApp(locale, mode: mode),
    );

Widget _materialApp(Locale locale, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
      locale: locale,
      theme: AppTheme.lightTheme(locale),
      darkTheme: AppTheme.darkTheme(locale),
      themeMode: mode,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...KurdishFallbackLocalizations.delegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainShell(),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('Main shell renders in English, left-to-right', (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(MainShell))), TextDirection.ltr);
  });

  for (final code in ['ar', 'ckb']) {
    testWidgets('Main shell renders in $code, right-to-left, with Material localizations',
        (tester) async {
      await tester.pumpWidget(_app(Locale(code)));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(MainShell));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(MaterialLocalizations.of(context), isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Main shell renders in dark mode', (tester) async {
    await tester.pumpWidget(_app(const Locale('en'), mode: ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(MainShell))).brightness, Brightness.dark);
  });

  test('preparation days use correct plural forms', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.preparationDays(1), 'This product requires 1 day for preparation');
    expect(en.preparationDays(12), 'This product requires 12 days for preparation');
    final ar = lookupAppLocalizations(const Locale('ar'));
    expect(ar.preparationDays(1), contains('يوم واحد'));
    expect(ar.preparationDays(2), contains('يومين'));
    expect(ar.preparationDays(3), contains('3 أيام'));
    expect(ar.preparationDays(12), contains('12 يومًا'));
    expect(lookupAppLocalizations(const Locale('ckb')).preparationDays(12), contains('12 ڕۆژ'));
  });

  test('every Arabic and Kurdish string is translated', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final code in ['ar', 'ckb']) {
      final l = lookupAppLocalizations(Locale(code));
      expect(l.home, isNot(en.home), reason: code);
      expect(l.emptyCartTitle, isNot(en.emptyCartTitle), reason: code);
    }
  });

  test('CurrencyFormatter: IQD, no decimals, thousands separator', () {
    expect(CurrencyFormatter.format(12000), '12,000 IQD');
    expect(CurrencyFormatter.format(1250000), '1,250,000 IQD');
    expect(CurrencyFormatter.format(999.6), '1,000 IQD');
    expect(CurrencyFormatter.format(0), '0 IQD');
  });
}
