import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/widgets/widgets.dart';

import 'test_app.dart';

void main() {
  testWidgets('formats current + old price with CurrencyFormatter and shows the badge',
      (tester) async {
    await tester.pumpWidget(
      testApp(const PriceText(price: 35000, oldPrice: 40000, discountPercent: 13)),
    );

    expect(find.text('35,000 IQD'), findsOneWidget);
    expect(find.text('40,000 IQD'), findsOneWidget);
    expect(find.text('13%'), findsOneWidget);
    final old = tester.widget<Text>(find.text('40,000 IQD'));
    expect(old.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('price only: no old price, no badge', (tester) async {
    await tester.pumpWidget(testApp(const PriceText(price: 1250000)));

    expect(find.text('1,250,000 IQD'), findsOneWidget);
    expect(find.byType(DiscountBadge), findsNothing);
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('old price not greater than price is ignored', (tester) async {
    await tester.pumpWidget(testApp(const PriceText(price: 20000, oldPrice: 20000)));

    expect(find.text('20,000 IQD'), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('fromProduct derives old price and the rounded percentage', (tester) async {
    await tester.pumpWidget(testApp(PriceText.fromProduct(discountedProduct())));

    expect(find.text('35,000 IQD'), findsOneWidget);
    expect(find.text('40,000 IQD'), findsOneWidget);
    expect(find.text('13%'), findsOneWidget);
  });

  testWidgets('large size is 26 px; small is 16 px', (tester) async {
    await tester.pumpWidget(testApp(const Column(
      children: [
        PriceText(price: 40000, size: PriceTextSize.large),
        PriceText(price: 5000),
      ],
    )));

    expect(tester.widget<Text>(find.text('40,000 IQD')).style?.fontSize, 26);
    expect(tester.widget<Text>(find.text('5,000 IQD')).style?.fontSize, 16);
  });

  testWidgets('wraps instead of overflowing in a narrow card', (tester) async {
    await tester.pumpWidget(testApp(
      const PriceText(price: 1250000, oldPrice: 1500000, discountPercent: 17),
      width: 120,
    ));

    expect(tester.takeException(), isNull);
    final current = tester.getTopLeft(find.text('1,250,000 IQD'));
    final badge = tester.getTopLeft(find.byType(DiscountBadge));
    expect(badge.dy, greaterThan(current.dy), reason: 'badge wraps to a second line');
  });

  testWidgets('DiscountBadge renders nothing for 0%', (tester) async {
    await tester.pumpWidget(testApp(const DiscountBadge(percent: 0)));
    expect(find.byType(Text), findsNothing);
  });
}
