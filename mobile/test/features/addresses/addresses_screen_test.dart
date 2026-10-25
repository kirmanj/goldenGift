import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/country_codes.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/addresses/presentation/widgets/address_card.dart';

import '../checkout/phase6_test_harness.dart';

final _en = l10nFor('en');

Finder _field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

Future<FakeFirebaseFirestore> _twoAddresses() async {
  final db = FakeFirebaseFirestore();
  await seedAddress(db, testAddress('a1', isDefault: true));
  await seedAddress(db, testAddress('a2', label: 'Work', city: 'duhok'));
  return db;
}

void main() {
  group('Saved Addresses (SRS §5.20)', () {
    testWidgets('cards: label, Default chip, recipient + LTR phone, localized city, street line', (tester) async {
      await pumpPhase6(tester, initialPath: AppRoutes.addresses, firestore: await _twoAddresses(), locale: 'ar');
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.byKey(const ValueKey('default-chip-a1')), findsOneWidget);
      expect(find.byKey(const ValueKey('default-chip-a2')), findsNothing);
      expect(find.text('أربيل'), findsOneWidget);
      expect(find.text('دهوك'), findsOneWidget);
      final phone = tester.widget<Text>(find.text('+964 750 123 4567').first);
      expect(phone.textDirection, TextDirection.ltr);
      expect(find.text('100m Road, B12 · Ankawa'), findsNWidgets(2));
    });

    testWidgets('menu: set as default', (tester) async {
      final h = await pumpPhase6(tester, initialPath: AppRoutes.addresses, firestore: await _twoAddresses());
      await tester.tap(find.byKey(const ValueKey('address-menu-a2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.setAsDefault));
      await tester.pumpAndSettle();
      expect((await h.firestore.doc('users/u1/addresses/a2').get()).data()!['isDefault'], isTrue);
      expect((await h.firestore.doc('users/u1/addresses/a1').get()).data()!['isDefault'], isFalse);
    });

    testWidgets('menu: delete asks first', (tester) async {
      final h = await pumpPhase6(tester, initialPath: AppRoutes.addresses, firestore: await _twoAddresses());
      await tester.tap(find.byKey(const ValueKey('address-menu-a2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.delete).last);
      await tester.pumpAndSettle();
      expect(find.text(_en.deleteAddressConfirm), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-address')));
      await tester.pumpAndSettle();
      expect((await h.firestore.doc('users/u1/addresses/a2').get()).exists, isFalse);
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('select mode: tapping an address returns it', (tester) async {
      await pumpPhase6(tester, initialPath: '/picker', firestore: await _twoAddresses());
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('address-a2')));
      await tester.pumpAndSettle();
      expect(find.text('picked: Work'), findsOneWidget);
    });

    testWidgets('select mode: a newly added address is returned straight away', (tester) async {
      await pumpPhase6(tester, initialPath: '/picker', firestore: await _twoAddresses());
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-address-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(_field('address-label'), 'Mum');
      await tester.enterText(_field('address-name'), 'Layla');
      await tester.enterText(_field('address-phone'), '7701234567');
      await tester.enterText(_field('address-area'), 'Center');
      await tester.enterText(_field('address-street'), 'Main St');
      await tester.tap(find.byKey(const ValueKey('address-city')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('city-duhok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('address-save')));
      await tester.pumpAndSettle();
      expect(find.text('picked: Mum'), findsOneWidget);
    });

    testWidgets('empty state with Add address', (tester) async {
      final h = await pumpPhase6(tester, initialPath: AppRoutes.addresses);
      expect(find.text(_en.noAddressesTitle), findsOneWidget);
      await tester.tap(find.text(_en.addAddress));
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.addressForm);
    });

    testWidgets('guests see the sign-in card', (tester) async {
      await pumpPhase6(tester, initialPath: AppRoutes.addresses, guest: true);
      expect(find.byKey(const ValueKey('guest-sign-in-card')), findsOneWidget);
    });
  });

  group('Address form', () {
    testWidgets('required fields and phone validation; nothing is written while invalid', (tester) async {
      final h = await pumpPhase6(tester, initialPath: AppRoutes.addressForm);
      await tester.tap(find.byKey(const ValueKey('address-save')));
      await tester.pumpAndSettle();
      // label, name, phone, city, area, street
      expect(find.text(_en.errorRequired), findsNWidgets(6));

      await tester.enterText(_field('address-phone'), '123');
      await tester.tap(find.byKey(const ValueKey('address-save')));
      await tester.pumpAndSettle();
      expect(find.text(_en.errorInvalidPhone), findsOneWidget);
      expect((await h.firestore.collection('users/u1/addresses').get()).docs, isEmpty);
    });

    testWidgets('a valid form saves (first address becomes the default) and pops', (tester) async {
      final h = await pumpPhase6(tester, initialPath: AppRoutes.addressForm);
      await tester.enterText(_field('address-label'), 'Home');
      await tester.enterText(_field('address-name'), 'Sara Ahmed');
      await tester.enterText(_field('address-phone'), '0750 123 4567');
      await tester.tap(find.byKey(const ValueKey('address-city')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('city-erbil')));
      await tester.pumpAndSettle();
      expect(find.text('Erbil'), findsOneWidget);
      await tester.enterText(_field('address-area'), 'Ankawa');
      await tester.enterText(_field('address-street'), '100m Road');
      await tester.enterText(_field('address-notes'), 'Blue door');
      await tester.tap(find.byKey(const ValueKey('address-save')));
      await tester.pumpAndSettle();
      final doc = (await h.firestore.collection('users/u1/addresses').get()).docs.single.data();
      expect(doc['label'], 'Home');
      expect(doc['phone'], '+9647501234567');
      expect(doc['city'], 'erbil');
      expect(doc['notes'], 'Blue door');
      expect(doc['isDefault'], isTrue);
    });

    testWidgets('edit loads the existing address and keeps its id', (tester) async {
      final db = await _twoAddresses();
      final h = await pumpPhase6(tester, initialPath: '${AppRoutes.addressForm}?id=a2', firestore: db);
      expect(find.text(_en.editAddress), findsOneWidget);
      expect(tester.widget<TextField>(_field('address-label')).controller!.text, 'Work');
      expect(tester.widget<TextField>(_field('address-phone')).controller!.text, '7501234567');
      expect(find.text('Duhok'), findsOneWidget);
      await tester.enterText(_field('address-label'), 'Office');
      await tester.tap(find.byKey(const ValueKey('address-save')));
      await tester.pumpAndSettle();
      final docs = (await h.firestore.collection('users/u1/addresses').get()).docs;
      expect(docs, hasLength(2));
      expect((await h.firestore.doc('users/u1/addresses/a2').get()).data()!['label'], 'Office');
    });
  });

  test('phones: E.164 round trip and legacy national numbers', () {
    expect(addressPhoneValue('0750 123 4567', CountryCodes.iraq), '+9647501234567');
    final (c, national) = splitAddressPhone('+905321234567');
    expect(c.isoCode, 'TR');
    expect(national, '5321234567');
    final (legacy, digits) = splitAddressPhone('7501234567');
    expect(legacy.isoCode, 'IQ');
    expect(digits, '7501234567');
    expect(addressPhoneDisplay('+9647501234567'), '+964 750 123 4567');
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('list + form $locale ${mode.name}', (tester) async {
        await pumpPhase6(tester,
            initialPath: AppRoutes.addresses, firestore: await _twoAddresses(), locale: locale, themeMode: mode);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('add-address-fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('address-save')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('320 px, 1.3× text', (tester) async {
      await pumpPhase6(tester,
          initialPath: AppRoutes.addresses,
          firestore: await _twoAddresses(),
          locale: 'ckb',
          size: const Size(320, 1600),
          textScale: 1.3);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('add-address-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('address-save')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
