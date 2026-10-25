import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/addresses/presentation/providers/address_map_providers.dart';
import 'package:golden_gift/features/addresses/presentation/screens/address_form_screen.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import '../../helpers/auth_fakes.dart';
import '../checkout/phase6_test_harness.dart' show pumpPhase6, testAddress, testCities;

AppLocalizations _l10n(String code) => lookupAppLocalizations(Locale(code));
final _en = _l10n('en');

Finder _field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

/// Stands in for the Google map: shows where it opened and "moves" on tap.
Widget _fakeMap(BuildContext context, {required GeoPin initial, required ValueChanged<GeoPin> onCenterChanged}) =>
    ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('map at ${initial.lat},${initial.lng}', key: const ValueKey('fake-map')),
            TextButton(
              key: const ValueKey('fake-map-move'),
              onPressed: () => onCenterChanged((lat: 36.2, lng: 44.05)),
              child: const Text('move'),
            ),
          ],
        ),
      ),
    );

Future<FakeFirebaseFirestore> _pumpMaps(
  WidgetTester tester, {
  String path = AppRoutes.addressForm,
  FakeFirebaseFirestore? firestore,
  String locale = 'en',
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(390, 2400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = firestore ?? FakeFirebaseFirestore();
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => context.push(path), child: const Text('open form')),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.addressForm,
        builder: (_, state) => AddressFormScreen(addressId: state.uri.queryParameters['id']),
      ),
    ],
  );
  final appLocale = Locale(locale);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...appTestOverridesSync(prefs, firestore: db, user: FakeUser(uid: 'u1')),
      citiesProvider.overrideWith((ref) => Stream.value(testCities)),
      mapsEnabledProvider.overrideWithValue(true),
      addressMapBuilderProvider.overrideWithValue(_fakeMap),
    ],
    child: MaterialApp.router(
      routerConfig: router,
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open form'));
  await tester.pumpAndSettle();
  return db;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _fillRequired(WidgetTester tester) async {
  await tester.enterText(_field('address-label'), 'Home');
  await tester.enterText(_field('address-name'), 'Sara Ahmed');
  await tester.enterText(_field('address-phone'), '0750 123 4567');
  await _tap(tester, find.byKey(const ValueKey('address-city')));
  await tester.tap(find.byKey(const ValueKey('city-erbil')));
  await tester.pumpAndSettle();
  await tester.enterText(_field('address-area'), 'Ankawa');
  await tester.enterText(_field('address-street'), '100m Road');
}

void main() {
  testWidgets('maps disabled (the default in tests): nothing new in the form', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.addressForm);
    expect(find.byKey(const ValueKey('address-pin-map')), findsNothing);
    expect(find.text(_en.addressPinOnMap), findsNothing);
  });

  testWidgets('maps disabled: editing keeps an existing pin', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1/addresses/a1').set({...testAddress('a1').toMap(), 'lat': 36.2, 'lng': 44.05});
    final h = await pumpPhase6(tester, initialPath: '${AppRoutes.addressForm}?id=a1', firestore: db);
    expect(find.byKey(const ValueKey('address-pin-preview')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('address-save')));
    await tester.pumpAndSettle();
    final doc = (await h.firestore.doc('users/u1/addresses/a1').get()).data()!;
    expect((doc['lat'], doc['lng']), (36.2, 44.05));
  });

  testWidgets('pin on map → move the map → Use this location → saved lat/lng', (tester) async {
    final db = await _pumpMaps(tester);
    expect(find.text(_en.addressPinOnMapHint), findsOneWidget);
    await _fillRequired(tester);
    await _tap(tester, find.byKey(const ValueKey('address-pin-map')));

    expect(find.text(_en.addressMapTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('map-centre-pin')), findsOneWidget);
    expect(find.text('map at ${defaultMapCenter.lat},${defaultMapCenter.lng}'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('fake-map-move')));
    await _tap(tester, find.byKey(const ValueKey('map-use-location')));

    expect(find.byKey(const ValueKey('address-pin-preview')), findsOneWidget);
    expect(find.text(_en.addressLocationPinned), findsOneWidget);
    expect(find.text('36.20000, 44.05000'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('address-save')));
    final doc = (await db.collection('users/u1/addresses').get()).docs.single.data();
    expect(doc['lat'], 36.2);
    expect(doc['lng'], 44.05);
  });

  testWidgets('going back from the map pins nothing', (tester) async {
    await _pumpMaps(tester);
    await _tap(tester, find.byKey(const ValueKey('address-pin-map')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('address-pin-preview')), findsNothing);
    expect(find.byKey(const ValueKey('address-pin-map')), findsOneWidget);
  });

  testWidgets('an existing pin opens the map there; Remove clears it on save', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1/addresses/a1').set({...testAddress('a1').toMap(), 'lat': 36.3, 'lng': 43.9});
    await _pumpMaps(tester, path: '${AppRoutes.addressForm}?id=a1', firestore: db);
    expect(find.text('36.30000, 43.90000'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('address-pin-change')));
    expect(find.text('map at 36.3,43.9'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const ValueKey('address-pin-remove')));
    expect(find.byKey(const ValueKey('address-pin-map')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('address-save')));
    final doc = (await db.doc('users/u1/addresses/a1').get()).data()!;
    expect(doc['lat'], isNull);
    expect(doc['lng'], isNull);
  });

  for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
    testWidgets('form + map picker in $locale (${mode.name})', (tester) async {
      await _pumpMaps(tester, locale: locale, mode: mode);
      final l10n = _l10n(locale);
      expect(find.text(l10n.addressPinOnMap), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('address-pin-map')));
      expect(find.text(l10n.addressMapHelp), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('map-use-location')));
      expect(find.text(l10n.addressLocationPinned), findsOneWidget);
      expect(Directionality.of(tester.element(find.byKey(const ValueKey('address-pin-preview')))), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in ['en', 'ar', 'ckb']) {
    testWidgets('320 px, 1.3× text ($locale)', (tester) async {
      await _pumpMaps(tester, locale: locale, size: const Size(320, 2400), textScale: 1.3);
      await _tap(tester, find.byKey(const ValueKey('address-pin-map')));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byKey(const ValueKey('map-use-location')));
      expect(find.byKey(const ValueKey('address-pin-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('pins print with 5 decimals', () {
    expect(formatGeoPin((lat: 36.19110, lng: 44.0092)), '36.19110, 44.00920');
  });
}
