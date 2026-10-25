import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/banner_model.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/user_model.dart';

void main() {
  group('LocalizedText', () {
    test('falls back to English when a translation is missing or empty', () {
      final t = LocalizedText.fromMap({'title': 'Mugs', 'titleAr': '', 'titleKu': 'کوپ'}, 'title');
      expect(t.resolve('en'), 'Mugs');
      expect(t.resolve('ar'), 'Mugs');
      expect(t.resolve('ckb'), 'کوپ');
      expect(t.resolve('fr'), 'Mugs');
    });

    test('toMap omits missing translations', () {
      expect(const LocalizedText('Mugs').toMap('title'), {'title': 'Mugs'});
    });
  });

  group('CategoryModel', () {
    final base = {'title': 'Christmas', 'type': 'occasion', 'sortOrder': 3};

    test('parses type and defaults', () {
      final c = CategoryModel.fromMap('christmas', base);
      expect(c.type, CategoryType.occasion);
      expect(c.isActive, isTrue);
    });

    test('seasonal window controls visibility', () {
      final c = CategoryModel.fromMap('christmas', {
        ...base,
        'isSeasonal': true,
        'activeFrom': Timestamp.fromDate(DateTime(2026, 12, 1)),
        'activeTo': Timestamp.fromDate(DateTime(2026, 12, 31)),
      });
      expect(c.isVisibleAt(DateTime(2026, 11, 30)), isFalse);
      expect(c.isVisibleAt(DateTime(2026, 12, 20)), isTrue);
      expect(c.isVisibleAt(DateTime(2027, 1, 2)), isFalse);
    });

    test('coming soon fields default to available, no note (SRS §6.3)', () {
      final c = CategoryModel.fromMap('christmas', base);
      expect(c.comingSoon, isFalse);
      expect(c.comingSoonNote.isEmpty, isTrue);
      expect(c.comingSoonSince, isNull);
      expect(c.status, CategoryStatus.available);
      final map = c.toMap();
      expect(map['comingSoon'], isFalse);
      expect(map.keys.where((k) => k.startsWith('comingSoonNote')), isEmpty, reason: 'no note keys without a note');
    });

    test('coming soon fields parse tolerantly and round-trip', () {
      final c = CategoryModel.fromMap('easter', {
        ...base,
        'comingSoon': true,
        'comingSoonNote': 'Arriving before Easter',
        'comingSoonNoteAr': 'تصل قبل عيد الفصح',
        'comingSoonNoteKu': '',
        'comingSoonSince': Timestamp.fromDate(DateTime(2026, 10, 20)),
      });
      expect(c.comingSoon, isTrue);
      expect(c.status, CategoryStatus.comingSoon);
      expect(c.comingSoonNote, const LocalizedText('Arriving before Easter', ar: 'تصل قبل عيد الفصح'));
      expect(c.comingSoonSince, DateTime(2026, 10, 20));
      final again = CategoryModel.fromMap('easter', c.toMap());
      expect(again.comingSoon, isTrue);
      expect(again.comingSoonNote, c.comingSoonNote);
      expect(again.comingSoonSince, c.comingSoonSince);

      // Wrong types never crash: a string flag is not "true", a number is not a note.
      final odd = CategoryModel.fromMap('x', {...base, 'comingSoon': 'yes', 'comingSoonNote': 42, 'comingSoonSince': 'soon'});
      expect(odd.comingSoon, isFalse);
      expect(odd.comingSoonNote.isEmpty, isTrue);
      expect(odd.comingSoonSince, isNull);
      expect(CategoryModel.fromMap('h', {...base, 'isActive': false, 'comingSoon': true}).status, CategoryStatus.hidden);
    });

    test('a subcategory of a coming-soon parent is coming soon; cycles end', () {
      const parent = CategoryModel(id: 'easter', title: LocalizedText('Easter'), comingSoon: true);
      const child = CategoryModel(id: 'eggs', title: LocalizedText('Eggs'), parentId: 'easter');
      const grandchild = CategoryModel(id: 'gold-eggs', title: LocalizedText('Gold eggs'), parentId: 'eggs');
      const other = CategoryModel(id: 'mugs', title: LocalizedText('Mugs'), parentId: 'missing');
      final byId = {for (final c in [parent, child, grandchild, other]) c.id: c};
      expect(child.comingSoonSource(byId)?.id, 'easter');
      expect(grandchild.isComingSoonWithin(byId), isTrue);
      expect(parent.comingSoonSource(byId)?.id, 'easter');
      expect(other.isComingSoonWithin(byId), isFalse);

      const a = CategoryModel(id: 'a', title: LocalizedText('A'), parentId: 'b');
      const b = CategoryModel(id: 'b', title: LocalizedText('B'), parentId: 'a');
      expect(a.isComingSoonWithin({'a': a, 'b': b}), isFalse);
    });
  });

  group('BannerModel', () {
    test('reads the nested action and picks artwork per language', () {
      final b = BannerModel.fromMap('b1', {
        'imageUrl': 'en.png',
        'imageUrlAr': 'ar.png',
        'placement': 'homeMid1',
        'action': {'type': 'route', 'value': '/special-requests'},
      });
      expect(b.placement, BannerPlacement.homeMid1);
      expect(b.actionType, BannerActionType.route);
      expect(b.actionValue, '/special-requests');
      expect(b.imageFor('ar'), 'ar.png');
      expect(b.imageFor('ckb'), 'en.png');
    });

    test('schedule', () {
      final b = BannerModel.fromMap('b1', {
        'imageUrl': 'x',
        'placement': 'homeTop',
        'action': {'type': 'url', 'value': 'https://goldengift.app'},
        'startAt': DateTime(2026, 1, 1),
        'endAt': DateTime(2026, 1, 31),
      });
      expect(b.isLiveAt(DateTime(2026, 1, 15)), isTrue);
      expect(b.isLiveAt(DateTime(2026, 2, 1)), isFalse);
    });
  });

  group('settings', () {
    test('general settings read the nested minAppVersion', () {
      final g = GeneralSettings.fromMap({
        'sameDayCutoff': '15:30',
        'minAppVersion': {'ios': '1.2.0', 'android': '1.1.0'},
      });
      expect(g.sameDayCutoff, '15:30');
      expect(g.minAppVersionIos, '1.2.0');
      expect(g.minAppVersionAndroid, '1.1.0');
    });

    test('cities document', () {
      final cities = CityModel.listFromDoc({
        'items': [
          {'id': 'erbil', 'name': 'Erbil', 'nameKu': 'هەولێر', 'deliveryFee': 3000},
          {'id': 'duhok', 'name': 'Duhok', 'deliveryFee': 4000, 'isActive': false},
        ],
      });
      expect(cities.map((c) => c.id), ['erbil', 'duhok']);
      expect(cities.first.name.resolve('ckb'), 'هەولێر');
      expect(cities.last.isActive, isFalse);
    });

    test('payments: online gateways off by default', () {
      expect(PaymentSettings.fromMap({}).anyOnlineGateway, isFalse);
      expect(PaymentSettings.fromMap({}).cashOnDelivery, isTrue);
    });
  });

  group('UserModel', () {
    test('profile completion needs name, email, birthday, gender and city', () {
      final partial = UserModel.fromMap('u1', {'name': 'Sara Ahmed', 'phone': '7501234567'});
      expect(partial.firstName, 'Sara');
      expect(partial.computedProfileCompleted, isFalse);
      final full = UserModel.fromMap('u1', {
        'name': 'Sara Ahmed',
        'phone': '7501234567',
        'email': 'sara@example.com',
        'birthday': Timestamp.fromDate(DateTime(1999, 4, 2)),
        'gender': 'female',
        'city': 'erbil',
      });
      expect(full.computedProfileCompleted, isTrue);
    });

    test('profile map never contains server-owned fields (SRS AUTH-3, §6.17)', () {
      final map = UserModel.fromMap('u1', {
        'name': 'Sara',
        'phone': '7501234567',
        'role': 'admin',
        'referralCode': 'ABC123',
        'referredBy': 'u0',
        'isBlocked': true,
        'storeIds': ['s1'],
        'totalSpent': 99,
      }).toProfileMap();
      for (final key in ['role', 'referralCode', 'referredBy', 'isBlocked', 'storeIds', 'totalOrders', 'totalSpent']) {
        expect(map.containsKey(key), isFalse, reason: key);
      }
    });
  });
}
