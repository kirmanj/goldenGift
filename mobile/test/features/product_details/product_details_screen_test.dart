import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/cart/presentation/widgets/quantity_stepper.dart';
import 'package:golden_gift/features/product_details/data/photo_service.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/product_details/presentation/providers/product_details_controller.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/add_to_cart_bar.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/option_group_section.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/product_image_carousel.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/product_summary.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/text_and_date_options.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/variant_options.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:image_picker/image_picker.dart';

import '../../helpers/auth_fakes.dart';
import 'shop_test_harness.dart';

final en = l10nFor('en');
final _path = AppRoutes.product('frame');

Finder _option(String groupId, String valueId) => find.byKey(ValueKey('option-$groupId-$valueId'));
Finder _slot(int n) => find.byKey(ValueKey('photo-slot-photos-$n'));
Finder get _addToCart => find.descendant(of: find.byType(Scaffold).first, matching: find.byType(PrimaryButton));
Finder _qty(int n) => find.descendant(of: find.byType(QuantityStepper), matching: find.text('$n'));

Finder get _pageScrollable =>
    find.ancestor(of: find.byType(OptionGroupSection).first, matching: find.byType(Scrollable)).first;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _addPhotoFromGallery(WidgetTester tester, int slot) async {
  await _tap(tester, _slot(slot));
  expect(find.text(en.takePhoto), findsOneWidget);
  await tester.tap(find.text(en.chooseFromGallery));
  await tester.pumpAndSettle();
}

/// Frame: Walnut, Text 1: "Happy B-day" — every required group except photos.
Future<void> _fillRequiredFields(WidgetTester tester) async {
  await _tap(tester, _option('frame', 'walnut'));
  await tester.enterText(find.byType(TextField).first, 'Happy B-day');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders every option type, banner, badges and the live bar', (tester) async {
    final h = await pumpShop(
      tester,
      initialPath: _path,
      product: allOptionsProduct(discounted: true, availableCities: const ['erbil', 'duhok']),
    );

    expect(find.text(en.productDetails), findsOneWidget);
    expect(find.text('Personalized Magnetic Photo Frame'), findsOneWidget);
    expect(find.text(en.availableOnlyIn('Erbil, Duhok')), findsOneWidget);
    expect(find.byType(FeaturedBadge), findsOneWidget);
    expect(find.byType(WishlistHeart), findsOneWidget);
    expect(find.text('13%'), findsOneWidget); // DiscountBadge below the carousel
    expect(find.text(en.preparationDays(2)), findsOneWidget);
    expect(find.text(en.aboutTheProduct), findsOneWidget);
    expect(find.text(en.share), findsOneWidget);

    // imageVariant tiles with the price delta; textVariant chips; swatches.
    expect(find.text('Frame Color'), findsOneWidget);
    expect(find.text('Walnut'), findsOneWidget);
    expect(find.text('+5,000 IQD'), findsOneWidget);
    expect(_option('frame', 'gold'), findsOneWidget);
    expect(find.text('30x30cm'), findsOneWidget);
    expect(find.text('40x40cm · +3,000 IQD'), findsOneWidget);
    for (final id in ['red', 'gold', 'black', 'white']) {
      expect(_option('ink', id), findsOneWidget);
    }
    // text + longText with live counters; optional groups say so.
    expect(find.text('0/12'), findsOneWidget);
    expect(find.text('0/500'), findsOneWidget);
    expect(find.textContaining(en.optionalLabel, findRichText: true), findsWidgets);
    // date pill and four numbered photo slots.
    expect(find.text(en.selectADate), findsOneWidget);
    for (var n = 1; n <= 4; n++) {
      expect(_slot(n), findsOneWidget);
    }
    expect(find.text('${en.addToCart} · 35,000 IQD'), findsOneWidget);

    // Counter updates while typing.
    await tester.enterText(find.byType(TextField).first, 'Hi');
    await tester.pump();
    expect(find.text('2/12'), findsOneWidget);

    // view_item + viewing history, once.
    expect(h.analytics.events.containsKey(AnalyticsEvents.viewItem), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add to Cart with missing groups shows the hints and scrolls to the first', (tester) async {
    final h = await pumpShop(tester, initialPath: _path, product: allOptionsProduct(), size: const Size(390, 800));

    await tester.fling(_pageScrollable, const Offset(0, -4000), 3000);
    await tester.pumpAndSettle();
    final scrolledTo = tester.state<ScrollableState>(_pageScrollable).position.pixels;
    expect(scrolledTo, greaterThan(300));

    await tester.tap(_addToCart);
    await tester.pumpAndSettle();

    // One hint per required group, worded per type.
    expect(find.text(en.optionRequiredError), findsOneWidget);
    expect(find.text(en.textRequiredError), findsOneWidget);
    expect(find.text(en.photosRequiredError(2)), findsOneWidget);

    // Scrolled back up so the first problem (Frame Color) is on screen.
    expect(tester.state<ScrollableState>(_pageScrollable).position.pixels, lessThan(scrolledTo));
    final hint = tester.getRect(find.text(en.optionRequiredError));
    final barTop = tester.getTopLeft(find.byType(QuantityStepper)).dy;
    expect(hint.top, greaterThan(0));
    expect(hint.bottom, lessThan(barTop));
    expect(h.cartItems, isEmpty);

    // Hints clear live once fixed.
    await _tap(tester, _option('frame', 'black'));
    expect(find.text(en.optionRequiredError), findsNothing);
  });

  testWidgets('a valid configuration adds the right line and View cart opens the Cart tab', (tester) async {
    final h = await pumpShop(tester, initialPath: _path, product: allOptionsProduct(photosRequired: false));

    await _fillRequiredFields(tester);
    await _tap(tester, find.text('40x40cm · +3,000 IQD'));
    await _tap(tester, _option('ink', 'red'));
    await _tap(tester, find.text(en.selectADate));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip(en.increaseQuantity));

    // 35,000 + 5,000 (walnut) + 3,000 (40x40) = 43,000 × 2.
    expect(find.text('${en.addToCart} · ${CurrencyFormatter.format(86000)}'), findsOneWidget);
    await tester.tap(_addToCart);
    await tester.pumpAndSettle();

    final item = h.cartItems.single;
    expect(h.local.items.values.single.id, item.id); // guest → local cart
    expect(item.productId, 'frame');
    expect(item.storeId, 's1');
    expect(item.unitPrice, 43000);
    expect(item.qty, 2);
    expect(item.preparationDays, 4); // walnut's override
    final byGroup = {for (final s in item.selections) s.groupId: s};
    expect(byGroup.keys, ['frame', 'size', 'ink', 'text1', 'date']); // empty notes / photos skipped
    expect(byGroup['frame']!.valueId, 'walnut');
    expect(byGroup['frame']!.priceDelta, 5000);
    expect(byGroup['size']!.valueId, 's40');
    expect(byGroup['ink']!.hex, '#E53935');
    expect(byGroup['text1']!.text, 'Happy B-day');
    final today = DateTime.now();
    expect(byGroup['date']!.date, DateTime.utc(today.year, today.month, today.day, 12));
    expect(h.analytics.events.containsKey(AnalyticsEvents.addToCart), isTrue);

    expect(find.text(en.addedToCart), findsOneWidget);
    await tester.tap(find.text(en.viewCart));
    await tester.pumpAndSettle();
    expect(find.text('main tab 1'), findsOneWidget);
  });

  testWidgets('a value with preparationDaysOverride updates the banner; sold-out values are disabled', (tester) async {
    final h = await pumpShop(tester, initialPath: _path, product: allOptionsProduct());
    expect(find.text(en.preparationDays(2)), findsOneWidget);

    await _tap(tester, _option('frame', 'walnut'));
    expect(find.text(en.preparationDays(4)), findsOneWidget);
    expect(find.text('${en.addToCart} · 40,000 IQD'), findsOneWidget);

    // Sold-out frame and swatch can't be chosen.
    await _tap(tester, _option('frame', 'gold'));
    await _tap(tester, _option('ink', 'white'));
    final config = h.container.read(productDetailsControllerProvider('frame')).config!;
    expect(config.selectionFor('frame').valueId, 'walnut');
    expect(config.selectionFor('ink').valueId, isNull);
    expect(find.text(en.outOfStock), findsWidgets);

    // Tapping the selected value again clears it (and the override).
    await _tap(tester, _option('frame', 'walnut'));
    expect(find.text(en.preparationDays(2)), findsOneWidget);
  });

  testWidgets('choosing a value rebuilds only what depends on it (SRS §5.9: < 16 ms frames)', (tester) async {
    await pumpShop(tester, initialPath: _path, product: allOptionsProduct());
    bool dirty(Type type) => tester.element(find.byType(type)).dirty;

    // A swatch without a price delta: only its own row.
    await tester.ensureVisible(_option('ink', 'red'));
    await tester.pumpAndSettle();
    await tester.tap(_option('ink', 'red'));
    expect(dirty(ColorSwatchOptions), isTrue);
    for (final type in [
      ProductImageCarousel,
      AvailabilityBanner,
      PriceShareRow,
      AddToCartBar,
      ImageVariantOptions,
      TextVariantOptions,
      DateOptionField,
    ]) {
      expect(dirty(type), isFalse, reason: '$type should not rebuild');
    }
    expect(tester.elementList(find.byType(OptionGroupSection)).where((e) => e.dirty), isEmpty);
    await tester.pumpAndSettle();

    // Walnut (+5,000 IQD, 4 days): its row, the banner, the price and the bar.
    await tester.ensureVisible(_option('frame', 'walnut'));
    await tester.pumpAndSettle();
    await tester.tap(_option('frame', 'walnut'));
    for (final type in [ImageVariantOptions, AvailabilityBanner, PriceShareRow, AddToCartBar]) {
      expect(dirty(type), isTrue, reason: '$type should rebuild');
    }
    expect(dirty(ProductImageCarousel), isFalse);
    expect(dirty(ColorSwatchOptions), isFalse);
    expect(dirty(TextVariantOptions), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('quantity is bounded by the selected values\' stock', (tester) async {
    final h = await pumpShop(tester, initialPath: _path, product: allOptionsProduct());
    await _tap(tester, find.text('40x40cm · +3,000 IQD')); // stock 3
    for (var i = 0; i < 5; i++) {
      await _tap(tester, find.byTooltip(en.increaseQuantity));
    }
    expect(_qty(3), findsOneWidget);
    final plus =
        tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.add_rounded), matching: find.byType(IconButton)));
    expect(plus.onPressed, isNull);

    // Switching to the unlimited size lifts the cap; decreasing stops at 1.
    await _tap(tester, find.text('30x30cm'));
    await _tap(tester, find.byTooltip(en.increaseQuantity));
    expect(_qty(4), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await _tap(tester, find.byTooltip(en.decreaseQuantity));
    }
    expect(h.container.read(productDetailsControllerProvider('frame')).config!.qty, 1);
  });

  testWidgets('a guest with photos is asked to sign in and nothing is uploaded', (tester) async {
    final h = await pumpShop(tester, initialPath: _path, product: allOptionsProduct());
    await _fillRequiredFields(tester);
    await _addPhotoFromGallery(tester, 1);
    await _addPhotoFromGallery(tester, 2);
    expect(h.photos.picks, [ImageSource.gallery, ImageSource.gallery]);
    expect(find.byTooltip(en.removePhoto), findsNWidgets(2));

    await tester.tap(_addToCart);
    await tester.pumpAndSettle();
    expect(find.text(en.signInToContinue), findsOneWidget);
    expect(h.photos.uploads, isEmpty);
    expect(h.cartItems, isEmpty);
  });

  testWidgets("a signed-in customer's photos upload under the cart line id and land in the selections", (tester) async {
    final h = await pumpShop(tester, initialPath: _path, product: allOptionsProduct(), user: FakeUser(uid: 'u7'));
    await _fillRequiredFields(tester);
    await _addPhotoFromGallery(tester, 1);
    await _addPhotoFromGallery(tester, 2);
    await _addPhotoFromGallery(tester, 3);
    // ✕ removes a thumbnail; slot 3 is empty again.
    await _tap(tester, find.byTooltip(en.removePhoto).last);
    expect(find.byTooltip(en.removePhoto), findsNWidgets(2));
    expect(_slot(3), findsOneWidget);

    await tester.tap(_addToCart);
    await tester.pumpAndSettle();

    final upload = h.photos.uploads.single;
    final item = h.remote.items.values.single; // signed in → account cart
    expect(upload.uid, 'u7');
    expect(upload.cartItemId, item.id);
    expect(upload.photosByGroup['photos'], hasLength(2));
    final photos = item.selections.singleWhere((s) => s.groupId == 'photos');
    expect(photos.type, OptionType.photoUpload);
    expect(photos.urls, [
      'https://storage.test/uploads/u7/${item.id}/photos-1.jpg',
      'https://storage.test/uploads/u7/${item.id}/photos-2.jpg',
    ]);
    expect(item.photoCount, 2);
    expect(find.text(en.addedToCart), findsOneWidget);
  });

  testWidgets('an upload failure adds nothing; a photo over 10 MB is refused', (tester) async {
    final photos = FakePhotoService()..uploadError = Exception('network');
    final h =
        await pumpShop(tester, initialPath: _path, product: allOptionsProduct(), user: FakeUser(), photos: photos);
    await _fillRequiredFields(tester);
    await _addPhotoFromGallery(tester, 1);
    await _addPhotoFromGallery(tester, 2);
    await tester.tap(_addToCart);
    await tester.pumpAndSettle();
    expect(find.text(en.photoUploadFailed), findsOneWidget);
    expect(h.cartItems, isEmpty);

    photos.pickError = const PhotoTooLargeException();
    await _addPhotoFromGallery(tester, 3);
    expect(find.text(en.photoTooLarge), findsOneWidget);
    expect(find.byTooltip(en.removePhoto), findsNWidgets(2));
  });

  testWidgets('a missing product shows Not found with a way back to shopping', (tester) async {
    await pumpShop(tester, initialPath: _path, product: null);
    expect(find.text(en.productNotFound), findsOneWidget);
    await tester.tap(find.text(en.startShopping));
    await tester.pumpAndSettle();
    expect(find.text('main tab 0'), findsOneWidget);
  });

  testWidgets('an inactive product is shown as no longer available', (tester) async {
    await pumpShop(
      tester,
      initialPath: _path,
      product: const ProductModel(
        id: 'mug',
        title: LocalizedText('Photo Mug'),
        storeId: 's1',
        price: 12000,
        isActive: false,
      ),
    );
    expect(find.text(en.productNotFound), findsOneWidget);
    expect(find.byType(QuantityStepper), findsNothing);
  });

  testWidgets('out of stock: error banner and a disabled button', (tester) async {
    await pumpShop(tester, initialPath: _path, product: allOptionsProduct(outOfStock: true));
    expect(find.text(en.outOfStock), findsWidgets);
    final button = tester.widget<PrimaryButton>(_addToCart);
    expect(button.label, en.outOfStock);
    expect(button.onPressed, isNull);
  });

  testWidgets('a same-day product without options shows the success banner', (tester) async {
    final h = await pumpShop(
      tester,
      initialPath: _path,
      product: const ProductModel(id: 'mug', title: LocalizedText('Photo Mug'), storeId: 's1', price: 12000),
    );
    expect(find.text(en.sameDayShipping), findsOneWidget);
    expect(find.text('${en.addToCart} · 12,000 IQD'), findsOneWidget);
    await tester.tap(_addToCart);
    await tester.pumpAndSettle();
    expect(h.cartItems.single.selections, isEmpty);
    expect(h.cartItems.single.preparationDays, 0);
  });

  testWidgets('a loading error offers Retry', (tester) async {
    var attempts = 0;
    await pumpShop(
      tester,
      initialPath: _path,
      productStream: (_) => ++attempts == 1 ? Stream.error(Exception('offline')) : Stream.value(allOptionsProduct()),
    );
    expect(find.text(en.somethingWentWrong), findsOneWidget);
    await tester.tap(find.text(en.retry));
    await tester.pumpAndSettle();
    expect(find.text('Frame Color'), findsOneWidget);
  });

  testWidgets('the heart saves the product for a signed-in customer', (tester) async {
    final db = FakeFirebaseFirestore();
    await pumpShop(tester, initialPath: _path, product: allOptionsProduct(), user: FakeUser(), firestore: db);
    await tester.tap(find.byType(WishlistHeart));
    await tester.pumpAndSettle();
    final saved = await db.doc('wishlists/u1/items/frame').get();
    expect(saved.exists, isTrue);
    expect(saved.data()!['price'], 35000);
  });

  for (final (locale, mode) in [('ar', ThemeMode.light), ('ckb', ThemeMode.dark), ('en', ThemeMode.dark)]) {
    testWidgets('renders in $locale (${mode.name}) without exceptions', (tester) async {
      final l10n = l10nFor(locale);
      await pumpShop(
        tester,
        initialPath: _path,
        product: allOptionsProduct(discounted: true, availableCities: const ['erbil']),
        locale: locale,
        themeMode: mode,
      );
      expect(find.text(l10n.productDetails), findsOneWidget);
      expect(find.text(l10n.availableOnlyIn(testCities.first.name.resolve(locale))), findsOneWidget);
      await tester.tap(_addToCart);
      await tester.pumpAndSettle();
      expect(find.text(l10n.optionRequiredError), findsOneWidget);
      if (locale != 'en') {
        expect(Directionality.of(tester.element(find.byType(OptionGroupSection).first)), TextDirection.rtl);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in ['en', 'ar', 'ckb']) {
    testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
      await pumpShop(
        tester,
        initialPath: _path,
        product: allOptionsProduct(discounted: true, availableCities: const ['erbil', 'duhok']),
        locale: locale,
        size: const Size(320, 3600),
        textScale: 1.3,
      );
      await _tap(tester, _option('frame', 'walnut'));
      await tester.tap(_addToCart);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Gift for pills (SRS §5.8a) open the products list filtered by that gift type', (tester) async {
    final product = allOptionsProduct().copyWithGiftFor(const [GiftAudience.men, GiftAudience.companies]);
    final h = await pumpShop(tester, initialPath: _path, product: product);
    expect(find.text(en.giftForTitle), findsOneWidget);
    expect(find.text(en.giftForWomen), findsNothing);
    await _tap(tester, find.text(en.giftForCompanies));
    expect(find.text('products ${AppRoutes.productsFor(const ProductQuery(giftFor: GiftAudience.companies))}'),
        findsOneWidget);
    expect(h.container, isNotNull);
  });

  testWidgets('no gift type → no Gift for line', (tester) async {
    await pumpShop(tester, initialPath: _path, product: allOptionsProduct());
    expect(find.text(en.giftForTitle), findsNothing);
  });
}

extension on ProductModel {
  ProductModel copyWithGiftFor(List<GiftAudience> giftFor) =>
      ProductModel.fromMap(id, {...toMap(), 'giftFor': giftFor.map((a) => a.name).toList()});
}
