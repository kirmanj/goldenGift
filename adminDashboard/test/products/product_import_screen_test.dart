import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/core/web/browser.dart';
import 'package:golden_gift_admin/features/products/import/product_csv.dart';
import 'package:golden_gift_admin/features/products/import/product_import_screen.dart';
import 'package:golden_gift_admin/features/products/products_screen.dart';

import '../seller/phase8_test_harness.dart';
import 'csv_import_test.dart' show csvOf, importWorld, mainRows;

List<Override> picking(String csv, {String name = 'products.csv'}) =>
    [csvFilePickerProvider.overrideWithValue(() async => PickedCsvFile(name, utf8.encode(csv)))];

/// Lets the analysis (many small reads) finish.
Future<void> settleLong(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await settle(tester);
  }
}

/// Disposes the previous ProviderScope, so the next pump really signs in as
/// another account (Riverpod keeps a scope's provider overrides).
Future<void> signOutOfTree(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<void> pickFile(WidgetTester tester) async {
  await tester.tap(find.text('Choose CSV file'));
  await settleLong(tester);
}

void main() {
  testWidgets('pick → preview with per-row errors → import → summary', (tester) async {
    final db = await importWorld();
    await pumpPhase8(tester, const ProductImportScreen(), db: db, size: const Size(1440, 1200), overrides: picking(csvOf(mainRows)));
    await pickFile(tester);
    expect(find.text('products.csv'), findsOneWidget);
    expect(find.text('11 rows · 3 to create · 1 to update · 1 without changes · 6 with errors'), findsOneWidget);
    expect(find.text('engraved-mug-2'), findsOneWidget);
    expect(find.text('price: Price must be greater than 0.'), findsOneWidget);
    expect(find.text('Changes: price, compareAtPrice, stock'), findsOneWidget);

    await tester.tap(find.textContaining('Errors ('));
    await settle(tester);
    expect(find.text('engraved-mug-2'), findsNothing);
    expect(find.text('Bad'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('runImport')));
    await settle(tester);
    expect(find.text('Import 4 products?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await settleLong(tester);
    expect(find.text('Import finished'), findsOneWidget);
    expect(find.text('3 created · 1 updated · 7 skipped'), findsOneWidget);
    expect((await db.doc('products/walnut-frame').get()).exists, isTrue);
    expect((await auditEntries(db)).single['action'], 'product.import');
    expect(find.byKey(const ValueKey('runImport')), findsNothing, reason: 'imported once');
  });

  testWidgets('download template saves the documented header with a BOM', (tester) async {
    final db = await importWorld();
    await pumpPhase8(tester, const ProductImportScreen(), db: db);
    downloadedFiles.clear();
    await tester.tap(find.text('Download template'));
    await tester.pump();
    final (name, text) = downloadedFiles.single;
    expect(name, 'golden-gift-products-template.csv');
    expect(text.codeUnitAt(0), 0xFEFF);
    expect(text.substring(1).split('\r\n').first, ProductCsv.all.join(','));
    expect(text, contains('golden-gift-home'), reason: 'real store id from the project');
  });

  testWidgets('an unreadable file shows why', (tester) async {
    final db = await importWorld();
    await pumpPhase8(tester, const ProductImportScreen(), db: db, overrides: picking('name,cost\nMug,1\n'));
    await pickFile(tester);
    expect(find.textContaining('it needs at least an “id” or a “title” column'), findsOneWidget);
    expect(find.byKey(const ValueKey('runImport')), findsNothing);
  });

  testWidgets('format help lists every column', (tester) async {
    final db = await importWorld();
    await pumpPhase8(tester, const ProductImportScreen(), db: db, size: const Size(1440, 1600));
    await tester.tap(find.text('CSV format'));
    await settle(tester);
    expect(find.text(ProductCsv.all.join(',')), findsOneWidget);
    expect(find.text(ProductCsv.help['availability']!), findsOneWidget);
  });

  testWidgets('finance and partner accounts can’t import', (tester) async {
    final db = await importWorld();
    await pumpPhase8(tester, const ProductImportScreen(), db: db, session: staffSession(AdminRole.finance));
    expect(find.textContaining('Your role can’t import products'), findsOneWidget);
    expect(find.text('Choose CSV file'), findsNothing);

    await seedStore(db, 'store-a');
    await signOutOfTree(tester);
    await pumpPhase8(tester, const ProductImportScreen(), db: db, session: sellerSession);
    expect(find.text('Products'), findsOneWidget, reason: 'the seller nav');
    expect(find.textContaining('Your role can’t import products'), findsOneWidget);
  });

  testWidgets('Products shows “Import CSV” to catalogue staff only', (tester) async {
    final db = await importWorld();
    await pumpPhase8(tester, const ProductsScreen(), db: db, size: const Size(1440, 1000));
    expect(find.byKey(const ValueKey('importCsv')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('importCsv')));
    await settle(tester);
    expect(find.text('visited: /products/import'), findsOneWidget);

    await signOutOfTree(tester);
    await pumpPhase8(tester, const ProductsScreen(), db: db, session: staffSession(AdminRole.content));
    expect(find.byKey(const ValueKey('importCsv')), findsOneWidget);
    await signOutOfTree(tester);
    await pumpPhase8(tester, const ProductsScreen(), db: db, session: staffSession(AdminRole.finance));
    expect(find.byKey(const ValueKey('importCsv')), findsNothing);
    await seedStore(db, 'store-a');
    await signOutOfTree(tester);
    await pumpPhase8(tester, const ProductsScreen(), db: db, session: sellerSession);
    expect(find.text('Store profile'), findsOneWidget, reason: 'really the seller view');
    expect(find.byKey(const ValueKey('importCsv')), findsNothing);
  });

  for (final (mode, size) in layoutMatrix) {
    testWidgets('lays out with a preview in ${mode.name} at ${size.width.toInt()} px', (tester) async {
      final db = await importWorld();
      final errors = await errorsOutsideCoreNav(() async {
        await pumpPhase8(tester, const ProductImportScreen(),
            db: db, mode: mode, size: size, overrides: picking(csvOf(mainRows)));
        await pickFile(tester);
        expect(find.text('engraved-mug-2'), findsOneWidget);
        await tester.tap(find.text('CSV format'));
        await settle(tester);
      });
      expect(errors, isEmpty);
    });
  }
}
