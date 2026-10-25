import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/features/partners/presentation/screens/become_partner_screen.dart';

import '../gift_cards/phase8_test_harness.dart';

final _en = l10nFor('en');
const _path = '/become-partner';

Future<void> _store(FakeFirebaseFirestore db, String status) => db.doc('stores/s1').set({
      'name': 'Wood & Words',
      'ownerUid': 'u1',
      'status': status,
    });

Future<void> _fillValid(WidgetTester tester) async {
  await enterIn(tester, 'partner-store-name', 'Wood & Words');
  await enterIn(tester, 'partner-category', 'Engraved wood');
  await enterIn(tester, 'partner-instagram', '@wood.words');
}

void main() {
  test('Instagram handles', () {
    expect(normalizeInstagram('@wood.words'), 'wood.words');
    expect(normalizeInstagram(' gift_shop '), 'gift_shop');
    expect(normalizeInstagram(''), '');
    expect(normalizeInstagram('bad!name'), isNull);
  });

  testWidgets('landing: hero, benefits and the form prefilled from the profile', (tester) async {
    await pumpPhase8(tester, initialPath: _path);
    expect(find.text(_en.partnerHeroTitle), findsOneWidget);
    expect(find.text(_en.partnerBenefitReachTitle), findsOneWidget);
    expect(find.text(_en.partnerBenefitDashboardTitle), findsOneWidget);
    expect(find.text(_en.partnerBenefitPersonalTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('partner-form')), findsOneWidget);
    expect(find.text('Sara Ahmed'), findsOneWidget);
    expect(find.text('7501234567'), findsOneWidget);
    expect(find.text('Erbil'), findsOneWidget); // profile city
  });

  testWidgets('validation runs before any upload or call', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, profile: null);
    await tapKey(tester, 'partner-submit');
    expect(find.text(_en.errorRequired), findsNWidgets(5)); // store, owner, phone, city, category
    expect(find.text(_en.giftCardFixErrors), findsOneWidget);

    await enterIn(tester, 'partner-store-name', 'W');
    await enterIn(tester, 'partner-phone', '123');
    await enterIn(tester, 'partner-instagram', 'bad!name');
    await tapKey(tester, 'partner-submit');
    expect(find.text(_en.partnerStoreNameLength), findsOneWidget);
    expect(find.text(_en.errorInvalidPhone), findsOneWidget);
    expect(find.text(_en.partnerInstagramInvalid), findsOneWidget);
    expect(h.callable.calls, isEmpty);
    expect(h.uploads.folders, isEmpty);
  });

  testWidgets('submit uploads samples to partner_applications/{uid} and sends the application', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path);
    await _fillValid(tester);
    // Pick another city through the sheet.
    await tapKey(tester, 'partner-city');
    await tester.tap(find.byKey(const ValueKey('city-duhok')));
    await tester.pumpAndSettle();
    await addPhoto(tester, 'partner-photos-add', _en);
    await addPhoto(tester, 'partner-photos-add', _en);
    await tapKey(tester, 'partner-submit');

    expect(h.uploads.folders, ['partner_applications/u1']);
    expect(h.uploads.counts, [2]);
    final sent = h.callable.callsTo('submitPartnerApplication').single;
    expect(sent, {
      'storeName': 'Wood & Words',
      'ownerName': 'Sara Ahmed',
      'phone': '+9647501234567',
      'city': 'duhok',
      'category': 'Engraved wood',
      'instagram': 'wood.words',
      'samplePhotos': ['https://img/partner_applications/u1/1.jpg', 'https://img/partner_applications/u1/2.jpg'],
    });
    expect(find.byKey(const ValueKey('partner-thanks')), findsOneWidget);
    expect(find.byKey(const ValueKey('partner-form')), findsNothing);
  });

  testWidgets('failures are explained and the form stays', (tester) async {
    final callable = FakeCallable()
      ..script('submitPartnerApplication', [
        FirebaseFunctionsException(code: 'already-exists', message: ''),
        FirebaseFunctionsException(code: 'invalid-argument', message: ''),
        FirebaseFunctionsException(code: 'not-found', message: ''),
      ]);
    await pumpPhase8(tester, initialPath: _path, callable: callable);
    await _fillValid(tester);
    for (final message in [_en.partnerAlreadyApplied, _en.partnerInvalid, _en.partnerUnavailable]) {
      await tapKey(tester, 'partner-submit');
      expect(find.text(message), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('partner-form')), findsOneWidget);
  });

  testWidgets('guests fill the form but sign in to send it', (tester) async {
    final h = await pumpPhase8(tester, initialPath: _path, guest: true);
    await _fillValid(tester);
    await enterIn(tester, 'partner-owner-name', 'Sara Ahmed');
    await enterIn(tester, 'partner-phone', '7501234567');
    await tapKey(tester, 'partner-city');
    await tester.tap(find.byKey(const ValueKey('city-erbil')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'partner-submit');
    expect(find.text(_en.signInToContinue), findsOneWidget);
    expect(h.callable.calls, isEmpty);
  });

  group('status card instead of the form', () {
    testWidgets('pending review', (tester) async {
      final db = FakeFirebaseFirestore();
      await _store(db, 'pendingApproval');
      await pumpPhase8(tester, initialPath: _path, firestore: db);
      expect(find.byKey(const ValueKey('partner-status-pending')), findsOneWidget);
      expect(find.text(_en.partnerPendingBody('Wood & Words')), findsOneWidget);
      expect(find.byKey(const ValueKey('partner-form')), findsNothing);
    });

    testWidgets('live → opens the dashboard', (tester) async {
      final db = FakeFirebaseFirestore();
      await _store(db, 'active');
      final h = await pumpPhase8(tester, initialPath: _path, firestore: db);
      expect(find.byKey(const ValueKey('partner-status-active')), findsOneWidget);
      expect(find.text(partnerDashboardUrl), findsOneWidget);
      await tapKey(tester, 'partner-open-dashboard');
      expect(h.openedLinks.single.toString(), partnerDashboardUrl);
    });

    testWidgets('suspended → contact support', (tester) async {
      final db = FakeFirebaseFirestore();
      await _store(db, 'suspended');
      final h = await pumpPhase8(tester, initialPath: _path, firestore: db);
      expect(find.byKey(const ValueKey('partner-status-suspended')), findsOneWidget);
      await tapKey(tester, 'partner-contact-support');
      expect(h.location, '/contact-us');
    });
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await pumpPhase8(tester, initialPath: _path, locale: locale, themeMode: mode);
        await tapKey(tester, 'partner-submit');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320 px, 1.3× text (form + active card)', (tester) async {
      await pumpPhase8(tester,
          initialPath: _path, profile: null, locale: 'ckb', size: const Size(320, 3200), textScale: 1.3);
      await tapKey(tester, 'partner-submit');
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 px, 1.3× text, active store', (tester) async {
      final db = FakeFirebaseFirestore();
      await _store(db, 'active');
      await pumpPhase8(tester,
          initialPath: _path, firestore: db, locale: 'ar', size: const Size(320, 1600), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });
}
