import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/banner_model.dart';
import 'package:golden_gift_admin/features/banners/banners_data.dart';
import 'package:golden_gift_admin/features/categories/categories_data.dart' show moveItem;

import '../categories/admin_test_harness.dart';

BannerModel banner(
  String id, {
  String imageUrl = 'https://cdn.goldengift.test/b.jpg',
  String? imageUrlAr,
  BannerPlacement placement = BannerPlacement.homeTop,
  BannerActionType type = BannerActionType.route,
  String value = '/special-requests',
  int sort = 0,
  bool isActive = true,
  DateTime? startAt,
  DateTime? endAt,
}) =>
    BannerModel(
      id: id,
      imageUrl: imageUrl,
      imageUrlAr: imageUrlAr,
      placement: placement,
      actionType: type,
      actionValue: value,
      sortOrder: sort,
      isActive: isActive,
      startAt: startAt,
      endAt: endAt,
    );

void main() {
  late FakeFirebaseFirestore db;
  late BannerAdminRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = BannerAdminRepository(db, adminUid: testAdmin.uid);
  });

  Future<List<BannerModel>> load() async =>
      sortBanners([for (final d in (await db.collection('banners').get()).docs) BannerModel.fromMap(d.id, d.data())]);

  Future<void> seed(List<BannerModel> banners) async {
    for (final b in banners) {
      await db.doc('banners/${b.id}').set(b.toMap());
    }
  }

  group('validation', () {
    test('a valid banner passes', () {
      expect(validateBanner(banner('a')), isEmpty);
      expect(validateBanner(banner('a', type: BannerActionType.url, value: 'https://goldengift.app/eid')), isEmpty);
      expect(validateBanner(banner('a', type: BannerActionType.category, value: 'mugs'), categoryIds: ['mugs']), isEmpty);
      expect(validateBanner(banner('a', type: BannerActionType.product, value: 'p1')), isEmpty);
    });

    test('the English artwork is required', () {
      expect(validateBanner(banner('a', imageUrl: ''))['imageUrl'], 'The English artwork is required');
      expect(validateBanner(banner('a', imageUrl: 'not a url')), contains('imageUrl'));
      expect(validateBanner(banner('a', imageUrlAr: 'nope')), contains('imageUrlAr'));
    });

    test('URL actions must be https', () {
      for (final bad in ['http://goldengift.app', 'goldengift.app', 'https://', 'ftp://x.com', 'https://bad host.com']) {
        expect(validateBanner(banner('a', type: BannerActionType.url, value: bad))['action'],
            'Links must be full https:// URLs',
            reason: bad);
      }
      expect(isHttpsUrl('https://www.instagram.com/goldengift?x=1'), isTrue);
    });

    test('route, category and product targets', () {
      expect(validateBanner(banner('a', value: '/admin'))['action'], contains('app screen'));
      expect(validateBanner(banner('a', type: BannerActionType.category, value: ''))['action'], contains('category'));
      expect(validateBanner(banner('a', type: BannerActionType.category, value: 'gone'), categoryIds: ['mugs'])['action'],
          contains('does not exist'));
      expect(validateBanner(banner('a', type: BannerActionType.product, value: ' '))['action'], contains('product id'));
    });

    test('the end must be after the start', () {
      final start = DateTime(2026, 11, 1, 9);
      expect(validateBanner(banner('a', startAt: start, endAt: start))['schedule'], 'The end must be after the start');
      expect(validateBanner(banner('a', startAt: start, endAt: DateTime(2026, 10, 1)))['schedule'], isNotNull);
      expect(validateBanner(banner('a', startAt: start, endAt: DateTime(2026, 11, 30))), isEmpty);
      expect(validateBanner(banner('a', endAt: DateTime(2026, 11, 30))), isEmpty);
    });

    test('route options are the app routes', () {
      expect(bannerRouteOptions.map((r) => r.$1), [
        '/special-requests',
        '/become-partner',
        '/gift-cards',
        '/categories',
        '/promo-codes',
        '/invite',
        '/ai-gift-search',
        '/secret-santa',
      ]);
    });
  });

  test('status: live / scheduled / expired / inactive', () {
    final now = DateTime(2026, 10, 21, 12);
    expect(bannerStatus(banner('a'), now), BannerStatus.live);
    expect(bannerStatus(banner('a', startAt: DateTime(2026, 10, 22)), now), BannerStatus.scheduled);
    expect(bannerStatus(banner('a', endAt: DateTime(2026, 10, 20)), now), BannerStatus.expired);
    expect(bannerStatus(banner('a', isActive: false), now), BannerStatus.inactive);
    expect(bannerStatus(banner('a', startAt: DateTime(2026, 10, 1), endAt: DateTime(2026, 11, 1)), now), BannerStatus.live);
  });

  group('writes', () {
    test('create writes the banner and its audit entry, at the end of its placement', () async {
      await seed([banner('top1', sort: 0), banner('top2', sort: 3)]);
      final created = banner('new', imageUrlAr: 'https://cdn.goldengift.test/b_ar.jpg', type: BannerActionType.url,
          value: 'https://goldengift.app/eid', startAt: DateTime(2026, 11, 1), endAt: DateTime(2026, 11, 30));
      await repo.create(created, existing: await load());

      final doc = (await db.doc('banners/new').get()).data()!;
      expect(doc['sortOrder'], 4);
      expect(doc['placement'], 'homeTop');
      expect(doc['action'], {'type': 'url', 'value': 'https://goldengift.app/eid'});
      expect(doc['imageUrlAr'], 'https://cdn.goldengift.test/b_ar.jpg');

      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'banner.create');
      expect(audit['target'], 'banners/new');
      expect(audit['adminUid'], 'admin-1');
      expect(audit['before'], isNull);
      expect((audit['after'] as Map)['action'], {'type': 'url', 'value': 'https://goldengift.app/eid'});

      await repo.create(banner('mid', placement: BannerPlacement.homeMid1), existing: await load());
      expect((await db.doc('banners/mid').get()).data()!['sortOrder'], 0, reason: 'first in its own placement');
    });

    test('an invalid banner writes nothing', () async {
      await expectLater(
        repo.create(banner('bad', imageUrl: '', type: BannerActionType.url, value: 'http://x.com'), existing: const []),
        throwsA(isA<BannerValidationException>()
            .having((e) => e.errors.keys, 'fields', containsAll(['imageUrl', 'action']))),
      );
      expect((await db.doc('banners/bad').get()).exists, isFalse);
      expect(await auditEntries(db), isEmpty);
    });

    test('update: keeps position, moves to the end of a new placement, deletes cleared artwork', () async {
      await seed([
        banner('a', sort: 0, imageUrlAr: 'https://cdn.goldengift.test/a_ar.jpg'),
        banner('m1', placement: BannerPlacement.homeBottom, sort: 0),
        banner('m2', placement: BannerPlacement.homeBottom, sort: 1),
      ]);
      final before = (await load()).firstWhere((b) => b.id == 'a');

      await repo.update(before, banner('a', sort: 0, isActive: false, imageUrlAr: 'https://cdn.goldengift.test/a_ar.jpg'),
          existing: await load());
      expect((await db.doc('banners/a').get()).data()!['isActive'], false);
      expect((await db.doc('banners/a').get()).data()!['sortOrder'], 0);

      final current = (await load()).firstWhere((b) => b.id == 'a');
      await repo.update(current, banner('a', placement: BannerPlacement.homeBottom, isActive: false), existing: await load());
      final doc = (await db.doc('banners/a').get()).data()!;
      expect(doc['placement'], 'homeBottom');
      expect(doc['sortOrder'], 2);
      expect(doc.containsKey('imageUrlAr'), isFalse);

      final audit = await auditEntries(db);
      expect(audit, hasLength(2));
      final last = audit.firstWhere((e) => (e['after'] as Map)['placement'] == 'homeBottom');
      expect(last['action'], 'banner.update');
      expect((last['before'] as Map)['placement'], 'homeTop');
      expect((last['before'] as Map)['imageUrlAr'], 'https://cdn.goldengift.test/a_ar.jpg');
      expect((last['after'] as Map)['sortOrder'], 2);
    });

    test('reorder within a placement: one batch, one banner.reorder entry', () async {
      await seed([banner('a', sort: 0), banner('b', sort: 1), banner('c', sort: 2), banner('x', placement: BannerPlacement.homeMid2)]);
      final top = (await load()).where((b) => b.placement == BannerPlacement.homeTop).toList();
      final moved = moveItem(top, 2, 0); // c up to first
      expect(await repo.reorder(BannerPlacement.homeTop, moved), 3);

      final order = (await load()).where((b) => b.placement == BannerPlacement.homeTop).map((b) => b.id);
      expect(order, ['c', 'a', 'b']);
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'banner.reorder');
      expect(audit['before'], {'placement': 'homeTop', 'sortOrder': {'c': 2, 'a': 0, 'b': 1}});
      expect(audit['after'], {'placement': 'homeTop', 'sortOrder': {'c': 0, 'a': 1, 'b': 2}});
      expect((await db.doc('banners/x').get()).data()!['sortOrder'], 0);
    });

    test('delete writes an audit snapshot', () async {
      await seed([banner('a')]);
      await repo.delete((await load()).single);
      expect((await db.doc('banners/a').get()).exists, isFalse);
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'banner.delete');
      expect((audit['before'] as Map)['imageUrl'], 'https://cdn.goldengift.test/b.jpg');
    });
  });
}
