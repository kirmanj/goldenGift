import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/utils/search_tokenizer.dart';
import 'package:golden_gift/features/products/data/product_derived.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift_admin/features/products/data/products_admin_repository.dart';
import 'package:golden_gift_admin/features/products/import/csv_codec.dart';
import 'package:golden_gift_admin/features/products/import/product_csv.dart';
import 'package:golden_gift_admin/features/products/import/product_importer.dart';

import 'products_test_helpers.dart';

final bom = String.fromCharCode(0xFEFF);

/// A CSV with [ProductCsv.all] (+ [extra] columns) and one line per row map.
String csvOf(List<Map<String, String>> rows, {List<String> extra = const []}) {
  final header = [...ProductCsv.all, ...extra];
  return encodeCsv([
    header,
    for (final r in rows) [for (final c in header) r[c] ?? ''],
  ]);
}

const existingMug = ProductModel(
  id: 'engraved-mug',
  title: LocalizedText('Engraved Mug', ar: 'كوب محفور'),
  storeId: 'golden-gift-home',
  categoryIds: ['mugs'],
  images: ['https://example.com/mug.jpg'],
  price: 15000,
  compareAtPrice: 20000,
  availability: ProductAvailability.preparationDays,
  preparationDays: 1,
  tags: ['gift'],
  giftFor: [GiftAudience.men, GiftAudience.women],
  salesCount: 7,
  viewCount: 30,
  ratingAvg: 4.5,
  ratingCount: 2,
  optionGroups: [OptionGroup(id: 'name', type: OptionType.text, label: LocalizedText('Name'), maxLength: 20)],
);

const existingBox = ProductModel(
  id: 'oak-box',
  title: LocalizedText('Oak Box', ar: 'صندوق بلوط'),
  storeId: 'golden-gift-home',
  price: 30000,
  giftFor: [GiftAudience.men, GiftAudience.companies],
);

Future<FakeFirebaseFirestore> importWorld([FakeFirebaseFirestore? db]) async {
  final d = db ?? FakeFirebaseFirestore();
  await seedCatalogueBasics(d);
  await seedProduct(d, existingMug, createdAt: DateTime(2026, 9, 1));
  await seedProduct(d, existingBox, createdAt: DateTime(2026, 9, 2));
  return d;
}

const store = 'golden-gift-home';

/// Rows 2 … 12 of the main test file (row 2 has a multi-line cell).
final mainRows = <Map<String, String>>[
  // 2: new, slug collides with the existing product.
  {
    'title': 'Engraved Mug',
    'titleAr': 'كوب محفور كبير',
    'titleKu': 'کوپی هەڵکۆڵراو',
    'description': 'Ceramic, 350 ml.\nDishwasher safe, "premium" glaze.',
    'price': '25,000',
    'categoryIds': 'mugs|frames',
    'storeId': store,
    'availability': 'preparationDays',
    'preparationDays': '2',
    'availableCities': 'erbil',
    'tags': 'Gift|gift|wood',
    'images': 'https://example.com/1.jpg|https://example.com/2.jpg',
    'supplierCode': 'X-1',
  },
  // 3: same title again.
  {'title': 'Engraved Mug', 'price': '26000', 'storeId': store},
  // 4: update — empty cells keep, "-" clears.
  {'id': 'engraved-mug', 'price': '18000', 'compareAtPrice': '-', 'stock': '3'},
  // 5: every kind of bad cell.
  {
    'title': 'Bad',
    'price': '0',
    'categoryIds': 'mugs|nope',
    'storeId': 'ghost',
    'availability': 'tomorrow',
    'availableCities': 'paris',
    'images': 'ftp://example.com/x.jpg',
    'isActive': 'maybe',
  },
  // 6: explicit new id, same day (preparation days saved as 0).
  {'id': 'walnut-frame', 'title': 'Walnut Frame', 'price': '42000', 'storeId': store, 'preparationDays': '5'},
  // 7: duplicate id.
  {'id': 'walnut-frame', 'title': 'Walnut Frame 2', 'price': '43000', 'storeId': store},
  // 8: reserved id.
  {'id': 'new', 'title': 'New', 'price': '1000', 'storeId': store},
  // 9: update with nothing to change.
  {'id': 'oak-box', 'price': '30000', 'title': 'Oak Box'},
  // 10: unknown id without a title.
  {'id': 'ghost-id', 'price': '9000'},
  // 11: compare price not above the price.
  {'title': 'Cheap', 'price': '5000', 'compareAtPrice': '4000', 'storeId': store},
  // 12: preparation days missing.
  {'title': 'Slow', 'price': '5000', 'storeId': store, 'availability': 'Preparation days'},
];

ImportRowPlan rowAt(ImportPlan plan, int row) => plan.rows.firstWhere((r) => r.row == row);

void main() {
  group('CSV parser (RFC 4180)', () {
    test('rows, CRLF / LF endings, trailing newline, blank lines', () {
      final records = parseCsv('a,b,c\r\n1,2,3\n\n4,5,6\n');
      expect([for (final r in records) r.cells], [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
        [''],
        ['4', '5', '6'],
      ]);
      expect([for (final r in records) r.line], [1, 2, 3, 4]);
      expect(records[2].isBlank, isTrue);
      expect(parseCsv('x,y'), hasLength(1), reason: 'no trailing newline');
      expect(parseCsv('a\rb\r').map((r) => r.cells.single), ['a', 'b'], reason: 'old Mac CR endings');
    });

    test('quoted cells: commas, doubled quotes, line breaks; records keep their first line', () {
      final records = parseCsv('id,text\r\n1,"Hello, world"\r\n2,"She said ""hi"""\r\n3,"line one\r\nline two\nthree"\r\n4,x\r\n');
      expect(records[1].cells, ['1', 'Hello, world']);
      expect(records[2].cells, ['2', 'She said "hi"']);
      expect(records[3].cells, ['3', 'line one\nline two\nthree']);
      expect(records[3].line, 4);
      expect(records[4].line, 7, reason: 'the quoted cell spanned lines 4–6');
    });

    test('BOM, Arabic and Kurdish text, empty and empty-quoted cells', () {
      final records = parseCsv('${bom}title,titleAr,titleKu\nMug,"كوب، محفور, كبير",چوارچێوەی دار\na,,""\n');
      expect(records[0].cells.first, 'title', reason: 'BOM stripped');
      expect(records[1].cells, ['Mug', 'كوب، محفور, كبير', 'چوارچێوەی دار']);
      expect(records[2].cells, ['a', '', '']);
    });

    test('lenient with stray quotes; an unclosed quote is an error with its line', () {
      expect(parseCsv('a"b,c').single.cells, ['a"b', 'c']);
      expect(parseCsv('"ab"cd,e').single.cells, ['abcd', 'e']);
      expect(
        () => parseCsv('a,b\n1,"open\n2,3\n'),
        throwsA(isA<CsvFormatException>().having((e) => e.message, 'message', contains('line 2'))),
      );
    });

    test('encode → parse round trip', () {
      final rows = [
        ['plain', 'with, comma', 'with "quotes"', 'multi\nline', ' padded ', 'عربي | کوردی', ''],
      ];
      final text = encodeCsv(rows);
      expect(text, contains('"with, comma"'));
      expect(text, contains('"with ""quotes"""'));
      expect(text.endsWith('\r\n'), isTrue);
      expect(parseCsv(text).single.cells, rows.single);
    });

    test('bytes: UTF-8 (with or without BOM) only', () {
      expect(decodeCsvBytes(utf8.encode('${bom}title\nكوب\n')), 'title\nكوب\n');
      expect(decodeCsvBytes(utf8.encode('title\n')), 'title\n');
      expect(() => decodeCsvBytes([0x4D, 0xE9, 0x0A]), throwsA(isA<CsvFormatException>()));
    });
  });

  group('product sheet', () {
    test('header is case-insensitive, any order; unknown columns are ignored', () {
      final sheet = parseProductSheet('Title,PRICE,Colour,storeid\nMug,1000,red,s1\n');
      expect(sheet.columns, ['title', 'price', 'storeId']);
      expect(sheet.ignoredColumns, ['Colour']);
      expect(sheet.rows.single.cells, {'title': 'Mug', 'price': '1000', 'storeId': 's1'});
      expect(sheet.rows.single.row, 2);
    });

    test('unreadable files', () {
      expect(() => parseProductSheet(''), throwsA(isA<CsvFormatException>()));
      expect(() => parseProductSheet('title,Title\nA,B\n'),
          throwsA(isA<CsvFormatException>().having((e) => e.message, 'message', contains('appears twice'))));
      expect(() => parseProductSheet('name,cost\nA,1\n'),
          throwsA(isA<CsvFormatException>().having((e) => e.message, 'message', contains('header'))));
    });

    test('rows with a wrong number of cells are flagged (trailing empty extras are fine)', () {
      final sheet = parseProductSheet('id,title,price\na,Mug\nb,Frame,1000,\nc,Box,1,extra\n');
      expect(sheet.rowIssues.keys, [2, 4]);
      expect(sheet.rowIssues[2]!.single.message, contains('Has 2 cells'));
    });

    test('the template parses and lists every documented column', () {
      final text = ProductCsv.template(exampleCategory: 'mugs', exampleStore: store, exampleCity: 'erbil');
      expect(text.startsWith(bom), isTrue);
      final sheet = parseProductSheet(text);
      expect(sheet.columns, ProductCsv.all);
      expect(sheet.rows.single.cell('titleKu'), isNotEmpty);
      expect(sheet.rows.single.cell('description'), contains('\n'));
      expect(ProductCsv.help.keys.toSet(), ProductCsv.all.toSet());
    });

    test('cell parsers', () {
      expect(parseImportInt('25000'), (25000, null));
      expect(parseImportInt('25,000'), (25000, null));
      expect(parseImportInt(' 25 000 '), (25000, null));
      expect(parseImportInt('٢٥٠٠٠'), (25000, null));
      expect(parseImportInt('۲۵۰۰۰'), (25000, null));
      expect(parseImportInt('25000.00'), (25000, null));
      expect(parseImportInt('-3'), (-3, null));
      expect(parseImportInt('25000.5').$2, contains('Whole numbers only'));
      expect(parseImportInt('abc').$2, contains('Not a whole number'));
      expect(parseImportInt('99999999999').$2, contains('Too large'));
      expect(parseImportBool('TRUE'), (true, null));
      expect(parseImportBool('no'), (false, null));
      expect(parseImportBool('0'), (false, null));
      expect(parseImportBool('maybe').$2, contains('true or false'));
      expect(parseImportAvailability('Same day').$1, ProductAvailability.sameDay);
      expect(parseImportAvailability('preparation_days').$1, ProductAvailability.preparationDays);
      expect(parseImportAvailability('outOfStock').$1, ProductAvailability.outOfStock);
      expect(parseImportAvailability('soon').$2, contains('sameDay'));
      expect(parseImportGiftFor('men|women').$1, [GiftAudience.men, GiftAudience.women]);
      expect(parseImportGiftFor('men|women').$2, isNull);
      expect(parseImportGiftFor(' Companies | MEN |men').$1, [GiftAudience.men, GiftAudience.companies],
          reason: 'case-insensitive, de-duplicated, in GiftAudience order');
      expect(parseImportGiftFor('women').$1, [GiftAudience.women]);
      expect(parseImportGiftFor('men|kids|teens').$2, 'Use men, women, companies separated by |: “kids|teens”.');
      expect(parseImportGiftFor('him').$1, isNull);
      expect(parseImportGiftFor('||').$2, contains('at least one'));
      expect(parseImportList(' a | b ||a| c '), ['a', 'b', 'c']);
      expect(parseImportList('Gift|gift|GIFT|wood', caseInsensitive: true), ['Gift', 'wood']);
      expect(isHttpUrl('https://example.com/a.jpg'), isTrue);
      expect(isHttpUrl('ftp://example.com/a.jpg'), isFalse);
      expect(isHttpUrl('example.com/a.jpg'), isFalse);
    });
  });

  group('analyze', () {
    late FakeFirebaseFirestore db;
    late ImportPlan plan;

    setUp(() async {
      db = await importWorld();
      plan = await ProductImporter(db).analyze(parseProductSheet(csvOf(mainRows, extra: ['supplierCode'])));
    });

    test('create / update / unchanged / invalid', () {
      expect(plan.sheet.ignoredColumns, ['supplierCode']);
      expect({for (final r in plan.rows) r.row: r.action}, {
        2: ImportAction.create,
        3: ImportAction.create,
        4: ImportAction.update,
        5: ImportAction.invalid,
        6: ImportAction.create,
        7: ImportAction.invalid,
        8: ImportAction.invalid,
        9: ImportAction.unchanged,
        10: ImportAction.invalid,
        11: ImportAction.invalid,
        12: ImportAction.invalid,
      });
    });

    test('a row without an id gets the title slug, unique in Firestore and in the file', () {
      expect(rowAt(plan, 2).id, 'engraved-mug-2');
      expect(rowAt(plan, 3).id, 'engraved-mug-3');
      expect(rowAt(plan, 6).id, 'walnut-frame');
    });

    test('a create writes exactly what the editor writes (model + derived fields + keywords)', () {
      final r = rowAt(plan, 2);
      final m = r.model!;
      expect(m.price, 25000);
      expect(m.title, const LocalizedText('Engraved Mug', ar: 'كوب محفور كبير', ku: 'کوپی هەڵکۆڵراو'));
      expect(m.description.en, 'Ceramic, 350 ml.\nDishwasher safe, "premium" glaze.');
      expect(m.categoryIds, ['mugs', 'frames']);
      expect(m.tags, ['Gift', 'wood']);
      expect(m.images, hasLength(2));
      expect(m.preparationDays, 2);
      expect(m.stock, isNull);
      expect(m.isActive, isTrue);
      expect(m.giftFor, ProductCsv.defaultGiftFor, reason: 'blank giftFor = men|women');
      expect(r.data!['giftFor'], ['men', 'women']);
      expect(r.data!['forKeys'], ProductDerived.of(m)['forKeys']);
      expect(r.data!['forKeys'], containsAll(['men|cat:mugs|city:erbil', 'women|cat:frames']));
      expect(r.data, ProductsAdminRepository.productData(m));
      expect(r.data!['searchKeywords'], SearchTokenizer.keywords([...m.title.all, ...m.tags]));
      expect(r.data!['searchKeywords'], containsAll(['engraved', 'wood']));
      expect(r.data!['catCityKeys'], ['mugs|erbil', 'frames|erbil']);
      expect(r.data!, containsPair('cityKeys', ['erbil']));
      expect(r.data!, containsPair('priceBand', ProductDerived.of(m)['priceBand']));
      expect(r.data!.containsKey('supplierCode'), isFalse, reason: 'unknown columns are ignored');
      expect(rowAt(plan, 6).model!.preparationDays, 0, reason: 'same day saves 0 like the editor');
    });

    test('an update changes only the filled cells and refreshes the derived fields', () {
      final r = rowAt(plan, 4);
      expect(r.changedFields, unorderedEquals(['price', 'compareAtPrice', 'stock']));
      expect(r.data, containsPair('price', 18000));
      expect(r.data, containsPair('compareAtPrice', null));
      expect(r.data, containsPair('stock', 3));
      expect(r.data, containsPair('hasDiscount', false));
      expect(r.data!.keys, containsAll(['priceBand', 'cityKeys', 'catCityKeys', 'forKeys', 'searchKeywords']));
      for (final k in ['title', 'tags', 'images', 'giftFor', 'salesCount', 'viewCount', 'ratingAvg', 'ratingCount', 'optionGroups']) {
        expect(r.data!.containsKey(k), isFalse, reason: '$k is not in the CSV row');
      }
      expect(r.model!.optionGroups, hasLength(1));
    });

    test('per-column validation messages', () {
      final bad = rowAt(plan, 5);
      String col(String c) => bad.issuesFor(c).map((i) => i.message).join(' ');
      expect(col('price'), 'Price must be greater than 0.');
      expect(col('categoryIds'), 'Unknown category: nope.');
      expect(col('storeId'), contains('Unknown store “ghost”.'));
      expect(col('availability'), contains('Use sameDay, preparationDays, outOfStock'));
      expect(col('availableCities'), 'Unknown city: paris.');
      expect(col('images'), contains('Not an http(s) URL'));
      expect(col('isActive'), contains('true or false'));

      expect(rowAt(plan, 7).issuesFor('id').single.message, 'The id “walnut-frame” is already used on row 6.');
      expect(rowAt(plan, 8).issuesFor('id').first.message, '“new” is reserved.');
      expect(rowAt(plan, 10).issuesFor('id').single.message, startsWith('No product has this id.'));
      expect(rowAt(plan, 11).issuesFor('compareAtPrice').single.message, startsWith('Compare-at price must be greater'));
      expect(rowAt(plan, 12).issuesFor('preparationDays').single.message, contains('at least 1'));
    });

    test('giftFor on new products: parsed case-insensitively, unknown = row error, blank = men|women', () async {
      final p = await ProductImporter(db).analyze(parseProductSheet(csvOf([
        {'title': 'Pen Set', 'price': '20000', 'storeId': store, 'giftFor': 'Men|COMPANIES'},
        {'title': 'Toy', 'price': '20000', 'storeId': store, 'giftFor': 'men|kids'},
        {'title': 'Scarf', 'price': '20000', 'storeId': store, 'giftFor': '-'},
        {'title': 'Mug', 'price': '20000', 'storeId': store},
      ])));
      expect(p.rows[0].action, ImportAction.create);
      expect(p.rows[0].model!.giftFor, [GiftAudience.men, GiftAudience.companies]);
      expect(p.rows[0].data!['forKeys'], ['men', 'men|city:all', 'companies', 'companies|city:all']);

      expect(p.rows[1].action, ImportAction.invalid);
      expect(p.rows[1].issuesFor('giftFor').first.message, 'Use men, women, companies separated by |: “kids”.');

      expect(p.rows[2].model!.giftFor, ProductCsv.defaultGiftFor, reason: '“-” on a new product = empty');
      expect(p.rows[3].model!.giftFor, ProductCsv.defaultGiftFor, reason: 'blank = men|women');
    });

    test('giftFor on updates: keeps, changes, can’t clear; an older product without one gets men|women', () async {
      await db.doc('products/old-frame').set({
        ...ProductsAdminRepository.productData(
            const ProductModel(id: 'old-frame', title: LocalizedText('Old Frame'), storeId: store, price: 9000)),
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      final p = await ProductImporter(db).analyze(parseProductSheet(csvOf([
        {'id': 'engraved-mug', 'price': '16000'},
        {'id': 'oak-box', 'giftFor': 'companies'},
        {'id': 'old-frame', 'price': '9500'},
      ])));
      expect(p.rows[0].changedFields, ['price'], reason: 'blank keeps men|women');
      expect(p.rows[1].changedFields, ['giftFor']);
      expect(p.rows[1].data!['giftFor'], ['companies']);
      expect(p.rows[1].data!['forKeys'], ['companies', 'companies|city:all']);
      expect(p.rows[2].changedFields, unorderedEquals(['price', 'giftFor']));
      expect(p.rows[2].data!['giftFor'], ['men', 'women']);

      final cleared = await ProductImporter(db).analyze(parseProductSheet(csvOf([
        {'id': 'oak-box', 'giftFor': '-'},
      ])));
      expect(cleared.rows.single.issuesFor('giftFor').single.message, 'Required — it can’t be cleared.');

      // A file made before Phase 11 (no giftFor column) still imports.
      final legacy = await ProductImporter(db)
          .analyze(parseProductSheet('title,price,storeId\nLegacy Mug,12000,$store\n'));
      expect(legacy.rows.single.action, ImportAction.create);
      expect(legacy.rows.single.model!.giftFor, ProductCsv.defaultGiftFor);
    });

    test('required fields can’t be cleared; translations can', () async {
      final p = await ProductImporter(db).analyze(parseProductSheet(csvOf([
        {'id': 'oak-box', 'title': '-'},
        {'id': 'engraved-mug', 'titleAr': '-'},
      ])));
      expect(p.rows[0].issuesFor('title').single.message, 'Required — it can’t be cleared.');
      expect(p.rows[1].action, ImportAction.update);
      expect(p.rows[1].changedFields, ['titleAr']);
      expect(p.rows[1].data!['titleAr'], isA<FieldValue>());
    });
  });

  group('commit', () {
    test('creates, updates (counters, ratings, option groups untouched) and one audit entry per batch', () async {
      final db = await importWorld();
      final importer = ProductImporter(db);
      final plan = await importer.analyze(parseProductSheet(csvOf(mainRows)));
      final progress = <(int, int)>[];
      final summary = await importer.commit(plan, adminUid: 'admin-1', onProgress: (d, t) => progress.add((d, t)));
      expect(summary.created, ['engraved-mug-2', 'engraved-mug-3', 'walnut-frame']);
      expect(summary.updated, ['engraved-mug']);
      expect(summary.failed, isEmpty);
      expect(summary.batches, 1);
      expect(summary.skipped.map((s) => s.$1), [5, 7, 8, 9, 10, 11, 12]);
      expect(summary.skipped.firstWhere((s) => s.$1 == 9).$2, contains('No changes'));
      expect(progress, [(4, 4)]);

      final created = (await db.doc('products/engraved-mug-2').get()).data()!;
      expect(created['createdAt'], isA<Timestamp>());
      expect(created['updatedAt'], isA<Timestamp>());
      expect(created['currency'], 'IQD');
      expect(created['salesCount'], 0);
      expect(created['titleKu'], 'کوپی هەڵکۆڵراو');

      final updated = (await db.doc('products/engraved-mug').get()).data()!;
      expect(updated['price'], 18000);
      expect(updated['compareAtPrice'], isNull);
      expect(updated['hasDiscount'], isFalse);
      expect(updated['stock'], 3);
      expect(updated['title'], 'Engraved Mug');
      expect(updated['titleAr'], 'كوب محفور');
      expect(updated['tags'], ['gift']);
      expect(updated['salesCount'], 7);
      expect(updated['viewCount'], 30);
      expect(updated['ratingAvg'], 4.5);
      expect(updated['ratingCount'], 2);
      expect(updated['optionGroups'], hasLength(1));
      expect(updated['availability'], 'preparationDays');

      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'product.import');
      expect(audit['target'], 'products');
      expect(audit['adminUid'], 'admin-1');
      expect(audit['after'], {
        'created': 3,
        'updated': 1,
        'ids': ['engraved-mug-2', 'engraved-mug-3', 'walnut-frame', 'engraved-mug'],
      });
    });

    test('clearing a translation deletes the field', () async {
      final db = await importWorld();
      final importer = ProductImporter(db);
      final plan = await importer.analyze(parseProductSheet(csvOf([
        {'id': 'engraved-mug', 'titleAr': '-'},
      ])));
      await importer.commit(plan, adminUid: 'admin-1');
      final doc = (await db.doc('products/engraved-mug').get()).data()!;
      expect(doc.containsKey('titleAr'), isFalse);
      expect(doc['searchKeywords'], SearchTokenizer.keywords(['Engraved Mug', 'gift']));
    });

    test('≤ 400 writes per batch, each with its own audit entry', () async {
      final db = RecordingFirestore();
      await importWorld(db);
      final importer = ProductImporter(db);
      final rows = [
        for (var i = 0; i < 450; i++) {'title': 'Item $i', 'price': '${1000 + i}', 'storeId': store},
      ];
      final plan = await importer.analyze(parseProductSheet(csvOf(rows)));
      expect(plan.count(ImportAction.create), 450);
      db.commits.clear();
      final summary = await importer.commit(plan, adminUid: 'admin-1');
      expect(summary.batches, 2);
      expect(db.commits.map((c) => c.length), [400, 52]);
      expect(db.commits.every((c) => c.last.startsWith('set admin_audit_log/')), isTrue);
      final audit = await auditEntries(db);
      expect(audit.map((e) => (e['after'] as Map)['created']), unorderedEquals([399, 51]));
      expect((await db.collection('products').count().get()).count, 452);
    });

    test('a batch that fails is reported and the others still commit', () async {
      final db = await importWorld();
      final importer = ProductImporter(db);
      final plan = await importer.analyze(parseProductSheet(csvOf([
        {'id': 'oak-box', 'price': '31000'},
      ])));
      await db.doc('products/oak-box').delete(); // deleted between preview and import
      final summary = await importer.commit(plan, adminUid: 'admin-1');
      expect(summary.updated, isEmpty);
      expect(summary.failed.single.$1, 2);
      expect(await auditEntries(db), isEmpty, reason: 'the audit entry was in the failed batch');
    });
  });
}
