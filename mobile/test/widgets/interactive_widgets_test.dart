import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/widgets/widgets.dart';

import 'test_app.dart';

void main() {
  group('WishlistHeart', () {
    testWidgets('toggles optimistically and reports each new value', (tester) async {
      final calls = <bool>[];
      await tester.pumpWidget(testApp(WishlistHeart(isActive: false, onChanged: calls.add)));

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();
      expect(calls, [true]);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pumpAndSettle();
      expect(calls, [true, false]);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('flips back when the toggle reports nothing changed (guest / failed write)', (tester) async {
      await tester.pumpWidget(testApp(WishlistHeart(isActive: false, onChanged: (_) => Future<bool?>.value(null))));
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('keeps the new state when the toggle confirms it', (tester) async {
      await tester.pumpWidget(testApp(WishlistHeart(isActive: false, onChanged: (v) => Future<bool?>.value(v))));
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('parent value wins and tap target is at least 44 px', (tester) async {
      await tester.pumpWidget(testApp(WishlistHeart(isActive: false, onChanged: (_) {})));
      await tester.pumpWidget(testApp(WishlistHeart(isActive: true, onChanged: (_) {})));
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      final size = tester.getSize(find.byType(GGCircleButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('GGSearchBar', () {
    testWidgets('debounces onChanged by 400 ms and only sends the last value', (tester) async {
      final values = <String>[];
      await tester.pumpWidget(testApp(GGSearchBar(onChanged: values.add)));

      await tester.enterText(find.byType(TextField), 'r');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'ro');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'roses');
      await tester.pump(const Duration(milliseconds: 399));
      expect(values, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(values, ['roses']);
    });

    testWidgets('clear button empties the field and notifies immediately', (tester) async {
      final values = <String>[];
      await tester.pumpWidget(testApp(GGSearchBar(onChanged: values.add)));

      await tester.enterText(find.byType(TextField), 'mug');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(values, ['']);
      expect(find.text('mug'), findsNothing);

      await tester.pump(const Duration(milliseconds: 500));
      expect(values, [''], reason: 'pending debounce was cancelled');
    });

    testWidgets('pending debounce is cancelled on dispose', (tester) async {
      final values = <String>[];
      await tester.pumpWidget(testApp(GGSearchBar(onChanged: values.add)));
      await tester.enterText(find.byType(TextField), 'frame');
      await tester.pumpWidget(testApp(const SizedBox()));
      await tester.pump(const Duration(seconds: 1));
      expect(values, isEmpty);
    });

    testWidgets('read-only mode is a tappable fake field; filter button fires', (tester) async {
      var taps = 0;
      var filters = 0;
      await tester.pumpWidget(testApp(GGSearchBar(
        readOnly: true,
        hint: 'Describe who it is for',
        onTap: () => taps++,
        onFilterTap: () => filters++,
      )));

      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Describe who it is for'));
      expect(taps, 1);
      await tester.tap(find.byTooltip('Filter'));
      expect(filters, 1);
    });
  });

  group('GGInput', () {
    testWidgets('label, live counter, enforced max length and error text', (tester) async {
      await tester.pumpWidget(testApp(const GGInput(
        label: 'Text 1',
        hint: 'Enter the text',
        maxLength: 5,
        showCounter: true,
        errorText: 'Required',
      )));

      expect(find.text('Text 1'), findsOneWidget);
      expect(find.text('0/5'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Happy birthday');
      await tester.pump();
      expect(find.text('5/5'), findsOneWidget);
      expect(find.text('Happy'), findsOneWidget);
    });

    testWidgets('multiline text area and prefix slot render in RTL dark', (tester) async {
      await tester.pumpWidget(testApp(
        const Column(
          children: [
            GGInput(label: 'Notes', multiline: true, maxLength: 500, showCounter: true),
            GGInput(label: 'Mobile', prefix: Text('+964')),
          ],
        ),
        locale: const Locale('ar'),
        dark: true,
        width: 360,
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('+964'), findsOneWidget);
      expect(find.text('0/500'), findsOneWidget);
    });
  });

  group('GGAppBar', () {
    testWidgets('back, title and cart badge; back mirrors in RTL', (tester) async {
      var backs = 0;
      var carts = 0;
      Widget bar(Locale locale) => testApp(
            GGAppBar(
              title: 'Products',
              showBack: true,
              onBack: () => backs++,
              cartCount: 3,
              onCartTap: () => carts++,
            ),
            locale: locale,
            width: 400,
          );

      await tester.pumpWidget(bar(const Locale('en')));
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      final backLtr = tester.getCenter(find.byIcon(Icons.arrow_back_ios_new_rounded)).dx;
      final cartLtr = tester.getCenter(find.byIcon(Icons.shopping_bag_outlined)).dx;
      expect(backLtr, lessThan(cartLtr));

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.tap(find.byIcon(Icons.shopping_bag_outlined));
      expect(backs, 1);
      expect(carts, 1);

      await tester.pumpWidget(bar(const Locale('ar')));
      final backRtl = tester.getCenter(find.byIcon(Icons.arrow_back_ios_new_rounded)).dx;
      final cartRtl = tester.getCenter(find.byIcon(Icons.shopping_bag_outlined)).dx;
      expect(backRtl, greaterThan(cartRtl));
    });

    testWidgets('no back button on a root route by default', (tester) async {
      await tester.pumpWidget(testApp(const GGAppBar(title: 'Home')));
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    });
  });

  group('Buttons', () {
    testWidgets('PrimaryButton: tap, loading ignores taps, disabled', (tester) async {
      var taps = 0;
      await tester
          .pumpWidget(testApp(PrimaryButton(label: 'Add to Cart', onPressed: () => taps++)));
      await tester.tap(find.text('Add to Cart'));
      expect(taps, 1);
      expect(tester.getSize(find.byType(PrimaryButton)).height, 56);

      await tester.pumpWidget(testApp(
        PrimaryButton(label: 'Add to Cart', isLoading: true, onPressed: () => taps++),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton));
      expect(taps, 1);

      await tester.pumpWidget(testApp(const OutlineButton(label: 'Later', onPressed: null)));
      await tester.tap(find.text('Later'));
      expect(tester.takeException(), isNull);
    });
  });

  group('Button labels keep the locale font (ButtonStyle.textStyle does not merge)', () {
    for (final (code, family) in [('en', 'Nunito'), ('ar', 'Vazirmatn'), ('ckb', 'Vazirmatn')]) {
      testWidgets(code, (tester) async {
        await tester.pumpWidget(testApp(
          Column(
            children: [
              PrimaryButton(label: 'Primary', onPressed: () {}),
              OutlineButton(label: 'Outline', onPressed: () {}),
              SectionHeader(title: 'Popular', viewAllLabel: 'All', onViewAll: () {}),
            ],
          ),
          locale: Locale(code),
        ));
        for (final label in ['Primary', 'Outline', 'All']) {
          final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
          expect(paragraph.text.style?.fontFamily, family, reason: label);
        }
      });
    }
  });

  group('Catalogue widgets', () {
    testWidgets('SectionHeader hides View All without a callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(testApp(SectionHeader(title: 'Popular', onViewAll: () => taps++)));
      await tester.tap(find.text('View All'));
      expect(taps, 1);

      await tester.pumpWidget(testApp(const SectionHeader(title: 'Popular')));
      expect(find.text('View All'), findsNothing);
    });

    testWidgets('CategoryChip selection and CategoryTile.more label', (tester) async {
      var chipTaps = 0;
      await tester.pumpWidget(testApp(
        Column(
          children: [
            CategoryChip(
              label: 'Flowers',
              icon: Icons.local_florist_outlined,
              selected: true,
              onTap: () => chipTaps++,
            ),
            const SizedBox(width: 90, child: CategoryTile(label: 'Skin and Body Care')),
            SizedBox(width: 90, child: CategoryTile.more(onTap: () {})),
          ],
        ),
      ));

      await tester.tap(find.text('Flowers'));
      expect(chipTaps, 1);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Skin and Body Care'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('BannerCarousel is hidden when empty', (tester) async {
      await tester.pumpWidget(testApp(const BannerCarousel(imageUrls: [])));
      expect(find.byType(PageView), findsNothing);
      expect(tester.getSize(find.byType(BannerCarousel)), Size.zero);
    });

    testWidgets('GGLogo shows the emblem and the wordmark', (tester) async {
      await tester.pumpWidget(testApp(const GGLogo(), dark: true));
      expect(find.text('GOLDEN GIFT'), findsOneWidget);
      expect(find.bySemanticsLabel('Golden Gift'), findsOneWidget);
      await tester.pumpWidget(testApp(const GGLogo(showWordmark: false)));
      expect(find.text('GOLDEN GIFT'), findsNothing);
    });
  });
}
