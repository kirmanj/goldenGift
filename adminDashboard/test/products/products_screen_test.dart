import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

import 'products_test_helpers.dart';

ProductModel _product(
  String id,
  String title, {
  List<String> categories = const [],
  bool active = true,
  bool featured = false,
  int price = 10000,
  int? compareAt,
  ProductAvailability availability = ProductAvailability.sameDay,
  int preparationDays = 0,
  int? stock,
  List<GiftAudience> giftFor = const [],
}) =>
    ProductModel(
      id: id,
      giftFor: giftFor,
      title: LocalizedText(title),
      storeId: 'golden-gift-home',
      categoryIds: categories,
      isActive: active,
      isFeatured: featured,
      price: price,
      compareAtPrice: compareAt,
      availability: availability,
      preparationDays: preparationDays,
      stock: stock,
    );

void main() {
  late RecordingFirestore db;

  setUp(() async {
    db = RecordingFirestore();
    await seedCatalogueBasics(db);
    await seedProduct(
        db,
        _product('wooden-photo-frame', 'Wooden Photo Frame',
            categories: ['frames'], price: 35000, compareAt: 42000, giftFor: [GiftAudience.women, GiftAudience.companies]),
        createdAt: DateTime(2026, 3, 3));
    await seedProduct(
        db,
        _product('custom-photo-mug', 'Custom Photo Mug',
            categories: ['mugs'], active: false, availability: ProductAvailability.preparationDays, preparationDays: 2),
        createdAt: DateTime(2026, 3, 2));
    await seedProduct(db, _product('engraved-pen', 'Engraved Pen', categories: ['mugs'], featured: true, stock: 0),
        createdAt: DateTime(2026, 3, 1));
    db.commits.clear();
  });

  double top(String text) => (find.text(text).evaluate().single.renderObject! as RenderBox).localToGlobal(Offset.zero).dy;

  productsTestWidgets('lists newest first with price, categories and availability; filters', (tester) async {
    await pumpProductsApp(tester, db);
    expect(find.text('Products'), findsWidgets);
    expect(top('Wooden Photo Frame'), lessThan(top('Custom Photo Mug')));
    expect(top('Custom Photo Mug'), lessThan(top('Engraved Pen')));
    expect(find.text('35,000 IQD'), findsOneWidget);
    expect(find.text('42,000 IQD'), findsOneWidget, reason: 'struck compare-at price');
    expect(find.text('2 days prep'), findsOneWidget);
    expect(find.text('Stock 0'), findsOneWidget);
    expect(find.text('Frames'), findsOneWidget, reason: 'category column (wide)');
    expect(find.text('3 shown'), findsOneWidget);

    // Search: client filter over the loaded page, then the keyword lookup.
    await tester.enterText(find.byKey(const ValueKey('productSearch')), 'mug');
    await tester.pump();
    expect(find.text('Custom Photo Mug'), findsOneWidget);
    expect(find.text('Wooden Photo Frame'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('1 shown'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('productSearch')), 'photo wood');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Wooden Photo Frame'), findsOneWidget);
    expect(find.text('Custom Photo Mug'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('3 shown'), findsOneWidget);

    // Active filter.
    await tester.tap(find.text('Inactive'));
    await tester.pumpAndSettle();
    expect(find.text('Custom Photo Mug'), findsOneWidget);
    expect(find.text('Engraved Pen'), findsNothing);
    await tester.tap(find.text('Active').first);
    await tester.pumpAndSettle();
    expect(find.text('Custom Photo Mug'), findsNothing);
    expect(find.text('2 shown'), findsOneWidget);

    // Category + active together.
    await tester.tap(find.byKey(const ValueKey('categoryFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mugs').last);
    await tester.pumpAndSettle();
    expect(find.text('Engraved Pen'), findsOneWidget);
    expect(find.text('1 shown'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('2 shown'), findsOneWidget);
    expect(find.text('Wooden Photo Frame'), findsNothing);
  });

  productsTestWidgets('a one-word search also finds products beyond the loaded page; Load more', (tester) async {
    for (var i = 0; i < 50; i++) {
      await seedProduct(db, _product('gift-$i', 'Gift Box $i'), createdAt: DateTime(2026, 4, 1).add(Duration(hours: i)));
    }
    await seedProduct(db, _product('silver-ring', 'Silver Ring'), createdAt: DateTime(2025, 1, 1));
    await pumpProductsApp(tester, db, size: const Size(1280, 4600));
    expect(find.text('50 shown'), findsOneWidget);
    expect(find.text('Silver Ring'), findsNothing);
    expect(find.text('Load more'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('productSearch')), 'Ring');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Silver Ring'), findsOneWidget, reason: 'searchKeywords array-contains "ring"');

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('54 shown'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  productsTestWidgets('inline toggles write an audited update; a row opens the editor', (tester) async {
    await pumpProductsApp(tester, db);
    await tester.tap(find.byKey(const ValueKey('featured-wooden-photo-frame')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('active-engraved-pen')));
    await tester.pumpAndSettle();
    expect((await db.doc('products/wooden-photo-frame').get()).data()!['isFeatured'], isTrue);
    expect((await db.doc('products/engraved-pen').get()).data()!['isActive'], isFalse);
    expect(db.commits, [
      ['update products/wooden-photo-frame', startsWith('set admin_audit_log/')],
      ['update products/engraved-pen', startsWith('set admin_audit_log/')],
    ]);
    final audits = await auditEntries(db);
    expect(audits.map((a) => a['after']), unorderedEquals([{'isFeatured': true}, {'isActive': false}]));
    expect(audits.every((a) => a['action'] == 'product.update' && a['adminUid'] == testAdmin.uid), isTrue);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('featured-wooden-photo-frame'))).value, isTrue);

    await tester.tap(find.text('Custom Photo Mug'));
    await tester.pumpAndSettle();
    expect(find.text('Edit product'), findsOneWidget);
    expect(find.text('id: custom-photo-mug'), findsOneWidget);
  });

  productsTestWidgets('Rebuild search keywords fixes stale products with an audit entry', (tester) async {
    await db.doc('products/engraved-pen').update({'searchKeywords': <String>[], 'priceBand': 3});
    db.commits.clear();
    await pumpProductsApp(tester, db);
    await tester.tap(find.text('Rebuild search keywords'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rebuild'));
    await tester.pumpAndSettle();
    expect(find.text('Updated 1 of 3 products.'), findsOneWidget);
    final pen = (await db.doc('products/engraved-pen').get()).data()!;
    expect(pen['searchKeywords'], ['engraved', 'pen']);
    expect(pen['priceBand'], 0);
    expect((await auditEntries(db)).single['action'], 'product.rebuildKeywords');
  });

  for (final mode in ThemeMode.values.where((m) => m != ThemeMode.system)) {
    productsTestWidgets('lays out at 800 px in ${mode.name} mode (categories move under the title)', (tester) async {
      await pumpProductsApp(tester, db, size: const Size(800, 1000), themeMode: mode);
      expect(find.text('engraved-pen · Mugs'), findsOneWidget);
      expect(find.text('Categories'), findsNothing);
      expect(find.text('New product'), findsOneWidget);
    });
    productsTestWidgets('lays out at 1280 px in ${mode.name} mode', (tester) async {
      await pumpProductsApp(tester, db, size: const Size(1280, 900), themeMode: mode);
      expect(find.text('Categories'), findsNWidgets(2), reason: 'side nav + the column header');
      expect(find.text('Rebuild search keywords'), findsOneWidget);
      // Gift types under the categories (SRS §5.8a); a product without any is flagged.
      expect(tester.widget<Text>(find.byKey(const ValueKey('giftFor-wooden-photo-frame'))).data, 'For her · For companies');
      expect(tester.widget<Text>(find.byKey(const ValueKey('giftFor-engraved-pen'))).data, 'Gift for: not set');
    });
  }
}
