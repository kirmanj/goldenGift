import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/product_details/presentation/screens/product_details_screen.dart';
import 'package:golden_gift/features/wishlist/data/wishlist_repository.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

import '../../helpers/auth_fakes.dart';
import '../product_details/shop_test_harness.dart';

final en = l10nFor('en');

ProductModel _p(String id, String title, int price) => ProductModel(
      id: id,
      title: LocalizedText(title, ar: '$title (ar)', ku: '$title (ku)'),
      storeId: 's1',
      price: price,
    );

/// A Firestore with `wishlists/u1/items/*` for [products] (newest last).
Future<FakeFirebaseFirestore> _savedDb(List<ProductModel> products) async {
  final db = FakeFirebaseFirestore();
  final repo = WishlistRepository(db);
  for (final p in products) {
    await repo.add('u1', p);
  }
  return db;
}

void main() {
  testWidgets('guests see a sign-in card', (tester) async {
    await pumpShop(tester, initialPath: AppRoutes.wishlists);
    expect(find.text(en.myWishlists), findsOneWidget);
    expect(find.text(en.signInToContinue), findsOneWidget);
    expect(find.byType(ProductCard), findsNothing);
    await tester.tap(find.text(en.signIn));
    await tester.pumpAndSettle();
    expect(find.text(AppRoutes.signIn), findsOneWidget);
  });

  testWidgets('saved gifts show as product cards; a tap opens Product Details', (tester) async {
    final db = await _savedDb([_p('mug', 'Photo Mug', 12000), _p('frame', 'Magnetic Frame', 35000)]);
    await pumpShop(
      tester,
      initialPath: AppRoutes.wishlists,
      user: FakeUser(),
      firestore: db,
      product: _p('mug', 'Photo Mug', 12000),
    );
    expect(find.byType(ProductCard), findsNWidgets(2));
    expect(find.text('Photo Mug'), findsOneWidget);
    expect(find.text('35,000 IQD'), findsOneWidget);
    final hearts = tester.widgetList<WishlistHeart>(find.byType(WishlistHeart));
    expect(hearts.every((heart) => heart.isActive), isTrue);

    await tester.tap(find.text('Photo Mug'));
    await tester.pumpAndSettle();
    expect(tester.widget<ProductDetailsScreen>(find.byType(ProductDetailsScreen)).productId, 'mug');
    expect(find.text(en.productDetails), findsOneWidget);
  });

  testWidgets('the heart removes a gift; the last one leaves the empty state', (tester) async {
    final db = await _savedDb([_p('mug', 'Photo Mug', 12000), _p('frame', 'Magnetic Frame', 35000)]);
    await pumpShop(tester, initialPath: AppRoutes.wishlists, user: FakeUser(), firestore: db);

    final mugCard = find.ancestor(of: find.text('Photo Mug'), matching: find.byType(ProductCard));
    await tester.tap(find.descendant(of: mugCard, matching: find.byType(WishlistHeart)));
    await tester.pumpAndSettle();
    expect(find.text('Photo Mug'), findsNothing);
    expect((await db.doc('wishlists/u1/items/mug').get()).exists, isFalse);

    await tester.tap(find.byType(WishlistHeart));
    await tester.pumpAndSettle();
    expect(find.text(en.wishlistEmptyTitle), findsOneWidget);
    expect(find.text(en.wishlistEmptyBody), findsOneWidget);
    await tester.tap(find.text(en.startShopping));
    await tester.pumpAndSettle();
    expect(find.text('main tab 0'), findsOneWidget);
  });

  for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('en', ThemeMode.dark)]) {
    testWidgets('renders in $locale (${mode.name})', (tester) async {
      final db = await _savedDb([_p('mug', 'Photo Mug', 12000), _p('frame', 'Magnetic Frame', 35000)]);
      await pumpShop(
        tester,
        initialPath: AppRoutes.wishlists,
        user: FakeUser(),
        firestore: db,
        locale: locale,
        themeMode: mode,
      );
      expect(find.text(l10nFor(locale).myWishlists), findsOneWidget);
      expect(find.text(const LocalizedText('Photo Mug', ar: 'Photo Mug (ar)', ku: 'Photo Mug (ku)').resolve(locale)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in ['en', 'ar', 'ckb']) {
    testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
      final db = await _savedDb([
        _p('mug', 'Photo Mug With A Long Personalised Name', 1250000),
        _p('frame', 'Magnetic Frame', 35000),
        _p('rose', 'Roses', 29000),
      ]);
      await pumpShop(
        tester,
        initialPath: AppRoutes.wishlists,
        user: FakeUser(),
        firestore: db,
        locale: locale,
        size: const Size(320, 1600),
        textScale: 1.3,
      );
      expect(find.byType(ProductCard), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('guest card fits at 320 × 568 with 1.3× text ($locale)', (tester) async {
      await pumpShop(tester,
          initialPath: AppRoutes.wishlists, locale: locale, size: const Size(320, 568), textScale: 1.3);
      expect(find.text(l10nFor(locale).signInToContinue), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty state fits at 320 × 568 with 1.3× text ($locale)', (tester) async {
      await pumpShop(
        tester,
        initialPath: AppRoutes.wishlists,
        user: FakeUser(),
        locale: locale,
        size: const Size(320, 568),
        textScale: 1.3,
      );
      expect(find.text(l10nFor(locale).wishlistEmptyTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
