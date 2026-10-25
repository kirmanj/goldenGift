import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/cart/presentation/providers/cart_controller.dart';
import 'package:golden_gift/features/cart/presentation/widgets/cart_line_tile.dart';
import 'package:golden_gift/features/cart/presentation/widgets/quantity_stepper.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

import '../../helpers/auth_fakes.dart';
import '../product_details/shop_test_harness.dart';

final en = l10nFor('en');

/// A configured frame line: Walnut (+5,000) · "Happy B-day" · a date · 2 photos.
CartItemModel _frameLine({String id = 'a', int qty = 2, int unit = 40000}) => CartItemModel(
      id: id,
      productId: 'frame',
      storeId: 's1',
      titleSnapshot: const LocalizedText('Magnetic Photo Frame', ar: 'إطار صور مغناطيسي', ku: 'چوارچێوەی وێنە'),
      unitPrice: unit,
      qty: qty,
      preparationDays: 4,
      selections: [
        const CartSelection(
          groupId: 'frame',
          type: OptionType.imageVariant,
          label: LocalizedText('Frame', ar: 'الإطار', ku: 'چوارچێوە'),
          valueId: 'walnut',
          valueLabel: LocalizedText('Walnut', ar: 'جوز', ku: 'گوێز'),
          priceDelta: 5000,
        ),
        const CartSelection(
          groupId: 'text1',
          type: OptionType.text,
          label: LocalizedText('Text', ar: 'النص', ku: 'دەق'),
          text: 'Happy B-day',
        ),
        CartSelection(
          groupId: 'date',
          type: OptionType.date,
          label: const LocalizedText('Date'),
          date: DateTime.utc(2026, 11, 2, 12),
        ),
        const CartSelection(
          groupId: 'photos',
          type: OptionType.photoUpload,
          label: LocalizedText('Photos'),
          urls: ['https://x/1.jpg', 'https://x/2.jpg'],
        ),
      ],
    );

CartItemModel _mugLine({String id = 'm', String store = 's2', int qty = 1}) => CartItemModel(
      id: id,
      productId: 'mug',
      storeId: store,
      titleSnapshot: const LocalizedText('Photo Mug', ar: 'كوب صور', ku: 'کوپی وێنە'),
      unitPrice: 12000,
      qty: qty,
    );

ProductModel _frame({int price = 35000}) => ProductModel(
      id: 'frame',
      title: const LocalizedText('Magnetic Photo Frame'),
      storeId: 's1',
      price: price,
      optionGroups: const [
        OptionGroup(id: 'frame', type: OptionType.imageVariant, label: LocalizedText('Frame'), values: [
          OptionValue(id: 'walnut', label: LocalizedText('Walnut'), priceDelta: 5000),
        ]),
      ],
    );

const _mug = ProductModel(id: 'mug', title: LocalizedText('Photo Mug'), storeId: 's2', price: 12000);

final _stores = {'s1': testStore('s1', 'Golden Home'), 's2': testStore('s2', 'Rose Shop')};

void main() {
  testWidgets('empty cart: lonely-cart state and Start Shopping goes Home', (tester) async {
    await pumpShop(tester, initialPath: '/cart', size: const Size(390, 844));
    expect(find.text(en.myCart), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text(en.emptyCartTitle), findsOneWidget);
    expect(find.text(en.emptyCartSubtitle), findsOneWidget);
    await tester.tap(find.text(en.startShopping));
    await tester.pumpAndSettle();
    expect(find.text('main tab 0'), findsOneWidget);
  });

  testWidgets('one store: no store header; the line shows its selection summary and totals', (tester) async {
    await pumpShop(
      tester,
      initialPath: '/cart',
      cartItems: [_frameLine()],
      cartProducts: {'frame': _frame()},
      stores: _stores,
    );
    expect(find.textContaining('Sold by'), findsNothing);
    expect(find.text('Magnetic Photo Frame'), findsOneWidget);
    expect(find.text('Frame: Walnut · Text: Happy B-day · Date: 02/11/2026 · 2 photos'), findsOneWidget);
    expect(find.text('40,000 IQD'), findsOneWidget); // unit price
    expect(find.text('80,000 IQD'), findsNWidgets(2)); // subtotal + total
    expect(find.text(en.deliveryCalculatedAtCheckout), findsOneWidget);
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNotNull);
  });

  testWidgets('lines are grouped by store with headers when the cart has several partners', (tester) async {
    await pumpShop(
      tester,
      initialPath: '/cart',
      cartItems: [_frameLine(), _mugLine(), _mugLine(id: 'm2', store: 's1')],
      cartProducts: {'frame': _frame(), 'mug': _mug},
      stores: _stores,
    );
    expect(find.text(en.soldBy('Golden Home')), findsOneWidget);
    expect(find.text(en.soldBy('Rose Shop')), findsOneWidget);
    final golden = tester.getTopLeft(find.text(en.soldBy('Golden Home'))).dy;
    final rose = tester.getTopLeft(find.text(en.soldBy('Rose Shop'))).dy;
    final mugs = find.text('Photo Mug');
    expect(mugs, findsNWidgets(2));
    // The s1 mug sits under Golden Home (before Rose Shop), the s2 mug after.
    final mugTops = [for (final e in mugs.evaluate()) (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy]
      ..sort();
    expect(mugTops.first, inExclusiveRange(golden, rose));
    expect(mugTops.last, greaterThan(rose));
  });

  testWidgets('an unavailable line is flagged and excluded from the total; a new price is shown', (tester) async {
    await pumpShop(
      tester,
      initialPath: '/cart',
      cartItems: [_frameLine(), _mugLine(store: 's1')],
      // The frame now costs 38,000 (+5,000) and the mug is gone.
      cartProducts: {'frame': _frame(price: 38000)},
      stores: _stores,
    );
    expect(find.text(en.itemUnavailable), findsOneWidget);
    expect(find.text(en.priceChangedNote('43,000 IQD')), findsOneWidget);
    // 43,000 × 2 — the mug's 12,000 is not counted.
    expect(find.text('86,000 IQD'), findsNWidgets(2));
    final mugStepper = tester.widget<QuantityStepper>(find.descendant(
      of: find.ancestor(of: find.text('Photo Mug'), matching: find.byType(CartLineTile)),
      matching: find.byType(QuantityStepper),
    ));
    expect(mugStepper.onChanged, isNull);
  });

  testWidgets('quantity changes and remove update the cart and the totals', (tester) async {
    final h = await pumpShop(
      tester,
      initialPath: '/cart',
      cartItems: [_frameLine(qty: 1), _mugLine(store: 's1')],
      cartProducts: {'frame': _frame(), 'mug': _mug},
      stores: _stores,
    );
    expect(find.text('52,000 IQD'), findsNWidgets(2));

    final frameTile = find.ancestor(of: find.text('Magnetic Photo Frame'), matching: find.byType(CartLineTile));
    await tester.tap(find.descendant(of: frameTile, matching: find.byTooltip(en.increaseQuantity)));
    await tester.pumpAndSettle();
    expect(h.local.items['a']!.qty, 2);
    expect(find.text('92,000 IQD'), findsNWidgets(2));
    expect(h.container.read(cartCountProvider), 3);

    await tester.tap(find.descendant(of: frameTile, matching: find.byTooltip(en.remove)));
    await tester.pumpAndSettle();
    expect(h.local.items.keys, ['m']);
    expect(find.text('Magnetic Photo Frame'), findsNothing);
    expect(find.text('12,000 IQD'), findsNWidgets(3)); // unit + subtotal + total

    await tester.tap(find.byTooltip(en.remove));
    await tester.pumpAndSettle();
    expect(find.text(en.emptyCartTitle), findsOneWidget);
  });

  testWidgets('Checkout asks a guest to sign in; a customer goes to checkout', (tester) async {
    await pumpShop(
      tester,
      initialPath: '/cart',
      cartItems: [_mugLine()],
      cartProducts: {'mug': _mug},
      stores: _stores,
    );
    await tester.tap(find.text(en.checkout));
    await tester.pumpAndSettle();
    expect(find.text(en.signInToContinue), findsOneWidget);
    expect(find.text('/checkout'), findsNothing);
  });

  testWidgets('a signed-in customer goes to checkout', (tester) async {
    await pumpShop(
      tester,
      initialPath: '/cart',
      user: FakeUser(),
      cartItems: [_mugLine()],
      cartProducts: {'mug': _mug},
      stores: _stores,
    );
    await tester.tap(find.text(en.checkout));
    await tester.pumpAndSettle();
    expect(find.text('/checkout'), findsOneWidget);
  });

  testWidgets('Checkout is disabled when nothing in the cart can be ordered', (tester) async {
    await pumpShop(tester, initialPath: '/cart', cartItems: [_mugLine()], cartProducts: const {});
    expect(find.text(en.itemUnavailable), findsOneWidget);
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNull);
  });

  testWidgets('a product load error offers Retry', (tester) async {
    var attempts = 0;
    await pumpShop(
      tester,
      initialPath: '/cart',
      cartItems: [_mugLine()],
      loadCartProducts: () async {
        if (++attempts == 1) throw Exception('offline');
        return {'mug': _mug};
      },
    );
    expect(find.text(en.somethingWentWrong), findsOneWidget);
    await tester.tap(find.text(en.retry));
    await tester.pumpAndSettle();
    expect(find.text('Photo Mug'), findsOneWidget);
  });

  for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('en', ThemeMode.dark)]) {
    testWidgets('filled cart renders in $locale (${mode.name})', (tester) async {
      final l10n = l10nFor(locale);
      await pumpShop(
        tester,
        initialPath: '/cart',
        cartItems: [_frameLine(), _mugLine()],
        cartProducts: {'frame': _frame(price: 36000)},
        stores: _stores,
        locale: locale,
        themeMode: mode,
      );
      expect(find.text(l10n.myCart), findsOneWidget);
      expect(find.text(l10n.itemUnavailable), findsOneWidget);
      expect(find.textContaining(l10n.photosCount(2)), findsOneWidget);
      if (locale != 'en') {
        expect(Directionality.of(tester.element(find.byType(CartLineTile).first)), TextDirection.rtl);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in ['en', 'ar', 'ckb']) {
    testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
      await pumpShop(
        tester,
        initialPath: '/cart',
        cartItems: [_frameLine(qty: 12), _mugLine(), _mugLine(id: 'm2', store: 's1')],
        cartProducts: {'frame': _frame(price: 1235000), 'mug': _mug},
        stores: _stores,
        locale: locale,
        size: const Size(320, 2400),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty cart fits at 320 × 568 with 1.3× text ($locale)', (tester) async {
      await pumpShop(tester, initialPath: '/cart', locale: locale, size: const Size(320, 568), textScale: 1.3);
      expect(find.text(l10nFor(locale).emptyCartTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
