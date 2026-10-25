import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/models/product_model.dart';

import 'test_app.dart';

/// A 2-column grid exactly as screens build it, at a phone-like width.
Widget _grid(List<ProductModel> products, {Set<String> wishlisted = const {}}) {
  return LayoutBuilder(
    builder: (context, c) => GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: ProductCard.gridDelegate(context, c.maxWidth),
      itemBuilder: (_, i) => ProductCard(
        product: products[i],
        isWishlisted: wishlisted.contains(products[i].id),
        onTap: () {},
        onWishlistChanged: (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows FeaturedBadge, 13% DiscountBadge and formatted prices', (tester) async {
    await tester.pumpWidget(testApp(
      ProductCard(product: discountedProduct(), onWishlistChanged: (_) {}),
      width: 200,
    ));

    expect(find.byType(FeaturedBadge), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
    expect(find.byType(DiscountBadge), findsOneWidget);
    expect(find.text('13%'), findsOneWidget);
    expect(find.text('35,000 IQD'), findsOneWidget);
    expect(find.text('40,000 IQD'), findsOneWidget);
    expect(find.text('Floral Candle Chest With A Long Name That Wraps'), findsOneWidget);
    expect(find.byType(WishlistHeart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows at most 5 colour dots from the first colour-swatch group', (tester) async {
    await tester.pumpWidget(testApp(ProductCard(product: discountedProduct()), width: 200));

    final swatchColors =
        swatchHexes.map((h) => Color(int.parse('FF${h.substring(1)}', radix: 16))).toSet();
    final dots = find.byWidgetPredicate((w) {
      if (w is! Container || w.decoration is! BoxDecoration) return false;
      final d = w.decoration! as BoxDecoration;
      return d.shape == BoxShape.circle && swatchColors.contains(d.color);
    });
    expect(dots, findsNWidgets(5));
  });

  testWidgets('plain product has no badges or old price; heart hidden without callback',
      (tester) async {
    await tester.pumpWidget(testApp(ProductCard(product: plainProduct()), width: 200));

    expect(find.text('29,000 IQD'), findsOneWidget);
    expect(find.byType(FeaturedBadge), findsNothing);
    expect(find.byType(DiscountBadge), findsNothing);
    expect(find.byType(WishlistHeart), findsNothing);
  });

  testWidgets('out-of-stock product shows the localized overlay label', (tester) async {
    await tester.pumpWidget(testApp(ProductCard(product: outOfStockProduct()), width: 200));
    expect(find.text('Out of stock'), findsOneWidget);
  });

  testWidgets('tapping the heart reports the new wishlist state; tapping the card opens',
      (tester) async {
    bool? wishlisted;
    var opened = 0;
    await tester.pumpWidget(testApp(
      ProductCard(
        product: plainProduct(),
        onTap: () => opened++,
        onWishlistChanged: (v) => wishlisted = v,
      ),
      width: 200,
    ));

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    expect(wishlisted, isTrue);
    expect(opened, 0, reason: 'heart tap must not open the product');

    await tester.tap(find.text('Red Roses Bouquet'));
    expect(opened, 1);
  });

  for (final (locale, dark) in [
    (const Locale('en'), true),
    (const Locale('ar'), false),
    (const Locale('ar'), true),
    (const Locale('ckb'), false),
    (const Locale('ckb'), true),
  ]) {
    testWidgets('grid renders without overflow: ${locale.languageCode} ${dark ? 'dark' : 'light'}',
        (tester) async {
      await tester.pumpWidget(testApp(
        _grid([discountedProduct(), plainProduct(), outOfStockProduct()], wishlisted: {'p2'}),
        locale: locale,
        dark: dark,
        width: 340,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(GridView));
      expect(Theme.of(context).brightness, dark ? Brightness.dark : Brightness.light);
      expect(find.text('35,000 IQD'), findsOneWidget);
    });
  }

  testWidgets('RTL: Featured badge is on the right (start), heart on the left (end)',
      (tester) async {
    await tester.pumpWidget(testApp(
      ProductCard(product: discountedProduct(), onWishlistChanged: (_) {}),
      locale: const Locale('ar'),
      width: 200,
    ));

    final context = tester.element(find.byType(ProductCard));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(find.text('صندوق شموع الورود باسم طويل جداً يلتف على سطرين'), findsOneWidget);
    final badgeX = tester.getCenter(find.byType(FeaturedBadge)).dx;
    final heartX = tester.getCenter(find.byType(WishlistHeart)).dx;
    expect(badgeX, greaterThan(heartX));
  });

  testWidgets('narrow grid at 1.3x text scale still fits (prices wrap, no overflow)',
      (tester) async {
    await tester.pumpWidget(testApp(
      _grid([discountedProduct(), plainProduct()]),
      width: 300,
      textScale: 1.3,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
