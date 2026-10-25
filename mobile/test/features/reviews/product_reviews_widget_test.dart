import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/product_image_carousel.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/product_summary.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/variant_options.dart';
import 'package:golden_gift/features/reviews/presentation/widgets/product_reviews_section.dart';
import 'package:golden_gift/features/reviews/presentation/widgets/star_rating.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

import '../product_details/shop_test_harness.dart';

final _en = l10nFor('en');
final _path = AppRoutes.product('mug');

ProductModel _mug({double ratingAvg = 0, int ratingCount = 0}) => ProductModel(
      id: 'mug',
      title: const LocalizedText('Photo Mug', ar: 'كوب بصورة', ku: 'کوپی وێنەدار'),
      description: const LocalizedText('A mug with your photo.', ar: 'كوب بصورتك.', ku: 'کوپێک بە وێنەکەت.'),
      storeId: 's1',
      price: 15000,
      ratingAvg: ratingAvg,
      ratingCount: ratingCount,
      optionGroups: const [
        OptionGroup(
          id: 'ink',
          type: OptionType.colorSwatch,
          label: LocalizedText('Color'),
          values: [
            OptionValue(id: 'red', label: LocalizedText('Red'), hex: '#E53935'),
            OptionValue(id: 'black', label: LocalizedText('Black'), hex: '#222222'),
          ],
        ),
      ],
    );

Future<void> _review(
  FakeFirebaseFirestore db,
  String id, {
  required bool approved,
  required DateTime at,
  int rating = 5,
  String name = 'Sara',
  String text = '',
  List<String> images = const [],
}) =>
    db.doc('products/mug/reviews/$id').set({
      'productId': 'mug',
      'userId': 'u-$id',
      'userName': name,
      'storeId': 's1',
      'rating': rating,
      'text': text,
      'images': images,
      'orderId': 'o-$id',
      'isApproved': approved,
      'createdAt': Timestamp.fromDate(at),
    });

/// 5 approved reviews (newest = e) and 1 pending.
Future<FakeFirebaseFirestore> _reviews() async {
  final db = FakeFirebaseFirestore();
  await _review(db, 'a', approved: true, at: DateTime(2026, 9, 1), name: 'Aras', text: 'Oldest one');
  await _review(db, 'b', approved: true, at: DateTime(2026, 9, 2), name: 'Bahar', rating: 3);
  await _review(db, 'c', approved: true, at: DateTime(2026, 9, 3), name: 'Chiman', rating: 4, text: 'Nice print');
  await _review(db, 'd', approved: true, at: DateTime(2026, 9, 4), name: 'Dara', images: const ['', '']);
  await _review(db, 'e', approved: true, at: DateTime(2026, 9, 5), name: 'Evin', text: 'Loved it!');
  await _review(db, 'p', approved: false, at: DateTime(2026, 9, 6), name: 'Pending', text: 'Not yet approved');
  return db;
}

void main() {
  testWidgets('no approved reviews → no section', (tester) async {
    await pumpShop(tester, initialPath: _path, product: _mug());
    expect(find.byType(ProductReviewsSection), findsOneWidget);
    expect(find.byKey(const ValueKey('product-reviews')), findsNothing);
  });

  testWidgets('below About: aggregates, the 3 latest approved reviews (never pending), See all', (tester) async {
    await pumpShop(tester, initialPath: _path, product: _mug(ratingAvg: 4.5, ratingCount: 12), firestore: await _reviews());
    expect(find.text(_en.reviewsTitle), findsOneWidget);
    // Below About.
    expect(tester.getTopLeft(find.text(_en.reviewsTitle)).dy,
        greaterThan(tester.getTopLeft(find.text(_en.aboutTheProduct)).dy));
    expect(tester.widget<Text>(find.byKey(const ValueKey('rating-average'))).data, '4.5');
    expect(find.text(_en.reviewsCount(12)), findsOneWidget);
    expect(find.bySemanticsLabel(_en.reviewStarsLabel('4.5')), findsWidgets);

    expect(find.byKey(const ValueKey('review-e')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-d')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-c')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-b')), findsNothing);
    expect(find.text('Not yet approved'), findsNothing);
    expect(find.text('Evin'), findsOneWidget);
    expect(find.text('05/09/2026'), findsOneWidget);
    expect(find.text('Loved it!'), findsOneWidget);
    expect(tester.widget<StarRatingDisplay>(
        find.descendant(of: find.byKey(const ValueKey('review-c')), matching: find.byType(StarRatingDisplay))).rating, 4);

    await tester.ensureVisible(find.byKey(const ValueKey('reviews-see-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviews-see-all')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('all-reviews'));
    expect(sheet, findsOneWidget);
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      await tester.scrollUntilVisible(
        find.descendant(of: sheet, matching: find.byKey(ValueKey('review-$id'))),
        200,
        scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)).first,
      );
    }
    expect(find.descendant(of: sheet, matching: find.text('Oldest one')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Not yet approved')), findsNothing);
  });

  testWidgets('without aggregates yet, the summary comes from the loaded reviews', (tester) async {
    final db = FakeFirebaseFirestore();
    await _review(db, 'a', approved: true, at: DateTime(2026, 9, 1), rating: 4);
    await _review(db, 'b', approved: true, at: DateTime(2026, 9, 2), rating: 5);
    await pumpShop(tester, initialPath: _path, product: _mug(), firestore: db);
    expect(tester.widget<Text>(find.byKey(const ValueKey('rating-average'))).data, '4.5');
    expect(find.text(_en.reviewsCount(2)), findsOneWidget);
    expect(find.byKey(const ValueKey('reviews-see-all')), findsNothing);
  });

  testWidgets('review photos open the full-screen viewer', (tester) async {
    await pumpShop(tester, initialPath: _path, product: _mug(ratingAvg: 4.5, ratingCount: 5), firestore: await _reviews());
    await tester.ensureVisible(find.byKey(const ValueKey('review-photo-d-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-photo-d-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-viewer')), findsOneWidget);
  });

  testWidgets('option taps never rebuild the reviews section (SRS §5.9 frame budget)', (tester) async {
    await pumpShop(tester, initialPath: _path, product: _mug(ratingAvg: 4.5, ratingCount: 5), firestore: await _reviews());
    final option = find.byKey(const ValueKey('option-ink-red'));
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    expect(tester.element(find.byType(ColorSwatchOptions)).dirty, isTrue);
    expect(tester.element(find.byType(ProductReviewsSection)).dirty, isFalse);
    expect(tester.element(find.byType(ProductImageCarousel)).dirty, isFalse);
    expect(tester.element(find.byType(AboutProductSection)).dirty, isFalse);
    await tester.pumpAndSettle();
  });

  for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
    testWidgets('renders in $locale (${mode.name})', (tester) async {
      await pumpShop(
        tester,
        initialPath: _path,
        product: _mug(ratingAvg: 4.5, ratingCount: 12),
        firestore: await _reviews(),
        locale: locale,
        themeMode: mode,
      );
      final l10n = l10nFor(locale);
      expect(find.text(l10n.reviewsTitle), findsOneWidget);
      expect(find.text(l10n.reviewsCount(12)), findsOneWidget);
      expect(Directionality.of(tester.element(find.byType(ProductReviewsSection))), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in ['en', 'ar', 'ckb']) {
    testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
      await pumpShop(
        tester,
        initialPath: _path,
        product: _mug(ratingAvg: 4.5, ratingCount: 1200),
        firestore: await _reviews(),
        locale: locale,
        size: const Size(320, 3200),
        textScale: 1.3,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('reviews-see-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reviews-see-all')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
