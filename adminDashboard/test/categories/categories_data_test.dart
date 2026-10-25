import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift_admin/features/categories/categories_data.dart';
import 'package:golden_gift_admin/features/categories/slug.dart';

import 'admin_test_harness.dart';

CategoryModel cat(String id, {int sort = 0, String? title, CategoryType type = CategoryType.productType, String? parentId}) =>
    CategoryModel(id: id, title: LocalizedText(title ?? id), sortOrder: sort, type: type, parentId: parentId);

Future<List<CategoryModel>> load(FakeFirebaseFirestore db) async => sortCategories([
      for (final d in (await db.collection('categories').get()).docs) CategoryModel.fromMap(d.id, d.data()),
    ]);

void main() {
  late FakeFirebaseFirestore db;
  late CategoryAdminRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = CategoryAdminRepository(db, adminUid: testAdmin.uid);
  });

  Future<void> seed(List<CategoryModel> categories) async {
    for (final c in categories) {
      await db.doc('categories/${c.id}').set(c.toMap());
    }
  }

  group('slug ids', () {
    test('kebab slug of the English title', () {
      expect(slugify("Mother's Day"), 'mothers-day');
      expect(slugify('Skin & Body Care'), 'skin-body-care');
      expect(slugify('  Jewelry and Watches  '), 'jewelry-and-watches');
      expect(slugify('3D'), '3d');
      expect(slugify('Kurdistan (local souvenirs)'), 'kurdistan-local-souvenirs');
    });

    test('format and uniqueness', () {
      expect(validateSlugId('mugs', takenIds: const []), isNull);
      expect(validateSlugId('', takenIds: const []), 'Required');
      expect(validateSlugId('Mugs', takenIds: const []), isNotNull);
      expect(validateSlugId('-mugs', takenIds: const []), isNotNull);
      expect(validateSlugId('mugs--cups', takenIds: const []), isNotNull);
      expect(validateSlugId('mugs', takenIds: const ['mugs']), contains('already used'));
    });

    test('create rejects an id already in the list', () async {
      await repo.create(cat('mugs', title: 'Mugs'), existing: const []);
      final existing = await load(db);
      await expectLater(
        repo.create(cat('mugs', title: 'Mugs again'), existing: existing),
        throwsA(isA<CategoryValidationException>()),
      );
      expect((await auditEntries(db)).length, 1);
    });

    test('create rejects an id taken in Firestore even when the local list is stale', () async {
      await seed([cat('mugs', title: 'Mugs')]);
      await expectLater(repo.create(cat('mugs'), existing: const []), throwsA(isA<CategoryIdTakenException>()));
      expect(await auditEntries(db), isEmpty);
      expect((await db.doc('categories/mugs').get()).data()!['title'], 'Mugs');
    });
  });

  group('create / update / delete', () {
    test('create writes the category and its audit entry; appended at the end', () async {
      await seed([cat('a', sort: 0), cat('b', sort: 4)]);
      final created = CategoryModel(
        id: 'mothers-day',
        title: const LocalizedText("Mother's Day", ar: 'عيد الأم'),
        type: CategoryType.occasion,
        isSeasonal: true,
        activeFrom: DateTime(2027, 3, 1),
        activeTo: endOfDay(DateTime(2027, 3, 21)),
        productCount: 99,
      );
      await repo.create(created, existing: await load(db));

      final doc = (await db.doc('categories/mothers-day').get()).data()!;
      expect(doc['title'], "Mother's Day");
      expect(doc['titleAr'], 'عيد الأم');
      expect(doc['type'], 'occasion');
      expect(doc['sortOrder'], 5);
      expect(doc['productCount'], 0, reason: 'a new category has no products');

      final audit = await auditEntries(db);
      expect(audit, hasLength(1));
      expect(audit.single['action'], 'category.create');
      expect(audit.single['target'], 'categories/mothers-day');
      expect(audit.single['adminUid'], 'admin-1');
      expect(audit.single['before'], isNull);
      expect((audit.single['after'] as Map)['title'], "Mother's Day");
      expect((audit.single['after'] as Map)['sortOrder'], 5);
      expect(audit.single['at'], isNotNull);
    });

    test('update keeps sortOrder and productCount, deletes cleared translations, audits before/after', () async {
      const original =
          CategoryModel(id: 'mugs', title: LocalizedText('Mugs', ar: 'أكواب', ku: 'کوپ'), sortOrder: 3, productCount: 12);
      await seed([original]);
      const edited = CategoryModel(
          id: 'mugs', title: LocalizedText('Mugs & Cups', ku: 'کوپ'), sortOrder: 0, productCount: 0, isActive: false);
      await repo.update(original, edited, existing: await load(db));

      final doc = (await db.doc('categories/mugs').get()).data()!;
      expect(doc['title'], 'Mugs & Cups');
      expect(doc.containsKey('titleAr'), isFalse);
      expect(doc['titleKu'], 'کوپ');
      expect(doc['isActive'], false);
      expect(doc['sortOrder'], 3);
      expect(doc['productCount'], 12);

      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'category.update');
      expect((audit['before'] as Map)['title'], 'Mugs');
      expect((audit['before'] as Map)['titleAr'], 'أكواب');
      expect((audit['after'] as Map)['title'], 'Mugs & Cups');
      expect((audit['after'] as Map).containsKey('titleAr'), isFalse);
      expect((audit['after'] as Map)['sortOrder'], 3);
      expect((audit['after'] as Map)['productCount'], 12);
    });

    test('a failed write leaves no audit entry (same batch)', () async {
      // The doc does not exist, so the batched update fails — and so must the audit write.
      final ghost = cat('ghost', title: 'Ghost');
      await expectLater(repo.update(ghost, ghost, existing: [ghost]), throwsA(anything));
      expect(await auditEntries(db), isEmpty);
    });

    test('delete removes the doc with an audit snapshot; blocked while it has subcategories', () async {
      await seed([cat('gifts', title: 'Gifts'), cat('mugs', title: 'Mugs', parentId: 'gifts')]);
      final all = await load(db);
      await expectLater(repo.delete(all.firstWhere((c) => c.id == 'gifts'), existing: all),
          throwsA(isA<CategoryValidationException>()));

      await repo.delete(all.firstWhere((c) => c.id == 'mugs'), existing: all);
      expect((await db.doc('categories/mugs').get()).exists, isFalse);
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'category.delete');
      expect((audit['before'] as Map)['parentId'], 'gifts');
      expect(audit['after'], isNull);
    });
  });

  group('reorder', () {
    test('rewrites sortOrder in list order with one category.reorder entry', () async {
      await seed([cat('a', sort: 0), cat('b', sort: 1), cat('c', sort: 2), cat('d', sort: 3)]);
      final moved = moveItem(await load(db), 3, 0); // drag d to the top
      expect(moved.map((c) => c.id), ['d', 'a', 'b', 'c']);

      expect(await repo.reorder(moved), 4);
      expect((await load(db)).map((c) => '${c.id}:${c.sortOrder}'), ['d:0', 'a:1', 'b:2', 'c:3']);

      final audit = await auditEntries(db);
      expect(audit, hasLength(1));
      expect(audit.single['action'], 'category.reorder');
      expect(audit.single['target'], 'categories');
      expect(audit.single['before'], {'d': 3, 'a': 0, 'b': 1, 'c': 2});
      expect(audit.single['after'], {'d': 0, 'a': 1, 'b': 2, 'c': 3});
    });

    test('only changed positions are written; a no-op writes nothing', () async {
      await seed([cat('a', sort: 0), cat('b', sort: 1), cat('c', sort: 2)]);
      final moved = moveItem(await load(db), 1, 3); // b to the end (ReorderableListView index semantics)
      expect(moved.map((c) => c.id), ['a', 'c', 'b']);
      await repo.reorder(moved);
      final audit = (await auditEntries(db)).single;
      expect(audit['before'], {'c': 2, 'b': 1});
      expect(audit['after'], {'c': 1, 'b': 2});

      expect(await repo.reorder(await load(db)), 0);
      expect(await auditEntries(db), hasLength(1));
    });
  });

  group('status: Available · Coming soon · Hidden (SRS §5.7a)', () {
    const note = LocalizedText('Arriving before Ramadan', ar: 'تصل قبل رمضان', ku: 'پێش ڕەمەزان دەگات');

    test('status is derived from isActive + comingSoon', () {
      expect(cat('a').status, CategoryStatus.available);
      expect(cat('a').copyWith(comingSoon: true).status, CategoryStatus.comingSoon);
      expect(cat('a').copyWith(isActive: false).status, CategoryStatus.hidden);
      expect(cat('a').copyWith(isActive: false, comingSoon: true).status, CategoryStatus.hidden);
    });

    test('Available → Coming soon: isActive, comingSoon, comingSoonSince in one batch with category.status', () async {
      await seed([cat('mugs', title: 'Mugs')]);
      final mugs = (await load(db)).single;
      await repo.setStatus(mugs, CategoryStatus.comingSoon);

      final doc = (await db.doc('categories/mugs').get()).data()!;
      expect(doc['isActive'], isTrue);
      expect(doc['comingSoon'], isTrue);
      expect(doc['comingSoonSince'], isNotNull, reason: 'server time when switched on');
      expect(doc['title'], 'Mugs', reason: 'nothing else changes');

      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'category.status');
      expect(audit['target'], 'categories/mugs');
      expect(audit['adminUid'], 'admin-1');
      expect(audit['before'], {'status': 'available', 'isActive': true, 'comingSoon': false});
      expect(audit['after'], {'status': 'comingSoon', 'isActive': true, 'comingSoon': true});
    });

    test('Coming soon → Hidden clears comingSoon, its note and comingSoonSince', () async {
      await db.doc('categories/eid').set({
        ...cat('eid', title: 'Eid').copyWith(comingSoon: true, comingSoonNote: note).toMap(),
        'comingSoonSince': DateTime(2026, 10, 1),
      });
      final eid = (await load(db)).single;
      expect(eid.status, CategoryStatus.comingSoon);
      expect(eid.comingSoonNote, note);

      await repo.setStatus(eid, CategoryStatus.hidden);
      final doc = (await db.doc('categories/eid').get()).data()!;
      expect(doc['isActive'], isFalse);
      expect(doc['comingSoon'], isFalse);
      for (final key in comingSoonNoteKeys) {
        expect(doc.containsKey(key), isFalse, reason: key);
      }
      expect(doc.containsKey('comingSoonSince'), isFalse);

      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'category.status');
      expect((audit['before'] as Map)['status'], 'comingSoon');
      expect((audit['before'] as Map)['comingSoonNote'], 'Arriving before Ramadan', reason: 'the cleared note is kept in the log');
      expect(audit['after'], {'status': 'hidden', 'isActive': false, 'comingSoon': false});
    });

    test('Hidden → Available; the same status writes nothing', () async {
      await seed([cat('x').copyWith(isActive: false)]);
      final x = (await load(db)).single;
      await repo.setStatus(x, CategoryStatus.hidden);
      expect(await auditEntries(db), isEmpty);

      await repo.setStatus(x, CategoryStatus.available);
      final doc = (await db.doc('categories/x').get()).data()!;
      expect(doc['isActive'], isTrue);
      expect(doc['comingSoon'], isFalse);
      expect((await auditEntries(db)).single['after'], {'status': 'available', 'isActive': true, 'comingSoon': false});
    });

    test('a failed status write leaves no audit entry (same batch)', () async {
      await expectLater(repo.setStatus(cat('ghost'), CategoryStatus.comingSoon), throwsA(anything));
      expect(await auditEntries(db), isEmpty);
    });

    test('editor update: the note is saved trimmed while coming soon and cleared when it leaves', () async {
      const original = CategoryModel(id: 'eid', title: LocalizedText('Eid'), sortOrder: 2, productCount: 3);
      await seed([original]);
      final soon = original.copyWith(
        comingSoon: true,
        comingSoonNote: const LocalizedText('  Arriving before Ramadan ', ar: ' ', ku: 'پێش ڕەمەزان دەگات'),
      );
      await repo.update(original, soon, existing: await load(db));

      var doc = (await db.doc('categories/eid').get()).data()!;
      expect(doc['comingSoon'], isTrue);
      expect(doc['comingSoonNote'], 'Arriving before Ramadan');
      expect(doc.containsKey('comingSoonNoteAr'), isFalse, reason: 'blank translation is not stored');
      expect(doc['comingSoonNoteKu'], 'پێش ڕەمەزان دەگات');
      expect(doc['comingSoonSince'], isNotNull);
      expect(doc['sortOrder'], 2);
      expect(doc['productCount'], 3);
      expect((await auditEntries(db)).single['action'], 'category.update');

      // Still coming soon, new note: comingSoonSince is not reset.
      final stored = (await load(db)).single;
      final since = stored.comingSoonSince;
      await repo.update(stored, stored.copyWith(comingSoonNote: const LocalizedText('Soon')), existing: await load(db));
      doc = (await db.doc('categories/eid').get()).data()!;
      expect(doc['comingSoonNote'], 'Soon');
      expect(doc.containsKey('comingSoonNoteKu'), isFalse);
      expect(CategoryModel.fromMap('eid', doc).comingSoonSince, since);

      // Back to Available: the note (the editor still sends it) and comingSoonSince are deleted.
      final again = (await load(db)).single;
      await repo.update(again, again.copyWith(comingSoon: false), existing: await load(db));
      doc = (await db.doc('categories/eid').get()).data()!;
      expect(doc['comingSoon'], isFalse);
      expect(doc['isActive'], isTrue);
      for (final key in comingSoonNoteKeys) {
        expect(doc.containsKey(key), isFalse, reason: key);
      }
      expect(doc.containsKey('comingSoonSince'), isFalse);
    });

    test('create as coming soon stamps comingSoonSince; a note over 140 characters is refused', () async {
      await repo.create(cat('new', title: 'New').copyWith(comingSoon: true, comingSoonNote: note), existing: const []);
      final doc = (await db.doc('categories/new').get()).data()!;
      expect(doc['comingSoon'], isTrue);
      expect(doc['comingSoonNoteAr'], 'تصل قبل رمضان');
      expect(doc['comingSoonSince'], isNotNull);

      final long = cat('long', title: 'Long').copyWith(comingSoon: true, comingSoonNote: LocalizedText('x' * 141));
      expect(validateCategory(long, existing: const [], isNew: true), contains(contains('140')));
      expect(
        validateCategory(long.copyWith(comingSoonNote: LocalizedText('x' * 140)), existing: const [], isNew: true),
        isEmpty,
      );
    });

    test('"Coming soon" filter', () {
      final all = [
        cat('a'),
        cat('b').copyWith(comingSoon: true),
        cat('c').copyWith(comingSoon: true, isActive: false),
      ];
      expect(filterAdminCategories(all, CategoryFilter.comingSoon, '').map((c) => c.id), ['b']);
    });
  });

  group('validation & filters', () {
    test('seasonal window: both dates, end on or after start (same day allowed)', () {
      expect(validateSeasonWindow(isSeasonal: false), isNull);
      expect(validateSeasonWindow(isSeasonal: true, from: DateTime(2027, 3, 1)), isNotNull);
      expect(validateSeasonWindow(isSeasonal: true, from: DateTime(2027, 3, 2), to: endOfDay(DateTime(2027, 3, 1))),
          contains('on or after'));
      expect(
          validateSeasonWindow(isSeasonal: true, from: startOfDay(DateTime(2027, 3, 1)), to: endOfDay(DateTime(2027, 3, 1))),
          isNull);
    });

    test('parent must exist and cannot be itself or a descendant', () {
      final all = [cat('a'), cat('b', parentId: 'a'), cat('c', parentId: 'b')];
      expect(validateCategory(cat('a', parentId: 'a'), existing: all, isNew: false), contains(contains('own parent')));
      expect(validateCategory(cat('a', parentId: 'c'), existing: all, isNew: false), contains(contains('subcategories')));
      expect(validateCategory(cat('a', parentId: 'zzz'), existing: all, isNew: false), contains(contains('does not exist')));
      expect(validateCategory(cat('c', parentId: 'a'), existing: all, isNew: false), isEmpty);
      expect(descendantsOf('a', all), {'b', 'c'});
    });

    test('English title required', () {
      expect(validateCategory(cat('x', title: ''), existing: const [], isNew: true), contains('English title is required'));
    });

    test('filter chips and title search (any language)', () {
      final all = [
        cat('mugs', title: 'Mugs'),
        const CategoryModel(id: 'mothers-day', title: LocalizedText("Mother's Day", ar: 'عيد الأم'), type: CategoryType.occasion),
        cat('valentine', title: 'Valentine', type: CategoryType.occasion),
      ];
      expect(filterAdminCategories(all, CategoryFilter.occasion, '').map((c) => c.id), ['mothers-day', 'valentine']);
      expect(filterAdminCategories(all, CategoryFilter.productType, '').map((c) => c.id), ['mugs']);
      expect(filterAdminCategories(all, CategoryFilter.all, 'الأم').map((c) => c.id), ['mothers-day']);
      expect(filterAdminCategories(all, CategoryFilter.all, 'val').map((c) => c.id), ['valentine']);
    });
  });
}
