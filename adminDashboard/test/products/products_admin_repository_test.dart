import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/products/data/product_derived.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift_admin/features/products/data/products_admin_repository.dart';
import 'package:golden_gift_admin/features/products/domain/product_draft.dart';

import 'products_test_helpers.dart';

/// Save logic of the products module (SRS §6.4, §9): one batch per change
/// with its audit entry, derived fields always written, counters kept.
void main() {
  late RecordingFirestore db;
  late ProductsAdminRepository repo;

  setUp(() {
    db = RecordingFirestore();
    repo = ProductsAdminRepository(db);
  });

  ProductDraft frameDraft() => ProductDraft(
        title: const LocalizedText('Wooden Photo Frame', ar: 'إطار صور خشبي'),
        description: const LocalizedText('Solid walnut.'),
        storeId: 'golden-gift-home',
        categoryIds: ['frames', 'wedding'],
        price: 35000,
        compareAtPrice: 42000,
        availableCities: ['erbil', 'duhok'],
        tags: ['Walnut'],
      );

  ProductModel simple(String id, {String? title, List<String> categories = const [], bool active = true}) =>
      ProductModel(
        id: id,
        title: LocalizedText(title ?? id),
        storeId: 'golden-gift-home',
        price: 10000,
        categoryIds: categories,
        isActive: active,
      );

  group('create', () {
    test('writes the product + derived fields + timestamps and a product.create audit entry in ONE batch', () async {
      final draft = frameDraft();
      final id = await repo.newProductId(draft.title.en);
      expect(id, 'wooden-photo-frame');
      await repo.save(draft.toModel(id), isNew: true, adminUid: 'admin-1');

      final stored = (await db.doc('products/$id').get()).data()!;
      final model = ProductModel.fromMap(id, stored);
      ProductDerived.of(model).forEach((key, value) => expect(stored[key], value, reason: key));
      expect(stored['hasDiscount'], isTrue);
      expect(stored['cityKeys'], ['erbil', 'duhok']);
      expect(stored['catCityKeys'], ['frames|erbil', 'frames|duhok', 'wedding|erbil', 'wedding|duhok']);
      expect(stored['searchKeywords'], containsAll(['wooden', 'photo', 'frame', 'walnut']));
      expect(stored['titleAr'], 'إطار صور خشبي');
      expect(stored['currency'], 'IQD');
      expect(stored['salesCount'], 0);
      expect(stored['createdAt'], isA<Timestamp>());
      expect(stored['updatedAt'], isA<Timestamp>());

      expect(db.commits, hasLength(1));
      expect(db.commits.single, ['set products/$id', startsWith('set admin_audit_log/')]);
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'product.create');
      expect(audit['target'], 'products/wooden-photo-frame');
      expect(audit['adminUid'], 'admin-1');
      expect(audit['before'], isNull);
      expect((audit['after'] as Map)['price'], 35000);
      expect((audit['after'] as Map).containsKey('createdAt'), isFalse);
      expect((audit['after'] as Map)['searchKeywords'], stored['searchKeywords']);
    });

    test('ids are the slug of the English title, made unique', () async {
      await seedProduct(db, simple('wooden-photo-frame'), createdAt: DateTime(2026));
      await seedProduct(db, simple('wooden-photo-frame-2'), createdAt: DateTime(2026));
      expect(await repo.newProductId('Wooden Photo Frame'), 'wooden-photo-frame-3');
      expect(await repo.newProductId("Mother's Day Mug!"), 'mothers-day-mug');
      // No latin letters → Firestore auto id.
      final auto = await repo.newProductId('كوب');
      expect(auto, hasLength(20));
    });
  });

  group('update', () {
    Future<ProductDraft> seededDraft() async {
      await db.doc('products/wooden-photo-frame').set({
        ...ProductsAdminRepository.productData(frameDraft().toModel('wooden-photo-frame')),
        'salesCount': 7,
        'viewCount': 99,
        'ratingAvg': 4.5,
        'ratingCount': 2,
        'colorDots': ['#C9A227'], // a field the editor doesn't know
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      db.commits.clear();
      return ProductDraft.fromModel((await repo.load('wooden-photo-frame'))!);
    }

    test('keeps salesCount / viewCount / ratings (even if they moved meanwhile) and unknown fields', () async {
      final draft = await seededDraft();
      expect(draft.salesCount, 7);
      // A sale lands while the admin is editing.
      await db.doc('products/wooden-photo-frame').update({'salesCount': 8});
      db.commits.clear();

      draft
        ..price = 30000
        ..title = const LocalizedText('Wooden Photo Frame'); // Arabic cleared
      await repo.save(draft.toModel(draft.id!), isNew: false, adminUid: 'admin-1');

      final stored = (await db.doc('products/wooden-photo-frame').get()).data()!;
      expect(stored['price'], 30000);
      expect(stored['priceBand'], ProductDerived.of(draft.toModel('x'))['priceBand']);
      expect(stored['salesCount'], 8);
      expect(stored['viewCount'], 99);
      expect(stored['ratingAvg'], 4.5);
      expect(stored['ratingCount'], 2);
      expect(stored['colorDots'], ['#C9A227']);
      expect(stored.containsKey('titleAr'), isFalse, reason: 'a cleared translation is deleted');
      expect((stored['createdAt'] as Timestamp).toDate(), DateTime(2026, 1, 1));
      expect((stored['updatedAt'] as Timestamp).toDate().isAfter(DateTime(2026, 1, 1)), isTrue);

      expect(db.commits, [
        ['update products/wooden-photo-frame', startsWith('set admin_audit_log/')],
      ]);
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'product.update');
      expect(audit['target'], 'products/wooden-photo-frame');
      final before = audit['before'] as Map, after = audit['after'] as Map;
      expect(before['price'], 35000);
      expect(after['price'], 30000);
      expect(after['salesCount'], 8);
      expect(before['titleAr'], 'إطار صور خشبي');
      expect(after.containsKey('titleAr'), isFalse);
      for (final m in [before, after]) {
        expect(m.containsKey('createdAt') || m.containsKey('updatedAt'), isFalse);
      }
    });

    test('gift types: giftFor + forKeys are written on create and recomputed on update', () async {
      final draft = frameDraft()..setGiftFor(GiftAudience.men, true);
      await repo.save(draft.toModel('wooden-photo-frame'), isNew: true, adminUid: 'admin-1');
      var stored = (await db.doc('products/wooden-photo-frame').get()).data()!;
      expect(stored['giftFor'], ['men']);
      expect(stored['forKeys'], ProductDerived.of(draft.toModel('x'))['forKeys']);
      expect(stored['forKeys'], containsAll(['men', 'men|cat:frames', 'men|city:duhok', 'men|cat:wedding|city:erbil']));
      expect(((await auditEntries(db)).single['after'] as Map)['forKeys'], stored['forKeys']);

      final edit = ProductDraft.fromModel((await repo.load('wooden-photo-frame'))!)
        ..setGiftFor(GiftAudience.men, false)
        ..setGiftFor(GiftAudience.companies, true);
      edit.availableCities.clear();
      await repo.save(edit.toModel(edit.id!), isNew: false, adminUid: 'admin-1');
      stored = (await db.doc('products/wooden-photo-frame').get()).data()!;
      expect(stored['giftFor'], ['companies']);
      expect(stored['forKeys'], [
        'companies', 'companies|cat:frames', 'companies|cat:wedding', 'companies|city:all',
        'companies|cat:frames|city:all', 'companies|cat:wedding|city:all',
      ]);
      final update = (await auditEntries(db)).firstWhere((a) => a['action'] == 'product.update');
      expect((update['before'] as Map)['giftFor'], ['men']);
      expect((update['after'] as Map)['giftFor'], ['companies']);
    });

    test('a product deleted meanwhile is not resurrected', () async {
      final draft = await seededDraft();
      await db.doc('products/wooden-photo-frame').delete();
      await expectLater(
        repo.save(draft.toModel(draft.id!), isNew: false, adminUid: 'admin-1'),
        throwsA(isA<ProductNotFoundException>()),
      );
      expect((await db.doc('products/wooden-photo-frame').get()).exists, isFalse);
      expect(await auditEntries(db), isEmpty);
    });
  });

  test('delete removes the doc with a product.delete audit entry in the same batch', () async {
    await seedProduct(db, simple('engraved-pen', title: 'Engraved Pen'), createdAt: DateTime(2026));
    db.commits.clear();
    await repo.delete('engraved-pen', adminUid: 'admin-1');
    expect((await db.doc('products/engraved-pen').get()).exists, isFalse);
    expect(db.commits, [
      ['delete products/engraved-pen', startsWith('set admin_audit_log/')],
    ]);
    final audit = (await auditEntries(db)).single;
    expect(audit['action'], 'product.delete');
    expect(audit['target'], 'products/engraved-pen');
    expect((audit['before'] as Map)['title'], 'Engraved Pen');
    expect((audit['before'] as Map).containsKey('createdAt'), isFalse);
    expect(audit['after'], isNull);
  });

  test('inline toggle is an audited single-field update', () async {
    await seedProduct(db, simple('engraved-pen'), createdAt: DateTime(2026));
    db.commits.clear();
    await repo.setFlag('engraved-pen', 'isFeatured', true, adminUid: 'admin-1');
    expect((await db.doc('products/engraved-pen').get()).data()!['isFeatured'], isTrue);
    expect(db.commits.single, ['update products/engraved-pen', startsWith('set admin_audit_log/')]);
    final audit = (await auditEntries(db)).single;
    expect(audit['action'], 'product.update');
    expect(audit['before'], {'isFeatured': false});
    expect(audit['after'], {'isFeatured': true});
  });

  group('rebuild search keywords', () {
    test('writes only stale derived fields, one audit entry per batch', () async {
      await seedProduct(db, simple('up-to-date', title: 'Up To Date'), createdAt: DateTime(2026));
      await db.doc('products/stale').set({
        ...simple('stale', title: 'Silver Ring', categories: ['jewellery']).toMap(),
        'searchKeywords': ['old'],
        'createdAt': Timestamp.fromDate(DateTime(2026)),
      });
      db.commits.clear();

      final result = await repo.rebuildSearchFields(adminUid: 'admin-1');
      expect(result.scanned, 2);
      expect(result.updated, 1);
      expect(result.batches, 1);

      final stale = (await db.doc('products/stale').get()).data()!;
      ProductDerived.of(ProductModel.fromMap('stale', stale)).forEach((k, v) => expect(stale[k], v, reason: k));
      expect(stale['searchKeywords'], ['silver', 'ring']);
      expect(stale['catCityKeys'], ['jewellery|all']);
      expect(db.commits.single, ['update products/stale', startsWith('set admin_audit_log/')]);
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'product.rebuildKeywords');
      expect(audit['target'], 'products');
      expect(audit['after'], {'productIds': ['stale'], 'count': 1});
    });

    test('batches never exceed 400 writes', () async {
      for (var i = 0; i < 450; i++) {
        await db.doc('products/p${i.toString().padLeft(3, '0')}').set({'title': 'Gift $i', 'price': 1000 * (i + 1)});
      }
      db.commits.clear();
      final result = await repo.rebuildSearchFields(adminUid: 'admin-1');
      expect(result.scanned, 450);
      expect(result.updated, 450);
      expect(result.batches, 2);
      expect(db.commits.map((c) => c.length), [400, 52]);
      for (final c in db.commits) {
        expect(c.where((op) => op.startsWith('set admin_audit_log/')), hasLength(1));
      }
      final p449 = (await db.doc('products/p449').get()).data()!;
      expect(p449['searchKeywords'], ['gift', '449']);
      expect(p449['priceBand'], 4);
    });
  });

  group('reads', () {
    test('pages newest first, 50 at a time', () async {
      for (var i = 0; i < 55; i++) {
        await seedProduct(db, simple('p$i'), createdAt: DateTime(2026, 1, 1).add(Duration(hours: i)));
      }
      final first = await repo.fetchPage();
      expect(first.items, hasLength(50));
      expect(first.items.first.id, 'p54');
      expect(first.hasMore, isTrue);
      final second = await repo.fetchPage(after: first.cursor);
      expect(second.items.map((p) => p.id), ['p4', 'p3', 'p2', 'p1', 'p0']);
      expect(second.hasMore, isFalse);
    });

    test('category and active filters, alone and together', () async {
      await seedProduct(db, simple('frame', categories: ['frames']), createdAt: DateTime(2026, 1, 3));
      await seedProduct(db, simple('mug', categories: ['mugs'], active: false), createdAt: DateTime(2026, 1, 2));
      await seedProduct(db, simple('pen', categories: ['mugs']), createdAt: DateTime(2026, 1, 1));
      Future<List<String>> ids({String? category, bool? active}) async =>
          [for (final p in (await repo.fetchPage(categoryId: category, isActive: active)).items) p.id];
      expect(await ids(), ['frame', 'mug', 'pen']);
      expect(await ids(category: 'mugs'), ['mug', 'pen']);
      expect(await ids(active: false), ['mug']);
      expect(await ids(category: 'mugs', active: true), ['pen']);
    });

    test('keyword lookup uses the stored searchKeywords', () async {
      await seedProduct(db, simple('a', title: 'Custom Photo Mug'), createdAt: DateTime(2026, 1, 1));
      await seedProduct(db, simple('b', title: 'Wooden Frame'), createdAt: DateTime(2026, 1, 2));
      expect((await repo.searchKeyword('mug')).map((p) => p.id), ['a']);
    });

    test('availability labels cover every value', () {
      expect(ProductAvailability.values.map(availabilityLabel), ['Same day', 'Preparation days', 'Out of stock']);
    });

    test('gift-for labels cover every value', () {
      expect(GiftAudience.values.map(giftAudienceLabel), ['For him', 'For her', 'For companies']);
    });
  });
}
