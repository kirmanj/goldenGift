import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/categories/presentation/providers/categories_providers.dart';
import 'package:golden_gift/features/categories/presentation/widgets/category_grid.dart';
import 'package:golden_gift/features/categories/presentation/widgets/coming_soon_category.dart';
import 'package:golden_gift/features/home/presentation/providers/home_providers.dart';
import 'package:golden_gift/features/home/presentation/widgets/discover_section.dart';
import 'package:golden_gift/features/home/presentation/widgets/home_sections.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/products/presentation/widgets/product_category_chips.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/features/product_details/data/product_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_fakes.dart';

import '../products/catalogue_test_harness.dart';

/// "Coming soon" categories (SRS §5.7a): the gate in the products list, the
/// page itself, the "Soon" pill on tiles / chips and Discover's inline card.

const _easter = CategoryModel(
  id: 'easter',
  title: LocalizedText('Easter Day', ar: 'عيد الفصح', ku: 'جەژنی ئیستەر'),
  sortOrder: 3,
  comingSoon: true,
  comingSoonNote: LocalizedText('Arriving before Easter', ar: 'تصل قبل عيد الفصح', ku: 'پێش جەژنی ئیستەر دەگات'),
);

/// Available itself, but under the coming-soon Easter.
const _eggs = CategoryModel(
  id: 'eggs',
  title: LocalizedText('Painted Eggs', ar: 'بيض ملوّن', ku: 'هێلکەی ڕەنگکراو'),
  sortOrder: 30,
  parentId: 'easter',
);

/// Flowers, Mugs, Easter (coming soon), Birthdays, … , Painted Eggs (inherits).
final _categories = [...testCategories.take(2), _easter, ...testCategories.skip(2), _eggs];

CatalogueData _data({List<CategoryModel>? categories}) => CatalogueData(
      homeCategories: () => Stream.value(categories ?? _categories),
      allCategories: () => Stream.value(categories ?? _categories),
    );

String _page(String id) => AppRoutes.productsFor(ProductQuery(categoryId: id));

/// Taps a Discover chip, scrolling the horizontal chip row to it first.
Future<void> _tapDiscoverChip(WidgetTester tester, String label) async {
  final row = find.descendant(of: find.byType(DiscoverSection), matching: find.byType(Scrollable)).first;
  final chip = find.descendant(of: find.byType(DiscoverSection), matching: find.widgetWithText(CategoryChip, label));
  await tester.scrollUntilVisible(chip, 80, scrollable: row);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Finder _otherTiles() =>
    find.descendant(of: find.byKey(const ValueKey('coming-soon-other-categories')), matching: find.byType(CategoryTile));

void main() {
  final en = l10nFor('en');

  group('helpers', () {
    test('comingSoonCategoryIn: itself, through a parent (note inherited), available, unknown', () {
      expect(comingSoonCategoryIn(_categories, 'easter')!.note.en, 'Arriving before Easter');
      final child = comingSoonCategoryIn(_categories, 'eggs')!;
      expect(child.category.id, 'eggs');
      expect(child.note, _easter.comingSoonNote, reason: 'no note of its own: the parent\'s');
      expect(comingSoonCategoryIn(_categories, 'mugs'), isNull);
      expect(comingSoonCategoryIn(_categories, 'nope'), isNull);
      expect(comingSoonCategoryIn(null, 'easter'), isNull);
      expect(comingSoonIdsIn(_categories), {'easter', 'eggs'});
      expect(availableCategoriesIn(_categories).map((c) => c.id), isNot(contains('easter')));
    });

    for (final (top, expected) in [
      ('easter', HomeQueries.forYou),
      ('mugs', const ProductQuery(categoryId: 'mugs', sort: ProductSort.popular)),
    ]) {
      test('For you with most-viewed "$top" → $expected', () async {
        SharedPreferences.setMockInitialValues({ViewHistory.key: '{"$top": 5, "flowers": 1}'});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith((ref) => Stream.value(FakeUser(uid: 'u1'))),
          homeCategoriesProvider.overrideWith((ref) => Stream.value(_categories)),
        ]);
        addTearDown(container.dispose);
        container.listen(forYouQueryProvider, (_, __) {});
        await container.read(authStateProvider.future);
        await container.read(homeCategoriesProvider.future);
        expect(container.read(forYouQueryProvider), expected);
      });
    }
  });

  group('gate in the products list', () {
    testWidgets('a coming-soon category shows the page, never queries its products', (tester) async {
      final data = _data();
      await pumpCatalogueApp(tester, initialPath: _page('easter'), data: data, disableAnimations: true);

      expect(find.byType(ComingSoonCategoryPage), findsOneWidget);
      expect(find.text('Easter Day'), findsOneWidget);
      expect(find.text(en.comingSoon.toUpperCase()), findsOneWidget);
      expect(find.text(en.comingSoonTagline), findsOneWidget);
      expect(find.text(en.comingSoonMessage('Easter Day')), findsOneWidget);
      expect(find.text('Arriving before Easter'), findsOneWidget);
      expect(find.byType(GGSearchBar), findsNothing);
      expect(data.repository.queries.where((q) => q.categoryId == 'easter'), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a subcategory of a coming-soon parent: its own name, the parent\'s note', (tester) async {
      final data = _data();
      await pumpCatalogueApp(tester, initialPath: _page('eggs'), data: data, disableAnimations: true);
      expect(find.byType(ComingSoonCategoryPage), findsOneWidget);
      expect(find.text('Painted Eggs'), findsOneWidget);
      expect(find.text(en.comingSoonMessage('Painted Eggs')), findsOneWidget);
      expect(find.text('Arriving before Easter'), findsOneWidget);
      expect(data.repository.queries, isEmpty);
    });

    testWidgets('no note → no quote line', (tester) async {
      final plain = [for (final c in _categories) c.id == 'easter' ? c.copyWith(comingSoonNote: LocalizedText.empty) : c];
      await pumpCatalogueApp(tester, initialPath: _page('easter'), data: _data(categories: plain), disableAnimations: true);
      expect(find.byKey(const ValueKey('coming-soon-note')), findsNothing);
    });

    testWidgets('an available category still lists its products', (tester) async {
      final data = _data();
      await pumpCatalogueApp(tester, initialPath: _page('mugs'), data: data);
      expect(find.byType(ComingSoonCategoryPage), findsNothing);
      expect(data.repository.queries, [const ProductQuery(categoryId: 'mugs')]);
      expect(find.text('Gift mugs-0'), findsOneWidget);
    });

    testWidgets('while categories load, a category list waits (skeleton, no query)', (tester) async {
      final data = CatalogueData(allCategories: pending);
      await pumpCatalogueApp(tester, initialPath: _page('mugs'), data: data, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(data.repository.queries, isEmpty);
      expect(find.byType(SkeletonLoader), findsWidgets);
      expect(find.byType(ComingSoonCategoryPage), findsNothing);
    });

    testWidgets('if the categories fail, the products load anyway', (tester) async {
      final data = CatalogueData(allCategories: () => Stream.error(Exception('offline')));
      await pumpCatalogueApp(tester, initialPath: _page('mugs'), data: data);
      expect(data.repository.queries, [const ProductQuery(categoryId: 'mugs')]);
    });

    testWidgets('a deep link has nothing to pop: Back opens Home', (tester) async {
      final router = await pumpCatalogueApp(tester, initialPath: _page('easter'), data: _data(), disableAnimations: true);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.mainTab(0));
    });

    testWidgets('from a Home tile (with the Soon pill): Back pops to Home', (tester) async {
      final router = await pumpCatalogueApp(tester, data: _data(), size: const Size(390, 6000), disableAnimations: true);
      final tile = find.descendant(of: find.byType(HomeCategoryGrid), matching: find.widgetWithText(CategoryTile, 'Easter Day'));
      expect(tester.widget<CategoryTile>(tile).comingSoon, isTrue);
      expect(find.descendant(of: tile, matching: find.byType(SoonPill)), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text(en.categorySoonBadge)), findsOneWidget);
      expect(
        tester.widget<CategoryTile>(find.descendant(of: find.byType(HomeCategoryGrid), matching: find.widgetWithText(CategoryTile, 'Mugs'))).comingSoon,
        isFalse,
      );

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(locationOf(router), _page('easter'));
      expect(find.byType(ComingSoonCategoryPage), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ComingSoonCategoryPage), findsNothing);
      expect(find.byType(HomeCategoryGrid), findsOneWidget);
    });

    testWidgets('a coming-soon chip of the products list: Back returns to that list', (tester) async {
      final data = _data();
      await pumpCatalogueApp(tester, initialPath: _page('mugs'), data: data, disableAnimations: true);
      final chip = find.descendant(
          of: find.byType(ProductCategoryChips), matching: find.widgetWithText(CategoryChip, 'Easter Day'));
      expect(tester.widget<CategoryChip>(chip).comingSoon, isTrue);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(ComingSoonCategoryPage), findsOneWidget);
      expect(data.repository.queries.where((q) => q.categoryId == 'easter'), isEmpty);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ComingSoonCategoryPage), findsNothing);
      expect(find.text('Gift mugs-0'), findsOneWidget);
      expect(
        tester.widget<CategoryChip>(
            find.descendant(of: find.byType(ProductCategoryChips), matching: find.widgetWithText(CategoryChip, 'Mugs'))),
        isA<CategoryChip>().having((c) => c.selected, 'selected', isTrue),
      );
    });

    testWidgets('All Categories shows the pill too and opens the page', (tester) async {
      final router = await pumpCatalogueApp(tester,
          initialPath: AppRoutes.categories, data: _data(), size: const Size(390, 1600), disableAnimations: true);
      final grid = find.byType(CategoryGrid);
      bool soon(String label) =>
          tester.widget<CategoryTile>(find.descendant(of: grid, matching: find.widgetWithText(CategoryTile, label))).comingSoon;
      expect(soon('Easter Day'), isTrue);
      expect(soon('Painted Eggs'), isTrue, reason: 'inherits from its parent');
      expect(soon('Flowers'), isFalse);

      await tester.tap(find.widgetWithText(CategoryTile, 'Easter Day'));
      await tester.pumpAndSettle();
      expect(locationOf(router), _page('easter'));
      expect(find.byType(ComingSoonCategoryPage), findsOneWidget);
    });
  });

  group('the page', () {
    testWidgets('"Explore other categories": available ones only; a tile opens it in place', (tester) async {
      final data = _data();
      final router = await pumpCatalogueApp(tester,
          initialPath: _page('easter'), data: data, size: const Size(390, 1600), disableAnimations: true);
      // Collect every tile of the (lazily built) row by scrolling it to the end.
      final labels = <String?>{};
      final row = find.descendant(
          of: find.byKey(const ValueKey('coming-soon-other-categories')), matching: find.byType(Scrollable));
      final position = tester.state<ScrollableState>(row).position;
      while (true) {
        for (final t in tester.widgetList<CategoryTile>(_otherTiles())) {
          labels.add(t.label);
          expect(t.comingSoon, isFalse);
        }
        if (position.pixels >= position.maxScrollExtent) break;
        position.jumpTo((position.pixels + 200).clamp(0, position.maxScrollExtent));
        await tester.pump();
      }
      expect(labels, isNot(contains('Easter Day')));
      expect(labels, isNot(contains('Painted Eggs')));
      expect(labels, {for (final c in testCategories) c.title.en});
      position.jumpTo(0);
      await tester.pump();

      await tester.tap(find.descendant(of: _otherTiles(), matching: find.text('Mugs')));
      await tester.pumpAndSettle();
      expect(find.byType(ComingSoonCategoryPage), findsNothing);
      expect(data.repository.queries.last, const ProductQuery(categoryId: 'mugs'));
      expect(find.text('Gift mugs-0'), findsOneWidget);
      expect(locationOf(router), _page('easter'), reason: 'same screen, switched in place');
      expect(find.byType(GGSearchBar), findsOneWidget);
    });

    testWidgets('"Gifts you might love": Popular products with hearts; a card and View All navigate', (tester) async {
      final router = await pumpCatalogueApp(tester,
          initialPath: _page('easter'), data: _data(), size: const Size(390, 1800), disableAnimations: true);
      final row = find.byKey(const ValueKey('coming-soon-gifts'));
      expect(find.descendant(of: row, matching: find.byType(ProductCard)), findsWidgets);
      expect(find.descendant(of: row, matching: find.byType(WishlistHeart)), findsWidgets);

      await tester.tap(find.text('Gift pop0'));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.product('pop0'));
      router.pop();
      await tester.pumpAndSettle();

      final header = find.ancestor(of: find.text(en.comingSoonGiftsYouMightLove), matching: find.byType(SectionHeader));
      await tester.tap(find.descendant(of: header, matching: find.text(en.viewAll)));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.productsFor(HomeQueries.popular));
    });

    testWidgets('no popular products → the gifts row is hidden', (tester) async {
      final data = CatalogueData(
        homeCategories: () => Stream.value(_categories),
        allCategories: () => Stream.value(_categories),
        popular: () => Stream.value(const []),
      );
      await pumpCatalogueApp(tester, initialPath: _page('easter'), data: data, disableAnimations: true);
      expect(find.text(en.comingSoonGiftsYouMightLove), findsNothing);
    });

    testWidgets('CTAs: Explore all categories and Back to home', (tester) async {
      final router = await pumpCatalogueApp(tester,
          initialPath: _page('easter'), data: _data(), size: const Size(390, 1600), disableAnimations: true);
      await tester.tap(find.text(en.comingSoonExploreAll));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.categories);
      router.pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text(en.comingSoonBackHome));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.mainTab(0));
    });

    testWidgets('moves by default and stays still with reduced motion', (tester) async {
      await pumpCatalogueApp(tester, initialPath: _page('easter'), data: _data(), settle: false);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'the hero loops');
      await tester.pumpWidget(const SizedBox.shrink());

      await pumpCatalogueApp(tester, initialPath: _page('easter'), data: _data(), disableAnimations: true);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    for (final locale in ['en', 'ar', 'ckb']) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('renders in $locale / ${mode.name} (RTL mirrored)', (tester) async {
          await pumpCatalogueApp(tester,
              initialPath: _page('easter'),
              data: _data(),
              locale: locale,
              themeMode: mode,
              size: const Size(390, 1800),
              disableAnimations: true);
          final l10n = l10nFor(locale);
          final name = _easter.title.resolve(locale);
          expect(find.text(name), findsOneWidget);
          expect(find.text(l10n.comingSoonMessage(name)), findsOneWidget);
          expect(find.text(_easter.comingSoonNote.resolve(locale)), findsOneWidget);
          expect(find.text(l10n.comingSoonExploreAll), findsOneWidget);
          expect(tester.takeException(), isNull);
          final back = tester.getCenter(find.byIcon(Icons.arrow_back_ios_new_rounded));
          expect(back.dx, locale == 'en' ? lessThan(195) : greaterThan(195), reason: 'back sits on the start side');
        });
      }

      testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
        await pumpCatalogueApp(tester,
            initialPath: _page('easter'),
            data: _data(),
            locale: locale,
            size: const Size(320, 640),
            textScale: 1.3,
            disableAnimations: true);
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 6; i++) {
          await tester.drag(scrollable, const Offset(0, -400));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Discover on Home', () {
    testWidgets('a coming-soon chip shows the inline card instead of the grid; Show all gifts goes back to All',
        (tester) async {
      final data = _data();
      await pumpCatalogueApp(tester, data: data, size: const Size(390, 6000));
      final chip = find.descendant(
          of: find.byType(DiscoverSection), matching: find.widgetWithText(CategoryChip, 'Easter Day'));
      await _tapDiscoverChip(tester, 'Easter Day');
      expect(tester.widget<CategoryChip>(chip).comingSoon, isTrue);
      expect(tester.widget<CategoryChip>(chip).selected, isTrue);

      expect(find.byType(ComingSoonInlineCard), findsOneWidget);
      expect(find.descendant(of: find.byType(ComingSoonInlineCard), matching: find.text('Easter Day')), findsOneWidget);
      expect(find.text(en.comingSoonMessage('Easter Day')), findsOneWidget);
      expect(find.text('Arriving before Easter'), findsOneWidget);
      expect(data.repository.queries.where((q) => q.categoryId == 'easter'), isEmpty, reason: 'no product query');
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'the inline hero does not loop');

      await tester.tap(find.text(en.comingSoonShowAllGifts));
      await tester.pumpAndSettle();
      expect(find.byType(ComingSoonInlineCard), findsNothing);
      expect(tester.widget<DiscoverSection>(find.byType(DiscoverSection)).categoryId, isNull, reason: 'All');
      expect(find.text('Gift all-0'), findsOneWidget);
    });

    testWidgets('inline card: Explore all categories opens All Categories', (tester) async {
      final router = await pumpCatalogueApp(tester, data: _data(), size: const Size(390, 6000));
      await _tapDiscoverChip(tester, 'Easter Day');
      await tester.ensureVisible(find.text(en.comingSoonExploreAll));
      await tester.tap(find.text(en.comingSoonExploreAll));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.categories);
    });

    for (final locale in ['en', 'ar', 'ckb']) {
      testWidgets('inline card: no overflow at 320 px with 1.3× text ($locale, dark)', (tester) async {
        await pumpCatalogueApp(tester,
            data: _data(), locale: locale, themeMode: ThemeMode.dark, size: const Size(320, 4000), textScale: 1.3);
        await _tapDiscoverChip(tester, _easter.title.resolve(locale));
        expect(find.byType(ComingSoonInlineCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
