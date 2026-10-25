import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift_admin/core/router/admin_routes.dart';
import 'package:golden_gift_admin/features/products/product_editor_screen.dart';
import 'package:golden_gift_admin/features/products/widgets/option_group_builder.dart';

import 'products_test_helpers.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  late RecordingFirestore db;

  setUp(() async {
    db = RecordingFirestore();
    await seedCatalogueBasics(db);
  });

  productsTestWidgets('validation errors block save; a valid product is created with a slug id', (tester) async {
    await pumpProductsApp(tester, db, initialLocation: AdminRoutes.productNew);
    expect(find.text('New product'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Fix these before saving'), findsOneWidget);
    expect(find.text('• English title is required.'), findsOneWidget);
    expect(find.text('• Price must be greater than 0.'), findsOneWidget);
    expect(find.text('• Choose who it is a gift for (at least one).'), findsOneWidget);
    expect(find.text('Required'), findsWidgets, reason: 'inline field errors too');
    expect(find.text('Choose at least one'), findsOneWidget, reason: 'inline under the Gift for chips');
    expect((await db.collection('products').get()).docs, isEmpty);
    expect(await auditEntries(db), isEmpty);

    await tester.enterText(_field('Title · English *'), 'Custom Photo Mug');
    await tester.enterText(_field('Price (IQD) *'), '15000');
    await tester.tap(find.text('For her'));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one'), findsNothing);
    await tester.enterText(_field('Compare-at price (IQD)'), '15000');
    await tester.pumpAndSettle();
    expect(find.text('Must be greater than the price, or empty.'), findsOneWidget, reason: 'live hint');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('• Compare-at price must be greater than the price (or empty).'), findsOneWidget);
    expect((await db.collection('products').get()).docs, isEmpty);

    await tester.enterText(_field('Compare-at price (IQD)'), '18000');
    await tester.pumpAndSettle();
    expect(find.text('Fix these before saving'), findsNothing, reason: 'the list stays live after a failed save');
    expect(find.text('Shows −17% · 15,000 IQD instead of 18,000 IQD'), findsOneWidget);
    await tester.tap(find.text('Frames'));
    await tester.tap(find.text('Erbil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = (await db.doc('products/custom-photo-mug').get()).data()!;
    expect(stored['storeId'], 'golden-gift-home', reason: 'the only store is the default');
    expect(stored['price'], 15000);
    expect(stored['categoryIds'], ['frames']);
    expect(stored['availableCities'], ['erbil']);
    expect(stored['catCityKeys'], ['frames|erbil']);
    expect(stored['searchKeywords'], ['custom', 'photo', 'mug']);
    expect(stored['giftFor'], ['women']);
    expect(stored['forKeys'], ['women', 'women|cat:frames', 'women|city:erbil', 'women|cat:frames|city:erbil']);
    expect((await auditEntries(db)).single['action'], 'product.create');
    expect(find.text('Edit product'), findsOneWidget, reason: 'moved to the edit route');
    expect(find.text('id: custom-photo-mug'), findsOneWidget);
  });

  productsTestWidgets('option-group builder: add, reorder and delete groups and values', (tester) async {
    await pumpProductsApp(tester, db, initialLocation: AdminRoutes.productNew, size: const Size(1280, 4000));
    await tester.enterText(_field('Title · English *'), 'Frame');
    await tester.enterText(_field('Price (IQD) *'), '30000');
    await tester.tap(find.text('For him'));

    Future<void> addGroup(String type) async {
      await tester.tap(find.text('Add group'));
      await tester.pumpAndSettle();
      expect(find.text('Photo upload'), findsOneWidget, reason: 'the menu lists every type');
      await tester.tap(find.text(type).last);
      await tester.pumpAndSettle();
    }

    await addGroup('Colour swatch');
    await addGroup('Text');
    await addGroup('Text variant');
    expect(find.textContaining('Untitled'), findsNWidgets(3));

    // A value group without values blocks save.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('add at least one value'), findsNWidgets(2));
    expect((await db.collection('products').get()).docs, isEmpty);

    final groupLabels = _field('Group label · English *');
    await tester.enterText(groupLabels.at(0), 'Ink');
    await tester.enterText(groupLabels.at(1), 'Name');
    await tester.enterText(groupLabels.at(2), 'Size');
    await tester.pumpAndSettle();
    expect(find.text('Text · id: name'), findsOneWidget);

    // Swatch values.
    await tester.tap(find.text('Add value').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add value').first);
    await tester.pumpAndSettle();
    final valueLabels = _field('Value label · English *');
    expect(valueLabels, findsNWidgets(2));
    await tester.enterText(valueLabels.at(0), 'Red');
    await tester.enterText(valueLabels.at(1), 'Gold');
    await tester.enterText(_field('Hex *').at(0), '#c62828');
    await tester.enterText(_field('Hex *').at(1), 'C9A227');
    await tester.enterText(_field('Price delta (IQD)').at(1), '-500');
    await tester.pumpAndSettle();
    expect(find.text('Value 1 · id: red'), findsOneWidget);

    // Invalid hex blocks save.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('• Option group 1 (Ink), value 2 (Gold): colour must be #RRGGBB.'), findsOneWidget);
    await tester.enterText(_field('Hex *').at(1), '#C9A227');
    await tester.pumpAndSettle();

    // Size values: add two, delete one.
    await tester.tap(find.text('Add value').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add value').last);
    await tester.pumpAndSettle();
    expect(valueLabels, findsNWidgets(4));
    await tester.enterText(valueLabels.at(2), '30x30cm');
    await tester.tap(find.byTooltip('Delete value').last);
    await tester.pumpAndSettle();
    expect(valueLabels, findsNWidgets(3));

    // Reorder values: Red moves below Gold.
    await tester.tap(find.byTooltip('Move value down').first);
    await tester.pumpAndSettle();
    expect(find.text('Value 1 · id: gold'), findsOneWidget);

    // Reorder groups: Size (3rd) moves to the top.
    await tester.tap(find.byTooltip('Move group up').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move group up').at(1));
    await tester.pumpAndSettle();
    expect(find.text('1. Size'), findsOneWidget);
    expect(find.text('2. Ink'), findsOneWidget);

    // Delete the Name group (now 3rd), after confirming.
    await tester.tap(find.byTooltip('Delete group').at(2));
    await tester.pumpAndSettle();
    expect(find.text('Delete option group?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('3. Name'), findsNothing);

    // Mark Ink required, then save.
    final inkCard = find.ancestor(of: find.text('2. Ink'), matching: find.byType(OptionGroupCard));
    await tester.tap(find.descendant(of: inkCard, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final product = ProductModel.fromMap('frame', (await db.doc('products/frame').get()).data()!);
    expect(product.optionGroups.map((g) => g.id), ['size', 'ink']);
    expect(product.optionGroups.map((g) => g.type), [OptionType.textVariant, OptionType.colorSwatch]);
    expect(product.optionGroups.map((g) => g.sortOrder), [0, 1]);
    expect(product.optionGroups[0].values.map((v) => v.id), ['30x30cm']);
    expect(product.optionGroups[1].required, isTrue);
    expect(product.optionGroups[1].values.map((v) => v.id), ['gold', 'red']);
    expect(product.optionGroups[1].values.map((v) => v.hex), ['#C9A227', '#C62828']);
    expect(product.optionGroups[1].values.map((v) => v.priceDelta), [-500, 0]);
  });

  productsTestWidgets('photo bounds and text max length are validated inline', (tester) async {
    await pumpProductsApp(tester, db, initialLocation: AdminRoutes.productNew, size: const Size(1280, 3000));
    await tester.enterText(_field('Title · English *'), 'Album');
    await tester.enterText(_field('Price (IQD) *'), '20000');
    await tester.tap(find.text('For companies'));
    await tester.tap(find.text('Add group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo upload'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Group label · English *'), 'Photos');
    await tester.enterText(_field('Max photos *'), '12');
    await tester.pumpAndSettle();
    expect(find.text('At most 10'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('• Option group 1 (Photos): photos must satisfy 1 ≤ min ≤ max ≤ 10.'), findsOneWidget);
    await tester.enterText(_field('Max photos *'), '6');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final g = ProductModel.fromMap('album', (await db.doc('products/album').get()).data()!).optionGroups.single;
    expect((g.type, g.minPhotos, g.maxPhotos), (OptionType.photoUpload, 1, 6));
  });

  productsTestWidgets('leaving with unsaved edits asks first (back button and router navigation)', (tester) async {
    final router = await pumpProductsApp(tester, db, initialLocation: AdminRoutes.productNew);
    expect(find.text('Unsaved changes'), findsNothing);
    await tester.enterText(_field('Title · English *'), 'Draft');
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(ProductEditorGuard.hasUnsavedChanges, isTrue);

    await tester.tap(find.text('All products'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('New product'), findsOneWidget);

    router.go(AdminRoutes.products); // left nav / browser back go through onExit
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Rebuild search keywords'), findsOneWidget, reason: 'on the products list');
    expect(ProductEditorGuard.hasUnsavedChanges, isFalse);
  });

  productsTestWidgets('edit keeps counters; delete confirms, audits and returns to the list', (tester) async {
    await seedProduct(
      db,
      const ProductModel(
        id: 'engraved-pen',
        title: LocalizedText('Engraved Pen', ar: 'قلم محفور'),
        storeId: 'golden-gift-home',
        price: 12000,
        salesCount: 5,
        viewCount: 40,
        categoryIds: ['mugs'],
        availability: ProductAvailability.preparationDays,
        preparationDays: 3,
      ),
      createdAt: DateTime(2026),
    );
    await pumpProductsApp(tester, db, initialLocation: AdminRoutes.product('engraved-pen'));
    expect(find.text('Edit product'), findsOneWidget);
    expect(find.text('Engraved Pen'), findsWidgets);
    expect(find.text('قلم محفور'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsNothing);

    await tester.enterText(_field('Price (IQD) *'), '13000');
    await tester.enterText(_field('Preparation days *'), '0');
    await tester.pumpAndSettle();
    expect(find.text('At least 1'), findsOneWidget);
    await tester.enterText(_field('Preparation days *'), '4');
    // Saved before Phase 11 without gift types: one must be chosen first.
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('giftFor-men'))).selected, isFalse);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('• Choose who it is a gift for (at least one).'), findsOneWidget);
    expect((await db.doc('products/engraved-pen').get()).data()!['price'], 12000, reason: 'not saved yet');
    await tester.tap(find.text('For him'));
    await tester.tap(find.text('For companies'));
    await tester.pumpAndSettle();
    expect(find.text('Fix these before saving'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    var stored = (await db.doc('products/engraved-pen').get()).data()!;
    expect(stored['giftFor'], ['men', 'companies']);
    expect(stored['forKeys'], containsAll(['men|cat:mugs|city:all', 'companies|cat:mugs']));
    expect(stored['price'], 13000);
    expect(stored['preparationDays'], 4);
    expect(stored['salesCount'], 5);
    expect(stored['viewCount'], 40);
    expect(find.text('Unsaved changes'), findsNothing);

    await tester.tap(find.byTooltip('Delete product'));
    await tester.pumpAndSettle();
    expect(find.text('Delete product?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((await db.doc('products/engraved-pen').get()).exists, isFalse);
    expect((await auditEntries(db)).map((a) => a['action']), unorderedEquals(['product.update', 'product.delete']));
    expect(find.text('Rebuild search keywords'), findsOneWidget, reason: 'back on the list');
  });

  productsTestWidgets('an existing product shows its gift types; unticking the last one blocks save', (tester) async {
    await seedProduct(
      db,
      const ProductModel(
        id: 'pen-set',
        title: LocalizedText('Pen Set'),
        storeId: 'golden-gift-home',
        price: 22000,
        giftFor: [GiftAudience.men, GiftAudience.companies],
      ),
      createdAt: DateTime(2026),
    );
    await pumpProductsApp(tester, db, initialLocation: AdminRoutes.product('pen-set'));
    bool selected(GiftAudience a) => tester.widget<FilterChip>(find.byKey(ValueKey('giftFor-${a.name}'))).selected;
    expect([for (final a in GiftAudience.values) selected(a)], [true, false, true]);
    expect(find.text('Unsaved changes'), findsNothing);

    await tester.tap(find.text('For him'));
    await tester.tap(find.text('For companies'));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one'), findsOneWidget, reason: 'validated as soon as it is emptied');
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('• Choose who it is a gift for (at least one).'), findsOneWidget);
    expect((await db.doc('products/pen-set').get()).data()!['giftFor'], ['men', 'companies']);

    await tester.tap(find.text('For her'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await db.doc('products/pen-set').get()).data()!['giftFor'], ['women']);
    expect((await db.doc('products/pen-set').get()).data()!['forKeys'], ['women', 'women|city:all']);
  });

  productsTestWidgets('a missing product shows a message', (tester) async {
    await pumpProductsApp(tester, db, initialLocation: AdminRoutes.product('nope'));
    expect(find.text('Product “nope” doesn’t exist.'), findsOneWidget);
  });

  for (final (width, mode) in [(1280.0, ThemeMode.dark), (800.0, ThemeMode.dark), (800.0, ThemeMode.light)]) {
    productsTestWidgets('every option type lays out at $width px in ${mode.name} mode', (tester) async {
      await pumpProductsApp(tester, db,
          initialLocation: AdminRoutes.productNew, size: Size(width, 6000), themeMode: mode);
      for (final type in ['Image variant', 'Text variant', 'Colour swatch', 'Text', 'Long text', 'Date', 'Photo upload', 'Quantity']) {
        await tester.tap(find.text('Add group'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(type).last);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Add value').at(i));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Add image'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Untitled'), findsNWidgets(7)); // Quantity comes pre-labelled
      expect(find.text('8. Quantity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
