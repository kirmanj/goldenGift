import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift_admin/features/settings/cities_settings_tab.dart' show citiesDoc;
import 'package:golden_gift_admin/features/settings/settings_data.dart';

import '../categories/admin_test_harness.dart';

void main() {
  late FakeFirebaseFirestore db;
  late SettingsAdminRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = SettingsAdminRepository(db, adminUid: testAdmin.uid);
  });

  Future<Map<String, dynamic>> doc(String id) async => (await db.doc('app_settings/$id').get()).data()!;

  group('save', () {
    test('writes the doc and a settings.{doc}.update entry with before/after', () async {
      const first = GeneralSettings(supportPhone: '+964 750 000 0000', minOrder: 10000);
      await repo.save('general', before: null, after: first.toMap());

      expect(GeneralSettings.fromMap(await doc('general')).supportPhone, '+964 750 000 0000');
      var audit = await auditEntries(db);
      expect(audit, hasLength(1));
      expect(audit.single['action'], 'settings.general.update');
      expect(audit.single['target'], 'app_settings/general');
      expect(audit.single['adminUid'], 'admin-1');
      expect(audit.single['before'], isNull);
      expect(audit.single['after'], first.toMap());

      final second = first.copyWith(maintenanceMode: true, minAppVersionIos: '1.2.0');
      await repo.save('general', before: first.toMap(), after: second.toMap());
      audit = await auditEntries(db);
      expect(audit, hasLength(2));
      final last = audit.firstWhere((e) => (e['after'] as Map)['maintenanceMode'] == true);
      expect((last['before'] as Map)['maintenanceMode'], false);
      expect((last['before'] as Map)['minAppVersion'], {'ios': '1.0.0', 'android': '1.0.0'});
      expect((last['after'] as Map)['minAppVersion'], {'ios': '1.2.0', 'android': '1.0.0'});
      expect(GeneralSettings.fromMap(await doc('general')).maintenanceMode, isTrue);
    });

    test('keeps delivery slots (not edited here) and fields the model does not know', () async {
      await db.doc('app_settings/general').set({
        'supportPhone': '+964 750 111 1111',
        'deliverySlots': [
          {'id': 'morning', 'label': 'Morning', 'from': '10:00', 'to': '14:00'},
        ],
        'legacyBannerText': 'keep me',
      });
      final before = GeneralSettings.fromMap(await doc('general'));
      await repo.save('general', before: before.toMap(), after: before.copyWith(sameDayCutoff: '15:30').toMap());
      final saved = await doc('general');
      expect(saved['sameDayCutoff'], '15:30');
      expect(saved['supportPhone'], '+964 750 111 1111');
      expect(saved['deliverySlots'], [
        {'id': 'morning', 'label': 'Morning', 'from': '10:00', 'to': '14:00'},
      ]);
      expect(saved['legacyBannerText'], 'keep me');
    });

    test('requires a signed-in admin', () async {
      final anonymous = SettingsAdminRepository(db, adminUid: '');
      await expectLater(anonymous.save('general', before: null, after: const {}), throwsStateError);
      expect(await auditEntries(db), isEmpty);
    });
  });

  group('general validation', () {
    test('minimum versions must be x.y.z', () {
      for (final ok in ['1.0.0', '2.10.3', '0.0.1']) {
        expect(validateAppVersion(ok), isNull, reason: ok);
      }
      for (final bad in ['', '1.2', '1.2.3.4', 'v1.2.3', '1.2.x', '1.2.3+4', ' ']) {
        expect(validateAppVersion(bad), isNotNull, reason: bad);
      }
    });

    test('cut-off must be HH:mm (24 h)', () {
      for (final ok in ['00:00', '09:30', '14:00', '23:59']) {
        expect(validateCutoff(ok), isNull, reason: ok);
      }
      for (final bad in ['', '9:30', '24:00', '14:60', '1400', '2pm', '14:0']) {
        expect(validateCutoff(bad), isNotNull, reason: bad);
      }
    });

    test('store links: https or empty; contact fields', () {
      expect(validateStoreUrl(''), isNull);
      expect(validateStoreUrl('https://apps.apple.com/app/id123'), isNull);
      expect(validateStoreUrl('http://play.google.com'), isNotNull);
      expect(validateStoreUrl('play.google.com'), isNotNull);
      expect(validateContactPhone(''), isNull);
      expect(validateContactPhone('+964 750 123 4567'), isNull);
      expect(validateContactPhone('call us'), isNotNull);
      expect(validateContactEmail('help@goldengift.app'), isNull);
      expect(validateContactEmail('help@'), isNotNull);
    });

    test('whole document', () {
      expect(validateGeneralSettings(const GeneralSettings()), isEmpty);
      final errors = validateGeneralSettings(
          const GeneralSettings(sameDayCutoff: '25:00', minAppVersionAndroid: '1.0', storeUrlIos: 'http://x.com'));
      expect(errors, hasLength(3));
      expect(errors.join('\n'), allOf(contains('cut-off'), contains('Android'), contains('App Store')));
    });
  });

  group('cities', () {
    Future<List<CityModel>> read() async => CityModel.listFromDoc(await doc('cities'));
    List<Map<String, dynamic>> maps(List<CityModel> cities) => [for (final c in cities) c.toMap()];

    test('add / rename / remove round-trip through CityModel.listFromDoc', () async {
      final initial = [
        const CityModel(id: 'erbil', name: LocalizedText('Erbil', ar: 'أربيل', ku: 'هەولێر'), deliveryFee: 3000),
        const CityModel(id: 'duhok', name: LocalizedText('Duhok'), deliveryFee: 4000),
      ];
      await repo.save('cities', before: null, after: citiesDoc(initial));
      expect(maps(await read()), maps(initial));

      // Add
      final added = [...await read(), const CityModel(id: 'basra', name: LocalizedText('Basra'), deliveryFee: 7000, isActive: false)];
      await repo.save('cities', before: citiesDoc(await read()), after: citiesDoc(added));
      expect((await read()).map((c) => c.id), ['erbil', 'duhok', 'basra']);
      expect((await read()).last.isActive, isFalse);

      // Rename (the id stays)
      final current = await read();
      final renamed = [...current]..[1] = current[1].copyWith(name: const LocalizedText('Dohuk', ar: 'دهوك'));
      await repo.save('cities', before: citiesDoc(current), after: citiesDoc(renamed));
      final afterRename = await read();
      expect(afterRename[1].id, 'duhok');
      expect(afterRename[1].name, const LocalizedText('Dohuk', ar: 'دهوك'));
      expect(afterRename[1].deliveryFee, 4000);

      // Remove
      final removed = [...afterRename]..removeAt(0);
      await repo.save('cities', before: citiesDoc(afterRename), after: citiesDoc(removed));
      expect((await read()).map((c) => c.id), ['duhok', 'basra']);

      final audit = await auditEntries(db);
      expect(audit, hasLength(4));
      expect(audit.map((e) => e['action']).toSet(), {'settings.cities.update'});
      final removal = audit.firstWhere((e) => ((e['after'] as Map)['items'] as List).length == 2 && e['before'] != null &&
          ((e['before'] as Map)['items'] as List).length == 3);
      expect(((removal['before'] as Map)['items'] as List).first, {
        'id': 'erbil',
        'name': 'Erbil',
        'nameAr': 'أربيل',
        'nameKu': 'هەولێر',
        'deliveryFee': 3000,
        'isActive': true,
      });
    });

    test('validation: slug ids, unique, English name, one active city', () {
      const ok = [CityModel(id: 'erbil', name: LocalizedText('Erbil'))];
      expect(validateCities(ok), isEmpty);
      expect(validateCities(const [CityModel(id: 'Erbil City', name: LocalizedText('Erbil'))]), [contains('lowercase')]);
      expect(
          validateCities(const [
            CityModel(id: 'erbil', name: LocalizedText('Erbil')),
            CityModel(id: 'erbil', name: LocalizedText('Hewlêr')),
          ]),
          [contains('more than once')]);
      expect(validateCities(const [CityModel(id: 'x', name: LocalizedText(''))]), [contains('English name')]);
      expect(validateCities(const [CityModel(id: 'erbil', name: LocalizedText('Erbil'), isActive: false)]),
          [contains('At least one city')]);
      expect(validateCities(const []), [contains('At least one city')]);
    });

    test('default cities use slug ids', () {
      expect(defaultCities(const ['Erbil', 'Sulaymaniyah']).map((c) => c.id), ['erbil', 'sulaymaniyah']);
    });
  });

  test('payments, referral and search validation', () {
    expect(validatePaymentSettings(const PaymentSettings()), isEmpty);
    expect(validatePaymentSettings(const PaymentSettings(cashOnDelivery: false, wallet: false)), isNotEmpty);
    expect(validatePaymentSettings(const PaymentSettings(cashOnDelivery: false, wallet: false, card: true)), isEmpty);

    expect(validateReferralSettings(const ReferralSettings(joinBonus: 5000, orderBonus: 5000)), isEmpty);
    expect(validateReferralSettings(const ReferralSettings(joinBonus: -1)), isNotEmpty);

    expect(validateSearchSettings(const SearchSettings()), isEmpty);
    expect(validateSearchSettings(const SearchSettings(algoliaAppId: 'APP', algoliaSearchKey: 'key')), isEmpty);
    expect(validateSearchSettings(const SearchSettings(algoliaAppId: 'APP')), [contains('both')]);
    expect(validateSearchSettings(const SearchSettings(indexName: ' ')), [contains('index name')]);
  });
}
