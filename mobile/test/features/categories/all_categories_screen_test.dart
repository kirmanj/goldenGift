import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/categories/presentation/providers/categories_providers.dart';
import 'package:golden_gift/features/categories/presentation/widgets/category_grid.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/products/presentation/screens/products_screen.dart';
import 'package:golden_gift/models/category_model.dart';

import '../products/catalogue_test_harness.dart';

Finder _tile(String label) => find.widgetWithText(CategoryTile, label);

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

void main() {
  final en = l10nFor('en');

  testWidgets('every category in a 3-column grid', (tester) async {
    await pumpCatalogueApp(tester, initialPath: AppRoutes.categories, size: const Size(390, 1400));

    expect(find.text(en.allCategories), findsOneWidget);
    expect(find.byType(CategoryTile), findsNWidgets(testCategories.length));
    final first = tester.getTopLeft(_tile('Flowers'));
    final third = tester.getTopLeft(_tile('Birthdays'));
    final fourth = tester.getTopLeft(_tile('Magnets'));
    expect(third.dy, first.dy);
    expect(fourth.dy, greaterThan(first.dy));
    expect(fourth.dx, first.dx);
  });

  testWidgets('local search matches English, Arabic and Kurdish titles', (tester) async {
    await pumpCatalogueApp(tester, initialPath: AppRoutes.categories, size: const Size(390, 1400));

    await _search(tester, 'MUG');
    expect(find.byType(CategoryTile), findsOneWidget);
    expect(_tile('Mugs'), findsOneWidget);

    await _search(tester, 'زهور'); // Arabic
    expect(find.byType(CategoryTile), findsOneWidget);
    expect(_tile('Flowers'), findsOneWidget);

    await _search(tester, 'چەرم'); // Kurdish
    expect(find.byType(CategoryTile), findsOneWidget);
    expect(_tile('Leather'), findsOneWidget);

    // Arabic keyboard kaf (ك) still finds the Kurdish spelling (ک).
    await _search(tester, 'كوردستان');
    expect(_tile('Kurdistan'), findsOneWidget);

    await _search(tester, '');
    expect(find.byType(CategoryTile), findsNWidgets(testCategories.length));
  });

  testWidgets('shows localized titles and searches them in Kurdish', (tester) async {
    await pumpCatalogueApp(tester, initialPath: AppRoutes.categories, locale: 'ckb', size: const Size(390, 1400));
    expect(_tile('گوڵ'), findsOneWidget);
    await _search(tester, 'مۆم');
    expect(find.byType(CategoryTile), findsOneWidget);
    expect(_tile('مۆم'), findsOneWidget);
  });

  testWidgets('no match shows the empty state', (tester) async {
    await pumpCatalogueApp(tester, initialPath: AppRoutes.categories);
    await _search(tester, 'xyz');
    expect(find.byType(CategoryTile), findsNothing);
    expect(find.text(en.noCategoriesMatch), findsOneWidget);
  });

  testWidgets('a tile opens the products list filtered by that category', (tester) async {
    final data = CatalogueData();
    final router = await pumpCatalogueApp(tester, initialPath: AppRoutes.categories, data: data);
    await tester.tap(_tile('Mugs'));
    await tester.pumpAndSettle();

    expect(locationOf(router), AppRoutes.productsFor(const ProductQuery(categoryId: 'mugs')));
    expect(tester.widget<ProductsScreen>(find.byType(ProductsScreen)).initialQuery,
        const ProductQuery(categoryId: 'mugs'));
    expect(data.repository.queries.last, const ProductQuery(categoryId: 'mugs'));
  });

  testWidgets('the cart button opens the Cart tab', (tester) async {
    final router = await pumpCatalogueApp(tester, initialPath: AppRoutes.categories);
    await tester.tap(find.byTooltip(en.cart));
    await tester.pumpAndSettle();
    expect(locationOf(router), AppRoutes.mainTab(1));
  });

  testWidgets('skeleton while loading, error with Retry that reloads', (tester) async {
    var attempt = 0;
    final firstLoad = StreamController<List<CategoryModel>>();
    addTearDown(firstLoad.close);
    await pumpCatalogueApp(
      tester,
      initialPath: AppRoutes.categories,
      settle: false,
      data: CatalogueData(
        allCategories: () => ++attempt == 1 ? firstLoad.stream : Stream.value(testCategories),
      ),
    );
    await tester.pump();
    expect(find.byType(CategoryTileSkeleton), findsWidgets);

    firstLoad.addError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);

    await tester.tap(find.text(en.retry));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsNothing);
    expect(find.byType(CategoryTile), findsWidgets);
    expect(attempt, 2);
  });

  test('filterCategories ignores case, diacritics and keyboard letter variants', () {
    expect(filterCategories(testCategories, '  flow ').map((c) => c.id), ['flowers']);
    expect(filterCategories(testCategories, 'أكواب').map((c) => c.id), ['mugs']);
    expect(filterCategories(testCategories, ''), testCategories);
  });

  group('locales, themes, sizes', () {
    for (final (locale, mode) in [
      ('ar', ThemeMode.light),
      ('ckb', ThemeMode.dark),
      ('en', ThemeMode.dark),
    ]) {
      testWidgets('renders in $locale / ${mode.name}', (tester) async {
        await pumpCatalogueApp(tester, initialPath: AppRoutes.categories, locale: locale, themeMode: mode);
        expect(find.text(l10nFor(locale).allCategories), findsOneWidget);
        expect(find.byType(CategoryTile), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    for (final locale in ['en', 'ar', 'ckb']) {
      testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
        await pumpCatalogueApp(
          tester,
          initialPath: AppRoutes.categories,
          locale: locale,
          size: const Size(320, 900),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
        await _search(tester, 'xyz');
        expect(find.text(l10nFor(locale).noCategoriesMatch), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
