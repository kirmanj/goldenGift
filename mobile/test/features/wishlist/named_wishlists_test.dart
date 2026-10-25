import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/wishlist/data/wishlist_repository.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

import '../../helpers/auth_fakes.dart';
import '../product_details/shop_test_harness.dart';

final _en = l10nFor('en');

ProductModel _p(String id, String title, int price) => ProductModel(
      id: id,
      title: LocalizedText(title, ar: '$title (ar)', ku: '$title (ku)'),
      storeId: 's1',
      price: price,
    );

final _mug = _p('mug', 'Photo Mug', 12000);
final _frame = _p('frame', 'Magnetic Frame', 35000);

/// wishlists/u1 with a named list "Mum" (id l1) and both gifts in the default list.
Future<FakeFirebaseFirestore> _withLists({bool mugInMum = false}) async {
  final db = FakeFirebaseFirestore();
  await db.doc('wishlists/u1').set({
    'lists': [
      {'id': 'l1', 'name': 'Mum', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1))},
    ],
  });
  final repo = WishlistRepository(db);
  await repo.add('u1', _frame);
  await repo.add('u1', _mug, listId: mugInMum ? 'l1' : WishlistRepository.defaultList);
  return db;
}

Future<String?> _listOf(FakeFirebaseFirestore db, String productId) async =>
    (await db.doc('wishlists/u1/items/$productId').get()).data()?['listId'] as String?;

/// The stored lists (default first), read once (no snapshot listener).
Future<List<WishlistList>> _lists(FakeFirebaseFirestore db) async =>
    WishlistRepository.withDefault((await db.doc('wishlists/u1').get()).data());

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps a list chip, scrolling the horizontal chip row to it first.
Future<void> _chip(WidgetTester tester, String id) async {
  final chip = find.byKey(ValueKey('wishlist-chip-$id'));
  await tester.scrollUntilVisible(chip, 120,
      scrollable: find.descendant(of: find.byKey(const ValueKey('wishlist-chips')), matching: find.byType(Scrollable)));
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Finder get _nameField =>
    find.descendant(of: find.byKey(const ValueKey('wishlist-list-name')), matching: find.byType(TextField));

void main() {
  group('repository (SRS §5.15 named lists)', () {
    test('the default list always comes first and is implicit', () async {
      final db = FakeFirebaseFirestore();
      final repo = WishlistRepository(db);
      expect((await _lists(db)).single.isDefault, isTrue);

      final b = await repo.createList('u1', '  Eid   gifts ');
      final a = await repo.createList('u1', 'x' * 60);
      final lists = await _lists(db);
      expect(lists.map((l) => l.id), [WishlistRepository.defaultList, b, a]);
      expect(lists[1].name, 'Eid gifts');
      expect(lists[2].name.length, WishlistRepository.maxListName);
      expect(() => repo.createList('u1', '   '), throwsA(isA<WishlistListException>()));
    });

    test('rename a named list; the default list can be neither renamed nor deleted', () async {
      final db = FakeFirebaseFirestore();
      final repo = WishlistRepository(db);
      final id = await repo.createList('u1', 'Mum');
      await repo.renameList('u1', id, 'Mother');
      expect((await _lists(db)).last.name, 'Mother');
      expect(() => repo.renameList('u1', 'default', 'x'), throwsA(isA<WishlistListException>()));
      expect(() => repo.deleteList('u1', 'default'), throwsA(isA<WishlistListException>()));
    });

    test('deleting a list moves its gifts to the default list', () async {
      final db = await _withLists(mugInMum: true);
      final repo = WishlistRepository(db);
      await repo.deleteList('u1', 'l1');
      expect(await _listOf(db, 'mug'), 'default');
      expect(await _listOf(db, 'frame'), 'default');
      expect((await _lists(db)).single.isDefault, isTrue);
    });

    test('save to a list and move between lists (a gift is in one list)', () async {
      final db = FakeFirebaseFirestore();
      final repo = WishlistRepository(db);
      await repo.add('u1', _mug, listId: 'l1');
      expect(await _listOf(db, 'mug'), 'l1');
      await repo.moveItem('u1', 'mug', 'default');
      expect(await _listOf(db, 'mug'), 'default');
      expect((await repo.watch('u1').first).single.listId, 'default');
    });

    test('stored entries named "default" or without an id are ignored', () {
      final lists = WishlistRepository.withDefault({
        'lists': [
          {'id': 'b', 'name': 'B', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2))},
          {'id': 'default', 'name': 'Hijack'},
          {'name': 'No id'},
          {'id': 'a', 'name': 'A', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1))},
        ],
      });
      expect(lists.map((l) => l.id), ['default', 'a', 'b']);
    });
  });

  group('My Wishlists screen', () {
    testWidgets('default list chip first + New list; no list menu or move buttons with one list', (tester) async {
      final db = FakeFirebaseFirestore();
      await WishlistRepository(db).add('u1', _mug);
      await pumpShop(tester, initialPath: AppRoutes.wishlists, user: FakeUser(), firestore: db);
      expect(find.byKey(const ValueKey('wishlist-chip-default')), findsOneWidget);
      expect(find.text(_en.wishlistDefaultList), findsOneWidget);
      expect(find.byKey(const ValueKey('wishlist-chip-new')), findsOneWidget);
      expect(find.byKey(const ValueKey('wishlist-list-menu')), findsNothing);
      expect(find.byKey(const ValueKey('wishlist-move-mug')), findsNothing);
    });

    testWidgets('New list → named, selected and empty; it gets the ⋯ menu', (tester) async {
      final db = FakeFirebaseFirestore();
      await WishlistRepository(db).add('u1', _mug);
      await pumpShop(tester, initialPath: AppRoutes.wishlists, user: FakeUser(), firestore: db);
      await _tap(tester, find.byKey(const ValueKey('wishlist-chip-new')));
      await _tap(tester, find.byKey(const ValueKey('wishlist-list-name-save')));
      expect(find.text(_en.errorRequired), findsOneWidget);
      await tester.enterText(_nameField, "Mum's birthday");
      await _tap(tester, find.byKey(const ValueKey('wishlist-list-name-save')));

      final lists = await _lists(db);
      expect(lists.last.name, "Mum's birthday");
      final chip = tester.widget<CategoryChip>(find.byKey(ValueKey('wishlist-chip-${lists.last.id}')));
      expect(chip.selected, isTrue);
      expect(find.byKey(const ValueKey('wishlist-list-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('wishlist-list-menu')), findsOneWidget);
    });

    testWidgets('chips filter by list; Move to… moves a gift', (tester) async {
      final db = await _withLists();
      await pumpShop(tester, initialPath: AppRoutes.wishlists, user: FakeUser(), firestore: db);
      expect(find.byType(ProductCard), findsNWidgets(2));
      await _tap(tester, find.byKey(const ValueKey('wishlist-move-mug')));
      expect(find.text(_en.wishlistMoveTo), findsWidgets);
      await _tap(tester, find.byKey(const ValueKey('wishlist-pick-l1')));
      expect(await _listOf(db, 'mug'), 'l1');
      expect(find.text(_en.wishlistMovedTo('Mum')), findsOneWidget);
      expect(find.text('Photo Mug'), findsNothing); // left the default list
      await _chip(tester, 'l1');
      expect(find.text('Photo Mug'), findsOneWidget);
      expect(find.text('Magnetic Frame'), findsNothing);
    });

    testWidgets('long-press on a card also offers Move to…', (tester) async {
      final db = await _withLists();
      await pumpShop(tester, initialPath: AppRoutes.wishlists, user: FakeUser(), firestore: db);
      await tester.longPress(find.text('Magnetic Frame'));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('wishlist-pick-l1')));
      expect(await _listOf(db, 'frame'), 'l1');
    });

    testWidgets('rename and delete a named list (its gifts go back to Favourites)', (tester) async {
      final db = await _withLists(mugInMum: true);
      await pumpShop(tester, initialPath: AppRoutes.wishlists, user: FakeUser(), firestore: db);
      await _chip(tester, 'l1');

      await _tap(tester, find.byKey(const ValueKey('wishlist-list-menu')));
      await _tap(tester, find.byKey(const ValueKey('wishlist-rename')));
      expect(tester.widget<TextField>(_nameField).controller!.text, 'Mum');
      await tester.enterText(_nameField, 'Mother');
      await _tap(tester, find.byKey(const ValueKey('wishlist-list-name-save')));
      expect(find.text('Mother'), findsOneWidget);
      expect((await _lists(db)).last.name, 'Mother');

      await _tap(tester, find.byKey(const ValueKey('wishlist-list-menu')));
      await _tap(tester, find.byKey(const ValueKey('wishlist-delete')));
      expect(find.text(_en.wishlistDeleteListConfirm('Mother', _en.wishlistDefaultList)), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('wishlist-delete-confirm')));
      expect(await _listOf(db, 'mug'), 'default');
      expect(find.byKey(const ValueKey('wishlist-chip-l1')), findsNothing);
      expect(find.text('Photo Mug'), findsOneWidget); // back under Favourites (selected)
      expect(find.byKey(const ValueKey('wishlist-list-menu')), findsNothing); // default is protected
    });

    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light)]) {
      testWidgets('lists render in $locale (${mode.name})', (tester) async {
        final db = await _withLists();
        await pumpShop(
          tester,
          initialPath: AppRoutes.wishlists,
          user: FakeUser(),
          firestore: db,
          locale: locale,
          themeMode: mode,
        );
        expect(find.text(l10nFor(locale).wishlistDefaultList), findsOneWidget);
        expect(find.text('Mum'), findsOneWidget);
        expect(Directionality.of(tester.element(find.byKey(const ValueKey('wishlist-chip-l1')))), TextDirection.rtl);
        expect(tester.takeException(), isNull);
      });
    }

    for (final locale in ['en', 'ar', 'ckb']) {
      testWidgets('no overflow at 320 px with 1.3× text, with move buttons ($locale)', (tester) async {
        final db = await _withLists();
        await pumpShop(
          tester,
          initialPath: AppRoutes.wishlists,
          user: FakeUser(),
          firestore: db,
          locale: locale,
          size: const Size(320, 1600),
          textScale: 1.3,
        );
        expect(find.byKey(const ValueKey('wishlist-move-mug')), findsOneWidget);
        await _chip(tester, 'l1');
        expect(find.byKey(const ValueKey('wishlist-list-empty')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Product Details heart', () {
    final path = AppRoutes.product('mug');

    testWidgets('a plain tap still saves to the default list', (tester) async {
      final db = FakeFirebaseFirestore();
      await pumpShop(tester, initialPath: path, product: _mug, user: FakeUser(), firestore: db);
      await tester.tap(find.byType(WishlistHeart));
      await tester.pumpAndSettle();
      expect(await _listOf(db, 'mug'), 'default');
      // No named lists → no "Save to…" prompt.
      expect(find.text(_en.wishlistSaveTo), findsNothing);
    });

    testWidgets('with named lists the save offers "Save to…"', (tester) async {
      final db = await _withLists();
      await WishlistRepository(db).remove('u1', 'mug');
      await pumpShop(tester, initialPath: path, product: _mug, user: FakeUser(), firestore: db);
      await tester.tap(find.byType(WishlistHeart));
      await tester.pumpAndSettle();
      expect(await _listOf(db, 'mug'), 'default');
      expect(find.text(_en.wishlistSavedTo(_en.wishlistDefaultList)), findsOneWidget);
      await tester.tap(find.text(_en.wishlistSaveTo));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('wishlist-pick-l1')));
      expect(await _listOf(db, 'mug'), 'l1');
    });

    testWidgets('long-press → choose a list, or create one there', (tester) async {
      final db = await _withLists();
      await WishlistRepository(db).remove('u1', 'mug');
      await pumpShop(tester, initialPath: path, product: _mug, user: FakeUser(), firestore: db);
      await tester.longPress(find.byKey(const ValueKey('heart-save-to')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wishlist-pick-default')), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('wishlist-pick-new')));
      await tester.enterText(_nameField, 'Graduation');
      await _tap(tester, find.byKey(const ValueKey('wishlist-list-name-save')));
      final lists = await _lists(db);
      expect(lists.last.name, 'Graduation');
      expect(await _listOf(db, 'mug'), lists.last.id);
      expect(find.text(_en.wishlistSavedTo('Graduation')), findsOneWidget);
    });

    testWidgets('guests who long-press are asked to sign in', (tester) async {
      await pumpShop(tester, initialPath: path, product: _mug);
      await tester.longPress(find.byKey(const ValueKey('heart-save-to')));
      await tester.pumpAndSettle();
      expect(find.text(_en.signInToContinue), findsOneWidget);
      expect(find.byKey(const ValueKey('wishlist-pick-default')), findsNothing);
    });
  });
}
