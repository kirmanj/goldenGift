import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift_admin/features/settings/settings_screen.dart';

import '../categories/admin_test_harness.dart';

const tabs = ['General', 'Cities & fees', 'Payments', 'Referral', 'Search'];

Future<FakeFirebaseFirestore> seeded({bool withCities = true}) async {
  final db = FakeFirebaseFirestore();
  await db.doc('app_settings/general').set(const GeneralSettings(
        supportPhone: '+964 750 123 4567',
        email: 'help@goldengift.app',
        minOrder: 10000,
      ).toMap());
  if (withCities) {
    await db.doc('app_settings/cities').set({
      'items': [
        const CityModel(id: 'erbil', name: LocalizedText('Erbil', ar: 'أربيل', ku: 'هەولێر'), deliveryFee: 3000).toMap(),
        const CityModel(id: 'duhok', name: LocalizedText('Duhok'), deliveryFee: 4000, isActive: false).toMap(),
      ],
    });
  }
  await db.doc('app_settings/payments').set(const PaymentSettings().toMap());
  await db.doc('app_settings/referral').set(const ReferralSettings(joinBonus: 5000, orderBonus: 5000).toMap());
  return db;
}

/// Tab switches animate; give them time.
Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> enterField(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await settle(tester);
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('every tab renders in ${mode.name} at 800 px without overflow', (tester) async {
      await pumpAdminScreen(tester, const SettingsScreen(), db: await seeded(), mode: mode);
      expect(find.text('Contact & support'), findsOneWidget);
      for (final tab in tabs) {
        await openTab(tester, tab);
        expect(tester.takeException(), isNull, reason: tab);
      }
      expect(find.text('Algolia'), findsOneWidget);
      expect(find.text('App uses keyword fallback'), findsOneWidget);
    });

    testWidgets('every tab renders in ${mode.name} at 1280 px with no overflow in the page', (tester) async {
      final db = await seeded(withCities: false);
      final errors = await errorsOutsideCoreNav(() async {
        await pumpAdminScreen(tester, const SettingsScreen(), db: db, mode: mode, size: const Size(1280, 900));
        for (final tab in tabs) {
          await openTab(tester, tab);
        }
      });
      expect(errors, isEmpty);
    });
  }

  testWidgets('maintenance mode: turning it on asks first, then saves with an audit entry', (tester) async {
    final db = await seeded();
    await pumpAdminScreen(tester, const SettingsScreen(), db: db);
    expect(find.text('All changes saved'), findsOneWidget);
    final maintenance = find.byKey(const ValueKey('maintenance-switch'));

    await tapVisible(tester, maintenance);
    expect(find.text('Turn on maintenance mode?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(tester.widget<SwitchListTile>(maintenance).value, isFalse);
    expect(find.text('All changes saved'), findsOneWidget);

    await tapVisible(tester, maintenance);
    await tester.tap(find.widgetWithText(FilledButton, 'Turn on'));
    await settle(tester);
    expect(tester.widget<SwitchListTile>(maintenance).value, isTrue);
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(find.byKey(const ValueKey('dirty-general')), findsOneWidget);
    expect(await auditEntries(db), isEmpty, reason: 'nothing is written before Save');

    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(GeneralSettings.fromMap((await db.doc('app_settings/general').get()).data()!).maintenanceMode, isTrue);
    final audit = (await auditEntries(db)).single;
    expect(audit['action'], 'settings.general.update');
    expect((audit['before'] as Map)['maintenanceMode'], false);
    expect((audit['after'] as Map)['maintenanceMode'], true);
    expect((audit['after'] as Map)['supportPhone'], '+964 750 123 4567');
    expect(find.text('All changes saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('dirty-general')), findsNothing);
  });

  testWidgets('turning maintenance off needs no confirmation', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('app_settings/general').set(const GeneralSettings(maintenanceMode: true).toMap());
    await pumpAdminScreen(tester, const SettingsScreen(), db: db);
    await tapVisible(tester, find.byKey(const ValueKey('maintenance-switch')));
    expect(find.text('Turn on maintenance mode?'), findsNothing);
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('invalid version and cut-off block the save', (tester) async {
    final db = await seeded();
    await pumpAdminScreen(tester, const SettingsScreen(), db: db);
    await enterField(tester, find.byKey(const ValueKey('min-version-ios')), '1.2');
    await enterField(tester, find.byKey(const ValueKey('cutoff-field')), '25:00');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Use x.y.z, e.g. 1.2.0'), findsOneWidget);
    expect(find.text('Use 24-hour HH:mm, e.g. 14:00'), findsOneWidget);
    expect(await auditEntries(db), isEmpty);

    await tester.tap(find.text('Discard'));
    await settle(tester);
    expect(find.text('All changes saved'), findsOneWidget);
    final ios = tester.widget<EditableText>(
        find.descendant(of: find.byKey(const ValueKey('min-version-ios')), matching: find.byType(EditableText)));
    expect(ios.controller.text, '1.0.0', reason: 'discard reloads the saved values');
  });

  testWidgets('cities: add, save, saved ids lock, remove with confirmation', (tester) async {
    final db = await seeded();
    await pumpAdminScreen(tester, const SettingsScreen(), db: db);
    await openTab(tester, 'Cities & fees');

    await tapVisible(tester, find.text('Add city'));
    await enterField(tester, find.widgetWithText(TextFormField, 'Name · English *').last, 'Basra');
    await enterField(tester, find.widgetWithText(TextFormField, 'Delivery fee (IQD) *').last, '7000');
    expect(find.byKey(const ValueKey('dirty-cities')), findsOneWidget);

    await tester.tap(find.text('Save'));
    await settle(tester);
    var cities = CityModel.listFromDoc((await db.doc('app_settings/cities').get()).data()!);
    expect(cities.map((c) => '${c.id}:${c.deliveryFee}'), ['erbil:3000', 'duhok:4000', 'basra:7000']);
    expect((await auditEntries(db)).single['action'], 'settings.cities.update');

    final idFields = tester.widgetList<TextFormField>(find.widgetWithText(TextFormField, 'Id *')).toList();
    expect(idFields.map((f) => f.enabled), [false, false, false], reason: 'saved ids are immutable');

    await tapVisible(tester, find.byTooltip('Remove city').first);
    expect(find.text('Remove "Erbil"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);
    cities = CityModel.listFromDoc((await db.doc('app_settings/cities').get()).data()!);
    expect(cities.map((c) => c.id), ['duhok', 'basra']);
    expect(await auditEntries(db), hasLength(2));
  });

  testWidgets('cities: an empty list offers the default cities', (tester) async {
    final db = await seeded(withCities: false);
    await pumpAdminScreen(tester, const SettingsScreen(), db: db);
    await openTab(tester, 'Cities & fees');
    expect(find.text('Not saved yet — the app is using its defaults'), findsOneWidget);
    await tapVisible(tester, find.text('Add the 7 default cities'));
    await tester.tap(find.text('Save'));
    await settle(tester);
    final cities = CityModel.listFromDoc((await db.doc('app_settings/cities').get()).data()!);
    expect(cities.first.id, 'erbil');
    expect(cities, hasLength(7));
    expect((await auditEntries(db)).single['before'], isNull);
  });
}
