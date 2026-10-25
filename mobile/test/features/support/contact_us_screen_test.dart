import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/support/presentation/widgets/contact_card.dart';
import 'package:golden_gift/models/app_settings_model.dart';

import '../checkout/phase6_test_harness.dart';

final _en = l10nFor('en');

const _settings = GeneralSettings(
  whatsapp: '+964 750 123 4567',
  supportPhone: '+964 770 000 1111',
  email: '',
  instagram: '@goldengift.iq',
);

void main() {
  testWidgets('shows a card per configured channel and hides empty ones', (tester) async {
    await pumpPhase6(tester, initialPath: AppRoutes.contactUs, settings: _settings);
    expect(find.text(_en.contactUsBody), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-whatsapp')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-phone')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-instagram')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-email')), findsNothing);
    expect(find.text('@goldengift.iq'), findsOneWidget);
  });

  testWidgets('cards open WhatsApp, the dialer and Instagram outside the app', (tester) async {
    final h = await pumpPhase6(tester, initialPath: AppRoutes.contactUs, settings: _settings);
    for (final key in ['contact-whatsapp', 'contact-phone', 'contact-instagram']) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }
    expect(h.openedLinks.map((u) => u.toString()), [
      'https://wa.me/9647501234567',
      'tel:+9647700001111',
      'https://instagram.com/goldengift.iq',
    ]);
    expect(find.text(_en.somethingWentWrong), findsNothing);
  });

  testWidgets('a link nothing can open → "Something went wrong"', (tester) async {
    await pumpPhase6(tester,
        initialPath: AppRoutes.contactUs,
        settings: const GeneralSettings(email: 'help@goldengift.app'),
        opener: (_) async => false);
    await tester.tap(find.byKey(const ValueKey('contact-email')));
    await tester.pumpAndSettle();
    expect(find.text(_en.somethingWentWrong), findsOneWidget);
  });

  test('links', () {
    expect(contactUri(ContactChannel.email, const GeneralSettings(email: ' help@goldengift.app ')).toString(),
        'mailto:help@goldengift.app');
    expect(
        contactUri(ContactChannel.instagram, const GeneralSettings(instagram: 'https://instagram.com/gg')).toString(),
        'https://instagram.com/gg');
    expect(contactUri(ContactChannel.whatsapp, const GeneralSettings(whatsapp: '  ')), isNull);
    expect(contactUri(ContactChannel.phone, const GeneralSettings()), isNull);
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await pumpPhase6(tester,
            initialPath: AppRoutes.contactUs, settings: _settings, locale: locale, themeMode: mode);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('320 px, 1.3× text', (tester) async {
      await pumpPhase6(tester,
          initialPath: AppRoutes.contactUs,
          settings: _settings,
          locale: 'ckb',
          size: const Size(320, 900),
          textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });
}
