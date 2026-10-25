import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/features/gift_cards/presentation/widgets/gift_card_face.dart';
import 'package:golden_gift/models/gift_card_model.dart';
import 'package:golden_gift/models/localized_text.dart';

import 'phase8_test_harness.dart';

final _en = l10nFor('en');

void main() {
  group('Home gift cards section', () {
    testWidgets('hidden when there are no templates', (tester) async {
      await pumpPhase8(tester, initialPath: '/home-test');
      expect(find.byKey(const ValueKey('home-gift-cards-header')), findsNothing);
      expect(find.text(_en.giftCards), findsNothing);
    });

    testWidgets('one gold tile per template in sortOrder; View All → shop; tile → Designer', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedTemplate(db, 'b', name: 'Birthday', presets: [25000], min: 0, max: 0, sortOrder: 2);
      await seedTemplate(db, 'a', name: 'Golden Classic', sortOrder: 1);
      final h = await pumpPhase8(tester, initialPath: '/home-test', firestore: db);

      expect(find.text(_en.giftCards), findsOneWidget);
      final a = tester.getTopLeft(find.byKey(const ValueKey('home-gift-card-a')));
      final b = tester.getTopLeft(find.byKey(const ValueKey('home-gift-card-b')));
      expect(a.dx, lessThan(b.dx));
      expect(find.text(_en.giftCardLabel), findsNWidgets(2));
      // Several amounts → "From the lowest"; one preset only → that amount.
      expect(find.text(_en.giftCardFrom('10,000 IQD')), findsOneWidget);
      expect(find.text('25,000 IQD'), findsOneWidget);

      await tester.tap(find.text(_en.viewAll));
      await tester.pumpAndSettle();
      expect(h.location, '/gift-cards/shop');
      expect(find.byKey(const ValueKey('shop-template-a')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('shop-template-b')));
      await tester.pumpAndSettle();
      expect(h.location, '/gift-cards/design/b');
    });

    testWidgets('a tile opens the Designer for its template', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedTemplate(db, 'a');
      final h = await pumpPhase8(tester, initialPath: '/home-test', firestore: db);
      await tester.tap(find.byKey(const ValueKey('home-gift-card-a')));
      await tester.pumpAndSettle();
      expect(h.location, '/gift-cards/design/a');
      expect(find.byKey(const ValueKey('designer-preview')), findsOneWidget);
    });

    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('renders in $locale ${mode.name}', (tester) async {
        final db = FakeFirebaseFirestore();
        await seedTemplate(db, 'a', gradientStart: '#1B2A4A', gradientEnd: '#3D5A80');
        await seedTemplate(db, 'b', sortOrder: 1);
        await pumpPhase8(tester, initialPath: '/home-test', firestore: db, locale: locale, themeMode: mode);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home-gift-card-b')), findsOneWidget);
      });
    }

    testWidgets('no overflow at 320 px with 1.3× text', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedTemplate(db, 'a', name: 'A very long gift card template name that keeps going');
      await pumpPhase8(tester,
          initialPath: '/home-test', firestore: db, locale: 'ckb', size: const Size(320, 800), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });

  group('Gift card shop', () {
    testWidgets('empty state without templates', (tester) async {
      await pumpPhase8(tester, initialPath: '/gift-cards/shop');
      expect(find.byKey(const ValueKey('gift-shop-empty')), findsOneWidget);
      expect(find.text(_en.giftCardShopEmptyTitle), findsOneWidget);
    });

    testWidgets('320 px, 1.3× text, Kurdish dark', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedTemplate(db, 'a');
      await seedTemplate(db, 'b', sortOrder: 1);
      await pumpPhase8(tester,
          initialPath: '/gift-cards/shop',
          firestore: db,
          locale: 'ckb',
          themeMode: ThemeMode.dark,
          size: const Size(320, 900),
          textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });

  group('card colours', () {
    test('template hex colours, else the gold shimmer', () {
      expect(parseHexColor('#C9A227'), const Color(0xFFC9A227));
      expect(parseHexColor('c9a227'), const Color(0xFFC9A227));
      expect(parseHexColor('#80C9A227'), const Color(0x80C9A227));
      expect(parseHexColor('#xyz'), isNull);
      expect(parseHexColor(null), isNull);
      expect(giftCardGradientFor(null, '#000000'), AppColors.giftCardGradient);
      expect(giftCardGradientFor('#111111', '#222222').colors, [const Color(0xFF111111), const Color(0xFF222222)]);
    });

    test('dark text on gold, white text on dark custom colours', () {
      expect(giftCardForeground(AppColors.giftCardGradient), AppColors.textOnPrimary);
      expect(giftCardForeground(giftCardGradientFor('#1B2A4A', '#3D5A80')), AppColors.white);
    });

    test('amount label', () {
      const one = GiftCardTemplateModel(id: 'x', name: LocalizedText.empty, presetAmounts: [50000]);
      const custom = GiftCardTemplateModel(id: 'y', name: LocalizedText.empty, minAmount: 5000, maxAmount: 90000);
      const none = GiftCardTemplateModel(id: 'z', name: LocalizedText.empty);
      expect(templateAmountLabel(_en, one), '50,000 IQD');
      expect(templateAmountLabel(_en, custom), _en.giftCardFrom('5,000 IQD'));
      expect(templateAmountLabel(_en, none), isNull);
    });
  });
}
