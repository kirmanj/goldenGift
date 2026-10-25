import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/products/presentation/widgets/product_category_chips.dart';
import 'package:golden_gift/features/products/presentation/widgets/product_filter_sheet.dart';

import 'catalogue_test_harness.dart';

Finder _chip(String label) =>
    find.descendant(of: find.byType(ProductCategoryChips), matching: find.widgetWithText(CategoryChip, label));

Finder _sheetChip(String label) =>
    find.descendant(of: find.byType(ProductFilterSheet), matching: find.widgetWithText(CategoryChip, label));

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.byTooltip(l10nFor('en').filter));
  await tester.pumpAndSettle();
  expect(find.byType(ProductFilterSheet), findsOneWidget);
}

String _path(ProductQuery q) => AppRoutes.productsFor(q);

void main() {
  final en = l10nFor('en');

  testWidgets('shows the first page as a 2-column grid; a card opens Product Details', (tester) async {
    final data = CatalogueData();
    final router = await pumpCatalogueApp(tester, initialPath: AppRoutes.products, data: data);

    expect(find.text(en.products), findsOneWidget);
    expect(data.repository.queries, [const ProductQuery()]);
    final first = tester.getTopLeft(find.text('Gift all-0'));
    final second = tester.getTopLeft(find.text('Gift all-1'));
    expect(first.dy, second.dy); // same row
    expect(second.dx, greaterThan(first.dx));

    await tester.tap(find.text('Gift all-1'));
    await tester.pumpAndSettle();
    expect(locationOf(router), AppRoutes.product('all-1'));
  });

  testWidgets('typing searches with the text after the 400 ms debounce', (tester) async {
    final data = CatalogueData();
    await pumpCatalogueApp(tester, initialPath: AppRoutes.products, data: data);

    await tester.enterText(find.byType(TextField), 'mug');
    await tester.pump(const Duration(milliseconds: 300));
    expect(data.repository.queries.where((q) => q.hasText), isEmpty);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(data.repository.queries.last, const ProductQuery(text: 'mug'));
  });

  testWidgets('initial query: text in the field, chip selected, search focused', (tester) async {
    final data = CatalogueData();
    await pumpCatalogueApp(
      tester,
      initialPath: AppRoutes.productsFor(const ProductQuery(text: 'rose', categoryId: 'frames'), focusSearch: true),
      data: data,
    );
    expect(data.repository.queries.single, const ProductQuery(text: 'rose', categoryId: 'frames'));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'rose');
    expect(tester.testTextInput.hasAnyClients, isTrue); // autofocus opened the keyboard
    expect(tester.widget<CategoryChip>(_chip('Frames')).selected, isTrue);
    expect(tester.widget<CategoryChip>(_chip(en.all)).selected, isFalse);
  });

  testWidgets('category chips set and clear categoryId', (tester) async {
    final data = CatalogueData();
    await pumpCatalogueApp(tester, initialPath: AppRoutes.products, data: data);

    await tester.tap(_chip('Mugs'));
    await tester.pumpAndSettle();
    expect(data.repository.queries.last, const ProductQuery(categoryId: 'mugs'));
    expect(tester.widget<CategoryChip>(_chip('Mugs')).selected, isTrue);
    expect(find.text('Gift mugs-0'), findsOneWidget);

    await tester.tap(_chip(en.all));
    await tester.pumpAndSettle();
    expect(data.repository.queries.last, const ProductQuery());
    expect(tester.widget<CategoryChip>(_chip(en.all)).selected, isTrue);
  });

  testWidgets('the filter sheet applies sort, price bands, same-day and city', (tester) async {
    final data = CatalogueData();
    await pumpCatalogueApp(tester, initialPath: AppRoutes.products, data: data, size: const Size(390, 1400));
    expect(tester.widget<GGSearchBar>(find.byType(GGSearchBar)).filterActive, isFalse);

    await _openFilters(tester);
    // Best match only makes sense for a text search.
    expect(_sheetChip(en.sortRelevance), findsNothing);
    expect(tester.widget<CategoryChip>(_sheetChip(en.sortNewest)).selected, isTrue);
    expect(tester.widget<CategoryChip>(_sheetChip(en.anyCity)).selected, isTrue);

    await tester.tap(_sheetChip(en.sortPriceLowHigh));
    await tester.tap(_sheetChip(en.priceUnder(CurrencyFormatter.format(25000))));
    await tester.tap(_sheetChip(en.priceBetween(CurrencyFormatter.format(50000), CurrencyFormatter.format(100000))));
    await tester.tap(find.text(en.sameDayOnly));
    await tester.tap(_sheetChip('Erbil'));
    await tester.pump();
    expect(tester.widget<CategoryChip>(_sheetChip(en.sortPriceLowHigh)).selected, isTrue);
    expect(tester.widget<CategoryChip>(_sheetChip(en.anyCity)).selected, isFalse);

    await tester.tap(find.text(en.showResults));
    await tester.pumpAndSettle();

    const expected = ProductQuery(
      sort: ProductSort.priceLowHigh,
      priceBands: {0, 2},
      sameDayOnly: true,
      cityId: 'erbil',
    );
    expect(find.byType(ProductFilterSheet), findsNothing);
    expect(data.repository.queries.last, expected);
    expect(tester.widget<GGSearchBar>(find.byType(GGSearchBar)).filterActive, isTrue);

    // Reopening shows the applied choices; Reset clears them (category/text kept).
    await _openFilters(tester);
    expect(tester.widget<CategoryChip>(_sheetChip('Erbil')).selected, isTrue);
    await tester.tap(find.text(en.resetFilters));
    await tester.tap(find.text(en.showResults));
    await tester.pumpAndSettle();
    expect(data.repository.queries.last, const ProductQuery());
  });

  testWidgets('the filter sheet applies one gift type (SRS §5.8a); Everyone clears it', (tester) async {
    final data = CatalogueData();
    await pumpCatalogueApp(tester, initialPath: AppRoutes.products, data: data, size: const Size(390, 1400));
    await _openFilters(tester);
    expect(tester.widget<CategoryChip>(_sheetChip(en.giftForEveryone)).selected, isTrue);

    await tester.tap(_sheetChip(en.giftForWomen));
    await tester.tap(_sheetChip(en.giftForCompanies));
    await tester.pump();
    expect(tester.widget<CategoryChip>(_sheetChip(en.giftForWomen)).selected, isFalse, reason: 'single choice');
    await tester.tap(find.text(en.showResults));
    await tester.pumpAndSettle();
    expect(data.repository.queries.last, const ProductQuery(giftFor: GiftAudience.companies));
    expect(tester.widget<GGSearchBar>(find.byType(GGSearchBar)).filterActive, isTrue);

    await _openFilters(tester);
    await tester.tap(_sheetChip(en.giftForEveryone));
    await tester.tap(find.text(en.showResults));
    await tester.pumpAndSettle();
    expect(data.repository.queries.last, const ProductQuery());
  });

  testWidgets('a `for=` deep link opens the list already filtered', (tester) async {
    final data = CatalogueData();
    await pumpCatalogueApp(tester, initialPath: '${AppRoutes.products}?for=men', data: data);
    expect(data.repository.queries.last, const ProductQuery(giftFor: GiftAudience.men));
  });

  testWidgets('dismissing the filter sheet changes nothing; on-sale toggle maps to discountOnly',
      (tester) async {
    final data = CatalogueData();
    await pumpCatalogueApp(tester, initialPath: AppRoutes.products, data: data, size: const Size(390, 1400));

    await _openFilters(tester);
    await tester.tap(find.text(en.onSaleOnly));
    await tester.tapAt(const Offset(10, 10)); // barrier
    await tester.pumpAndSettle();
    expect(data.repository.queries, [const ProductQuery()]);

    await _openFilters(tester);
    await tester.tap(find.text(en.onSaleOnly));
    await tester.tap(find.text(en.showResults));
    await tester.pumpAndSettle();
    expect(data.repository.queries.last, const ProductQuery(discountOnly: true));
  });

  testWidgets('relevance is offered for a text search and is its default', (tester) async {
    await pumpCatalogueApp(
      tester,
      initialPath: _path(const ProductQuery(text: 'mug')),
      size: const Size(390, 1400),
    );
    await _openFilters(tester);
    expect(tester.widget<CategoryChip>(_sheetChip(en.sortRelevance)).selected, isTrue);
  });

  test('price band labels use IQD amounts', () {
    expect(priceBandLabel(en, 0), en.priceUnder('25,000 IQD'));
    expect(priceBandLabel(en, 1), en.priceBetween('25,000 IQD', '50,000 IQD'));
    expect(priceBandLabel(en, 3), en.priceBetween('100,000 IQD', '200,000 IQD'));
    expect(priceBandLabel(en, 4), en.priceAndAbove('200,000 IQD'));
    // RTL isolates each amount so a range keeps its order.
    final ar = l10nFor('ar');
    expect(priceBandLabel(ar, 1, rtl: true), ar.priceBetween('\u206725,000 IQD\u2069', '\u206750,000 IQD\u2069'));
  });

  testWidgets('the search-fallback note shows when the backend ignored filters', (tester) async {
    final data = CatalogueData(repository: FakeProductRepository()..ignoredFilters = true);
    await pumpCatalogueApp(
      tester,
      initialPath: _path(const ProductQuery(text: 'mug', categoryId: 'flowers')),
      data: data,
    );
    expect(find.widgetWithText(InfoBanner, en.searchFallbackNote), findsOneWidget);
  });

  testWidgets('no fallback note or offline chip for a normal server page', (tester) async {
    await pumpCatalogueApp(tester, initialPath: AppRoutes.products);
    expect(find.text(en.searchFallbackNote), findsNothing);
    expect(find.byType(OfflineChip), findsNothing);
  });

  testWidgets('the offline chip shows for pages served from the cache', (tester) async {
    await pumpCatalogueApp(
      tester,
      initialPath: AppRoutes.products,
      data: CatalogueData(repository: FakeProductRepository()..fromCache = true),
    );
    expect(find.byType(OfflineChip), findsOneWidget);
  });

  testWidgets('empty results offer Reset filters when filters are active', (tester) async {
    final repo = FakeProductRepository()..totalFor = (q) => q.sameDayOnly ? 0 : 45;
    await pumpCatalogueApp(
      tester,
      initialPath: _path(const ProductQuery(categoryId: 'mugs', sameDayOnly: true)),
      data: CatalogueData(repository: repo),
    );
    expect(find.text(en.noProductsTitle), findsOneWidget);
    expect(find.text(en.noProductsBody), findsOneWidget);

    await tester.tap(find.text(en.resetFilters));
    await tester.pumpAndSettle();
    expect(repo.queries.last, const ProductQuery(categoryId: 'mugs'));
    expect(find.text(en.noProductsTitle), findsNothing);
    expect(find.text('Gift mugs-0'), findsOneWidget);
  });

  testWidgets('empty results without filters have no Reset button', (tester) async {
    await pumpCatalogueApp(
      tester,
      initialPath: _path(const ProductQuery(text: 'zzz', sort: ProductSort.popular)),
      data: CatalogueData(repository: FakeProductRepository(total: 0)),
    );
    expect(find.text(en.noProductsTitle), findsOneWidget);
    expect(find.text(en.resetFilters), findsNothing);
  });

  testWidgets('a failed first page shows the error state; Retry reloads', (tester) async {
    final repo = FakeProductRepository()..error = Exception('unavailable');
    await pumpCatalogueApp(tester, initialPath: AppRoutes.products, data: CatalogueData(repository: repo));
    expect(find.byType(ErrorState), findsOneWidget);

    repo.error = null;
    await tester.tap(find.text(en.retry));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('Gift all-0'), findsOneWidget);
    expect(repo.queries, [const ProductQuery(), const ProductQuery()]);
  });

  testWidgets('infinite scroll: the next page loads near the end; a failed page offers Retry',
      (tester) async {
    final repo = FakeProductRepository(total: 45)..loadMoreError = Exception('flaky');
    await pumpCatalogueApp(tester, initialPath: AppRoutes.products, data: CatalogueData(repository: repo));
    expect(repo.requests, hasLength(1));

    final scrollable = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable));
    final position = tester.state<ScrollableState>(scrollable.first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    position.jumpTo(position.maxScrollExtent); // the row appeared below the old end
    await tester.pumpAndSettle();
    expect(find.text(en.loadMoreFailed), findsOneWidget);

    repo.loadMoreError = null;
    await tester.tap(find.text(en.retry));
    await tester.pumpAndSettle();
    expect(find.text(en.loadMoreFailed), findsNothing);
    expect(repo.requests.map((r) => r.$2?.value), [null, 20, 20]);

    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(repo.requests.map((r) => r.$2?.value), [null, 20, 20, 40]);

    // No more pages: nothing else is requested.
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(repo.requests, hasLength(4));
    expect(find.text('Gift all-44'), findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads the first page', (tester) async {
    final repo = FakeProductRepository();
    await pumpCatalogueApp(tester, initialPath: AppRoutes.products, data: CatalogueData(repository: repo));
    await tester.fling(find.text('Gift all-0'), const Offset(0, 500), 1000);
    await tester.pumpAndSettle();
    expect(repo.requests.map((r) => r.$2), [null, null]);
  });

  testWidgets('the cart button opens the Cart tab', (tester) async {
    final router = await pumpCatalogueApp(tester, initialPath: AppRoutes.products);
    await tester.tap(find.byTooltip(en.cart));
    await tester.pumpAndSettle();
    expect(locationOf(router), AppRoutes.mainTab(1));
  });

  group('locales, themes, sizes', () {
    for (final (locale, mode) in [
      ('ar', ThemeMode.light),
      ('ckb', ThemeMode.light),
      ('en', ThemeMode.dark),
      ('ckb', ThemeMode.dark),
    ]) {
      testWidgets('renders with the filter sheet open in $locale / ${mode.name}', (tester) async {
        await pumpCatalogueApp(
          tester,
          initialPath: _path(const ProductQuery(categoryId: 'flowers')),
          locale: locale,
          themeMode: mode,
          data: CatalogueData(repository: FakeProductRepository()..fromCache = true),
        );
        final l10n = l10nFor(locale);
        expect(find.text(l10n.products), findsOneWidget);
        await tester.tap(find.byTooltip(l10n.filter));
        await tester.pumpAndSettle();
        expect(find.text(l10n.sameDayOnly), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final locale in ['en', 'ar', 'ckb']) {
      testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
        await pumpCatalogueApp(
          tester,
          initialPath: _path(const ProductQuery(text: 'mug', sameDayOnly: true)),
          locale: locale,
          size: const Size(320, 640),
          textScale: 1.3,
          data: CatalogueData(
            repository: FakeProductRepository()
              ..fromCache = true
              ..ignoredFilters = true,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip(l10nFor(locale).filter));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('empty state fits at 320 px with 1.3× text ($locale)', (tester) async {
        await pumpCatalogueApp(
          tester,
          initialPath: _path(const ProductQuery(sameDayOnly: true)),
          locale: locale,
          size: const Size(320, 480),
          textScale: 1.3,
          data: CatalogueData(repository: FakeProductRepository(total: 0)),
        );
        expect(find.text(l10nFor(locale).resetFilters), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
