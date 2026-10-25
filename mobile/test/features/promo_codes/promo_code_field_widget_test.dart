import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/utils/promo_rules.dart';
import 'package:golden_gift/features/cart/presentation/widgets/cart_line_tile.dart';
import 'package:golden_gift/features/cart/presentation/widgets/cart_summary_card.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/features/promo_codes/data/promo_repository.dart';
import 'package:golden_gift/features/promo_codes/presentation/widgets/promo_code_field.dart';
import 'package:golden_gift/features/wallet/data/wallet_repository.dart';
import 'package:golden_gift/features/wallet/presentation/widgets/use_credits_toggle.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/user_model.dart';

import '../../helpers/auth_fakes.dart';
import '../product_details/shop_test_harness.dart';
import '../referrals/rewards_test_harness.dart' show seedPromo, seedWallet;

final en = l10nFor('en');

/// 2 × 40,000 = 80,000 IQD of mugs (category "mugs").
CartItemModel _mugs({int qty = 2}) => CartItemModel(
      id: 'm',
      productId: 'mug',
      storeId: 's1',
      titleSnapshot: const LocalizedText('Photo Mug', ar: 'كوب صور', ku: 'کوپی وێنە'),
      unitPrice: 40000,
      qty: qty,
    );

const _mug = ProductModel(
  id: 'mug',
  title: LocalizedText('Photo Mug'),
  storeId: 's1',
  price: 40000,
  categoryIds: ['mugs'],
);

final _stores = {'s1': testStore('s1', 'Golden Home')};

Finder get _input =>
    find.descendant(of: find.byKey(const ValueKey('promo-code-input')), matching: find.byType(EditableText));
Finder get _summary => find.byType(CartSummaryCard);
Finder _inSummary(String text) => find.descendant(of: _summary, matching: find.text(text));
Finder get _discountRow => find.byKey(const ValueKey('cart-discount-row'));
Finder get _creditsRow => find.byKey(const ValueKey('cart-credits-row'));
Finder _total(String amount) =>
    find.descendant(of: find.byKey(const ValueKey('cart-total-row')), matching: find.text(amount));

Future<ShopHarness> _pumpCart(
  WidgetTester tester, {
  required FakeFirebaseFirestore db,
  String? applied,
  bool signedIn = false,
  UserModel? profile,
  int qty = 2,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 3200),
  double textScale = 1,
}) =>
    pumpShop(
      tester,
      initialPath: '/cart',
      cartItems: [_mugs(qty: qty)],
      cartProducts: {'mug': _mug},
      stores: _stores,
      firestore: db,
      user: signedIn ? FakeUser() : null,
      prefs: {if (applied != null) AppliedPromoController.prefsKey: applied},
      overrides: [
        if (profile != null) currentUserProfileProvider.overrideWith((ref) => Stream.value(profile)),
      ],
      locale: locale,
      themeMode: themeMode,
      size: size,
      textScale: textScale,
    );

void main() {
  group('apply / remove', () {
    testWidgets('typing a code and Apply shows the saving, the discount row and the new total', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, 'GOLD10', value: 10);
      final h = await _pumpCart(tester, db: db);

      final apply = find.byKey(const ValueKey('promo-apply'));
      expect(tester.widget<OutlinedButton>(find.descendant(of: apply, matching: find.byType(OutlinedButton))).onPressed,
          isNull);
      await tester.enterText(_input, ' gold 10 ');
      await tester.pump();
      await tester.tap(apply);
      await tester.pumpAndSettle();

      expect(h.container.read(appliedPromoProvider), 'GOLD10');
      expect(find.byKey(const ValueKey('promo-applied')), findsOneWidget);
      expect(find.text('GOLD10'), findsOneWidget);
      expect(find.text(en.promoSaved('8,000 IQD')), findsOneWidget);
      expect(find.descendant(of: _discountRow, matching: find.text(en.promoDiscountRow('GOLD10'))), findsOneWidget);
      expect(find.descendant(of: _discountRow, matching: find.text('−8,000 IQD')), findsOneWidget);
      expect(_total('72,000 IQD'), findsOneWidget);
      expect(_inSummary('80,000 IQD'), findsOneWidget); // subtotal unchanged
      // Guests never get the credits toggle.
      expect(find.byType(UseCreditsToggle), findsNothing);
    });

    testWidgets('Remove clears the code (and cart_promo) and restores the total', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, 'GOLD10', value: 10);
      final h = await _pumpCart(tester, db: db, applied: 'GOLD10');
      expect(_total('72,000 IQD'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('promo-remove')));
      await tester.pumpAndSettle();
      expect(h.container.read(appliedPromoProvider), isNull);
      expect(h.container.read(sharedPreferencesProvider).getString(AppliedPromoController.prefsKey), isNull);
      expect(find.byKey(const ValueKey('promo-code-input')), findsOneWidget);
      expect(_discountRow, findsNothing);
      expect(_inSummary('80,000 IQD'), findsNWidgets(2)); // subtotal + total
    });

    testWidgets('the code stays applied when the cart changes and is re-evaluated', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, 'BIG10', value: 10, minOrder: 100000);
      final h = await _pumpCart(tester, db: db, applied: 'BIG10');
      expect(find.text(en.promoMinOrderNotMet('100,000 IQD')), findsOneWidget);
      expect(_discountRow, findsNothing);

      await tester.tap(find.descendant(of: find.byType(CartLineTile), matching: find.byTooltip(en.increaseQuantity)));
      await tester.pumpAndSettle();
      expect(h.container.read(appliedPromoProvider), 'BIG10');
      expect(find.text(en.promoMinOrderNotMet('100,000 IQD')), findsNothing);
      expect(find.text(en.promoSaved('12,000 IQD')), findsOneWidget);
      expect(_total('108,000 IQD'), findsOneWidget);
    });
  });

  group('every rejection has its own inline message and no discount', () {
    final past = DateTime.now().subtract(const Duration(days: 2));
    final cases = <(String, Future<void> Function(FakeFirebaseFirestore), String Function(), bool, UserModel?)>[
      ('notFound', (_) async {}, () => en.promoNotFound, false, null),
      ('inactive', (db) => seedPromo(db, 'CODE', isActive: false), () => en.promoInactive, false, null),
      ('expired', (db) => seedPromo(db, 'CODE', expiresAt: past), () => en.promoExpired, false, null),
      (
        'minOrder',
        (db) => seedPromo(db, 'CODE', minOrder: 150000),
        () => en.promoMinOrderNotMet('150,000 IQD'),
        false,
        null,
      ),
      (
        'usageLimit',
        (db) => seedPromo(db, 'CODE', usageLimit: 5, usageCount: 5),
        () => en.promoUsageLimit,
        false,
        null
      ),
      (
        'notApplicable',
        (db) => seedPromo(db, 'CODE', categoryIds: ['flowers']),
        () => en.promoNotApplicable,
        false,
        null,
      ),
      (
        'perUserLimit',
        (db) async {
          await seedPromo(db, 'CODE');
          await db.doc('${FirestorePaths.promoCodes}/CODE/usages/u1').set({'count': 1});
        },
        () => en.promoPerUserLimit,
        true,
        null,
      ),
      (
        'firstOrderOnly',
        (db) => seedPromo(db, 'CODE', firstOrderOnly: true),
        () => en.promoFirstOrderOnlyError,
        true,
        const UserModel(uid: 'u1', name: 'Krmanj', phone: '7505448229', totalOrders: 3),
      ),
    ];
    for (final (name, seed, message, signedIn, profile) in cases) {
      testWidgets(name, (tester) async {
        final db = FakeFirebaseFirestore();
        await seed(db);
        await _pumpCart(tester, db: db, applied: 'CODE', signedIn: signedIn, profile: profile);
        expect(find.byKey(const ValueKey('promo-applied')), findsOneWidget);
        final shown = tester.widget<Text>(find.byKey(const ValueKey('promo-message'))).data;
        expect(shown, message());
        expect(_discountRow, findsNothing);
        expect(_inSummary('80,000 IQD'), findsNWidgets(2));
      });
    }

    test('message helper: a distinct message for every PromoRejection, in every language', () {
      for (final code in ['en', 'ar', 'ckb']) {
        final l10n = l10nFor(code);
        final messages = {for (final r in PromoRejection.values) promoRejectionMessage(l10n, r, minOrder: 25000)};
        expect(messages, hasLength(PromoRejection.values.length), reason: code);
      }
      expect(promoRejectionMessage(en, PromoRejection.minOrder, minOrder: 25000),
          'Minimum order for this code is 25,000 IQD');
    });
  });

  group('credits toggle', () {
    testWidgets('signed in with credits: on by default, deducts min(credits, due); off restores the total',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await seedWallet(db, balance: 30000, credits: 5000);
      final h = await _pumpCart(tester, db: db, signedIn: true);

      expect(find.text(en.useMyCredits('5,000 IQD')), findsOneWidget);
      expect(h.container.read(useCreditsProvider), isTrue);
      expect(find.descendant(of: _creditsRow, matching: find.text(en.walletCredits)), findsOneWidget);
      expect(find.descendant(of: _creditsRow, matching: find.text('−5,000 IQD')), findsOneWidget);
      expect(_total('75,000 IQD'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('use-credits-switch')));
      await tester.pumpAndSettle();
      expect(h.container.read(useCreditsProvider), isFalse);
      expect(_creditsRow, findsNothing);
      expect(_total('80,000 IQD'), findsOneWidget);
    });

    testWidgets('credits are capped at subtotal − discount', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedWallet(db, credits: 100000);
      await seedPromo(db, 'GOLD10', value: 10);
      await _pumpCart(tester, db: db, signedIn: true, applied: 'GOLD10');
      expect(find.descendant(of: _discountRow, matching: find.text('−8,000 IQD')), findsOneWidget);
      expect(find.descendant(of: _creditsRow, matching: find.text('−72,000 IQD')), findsOneWidget);
      expect(_total('0 IQD'), findsOneWidget);
    });

    testWidgets('hidden when the customer has no credits', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedWallet(db, balance: 50000);
      await _pumpCart(tester, db: db, signedIn: true);
      expect(find.byType(UseCreditsToggle), findsNothing);
      expect(_creditsRow, findsNothing);
    });
  });

  for (final (locale, mode) in [
    ('ar', ThemeMode.dark),
    ('ckb', ThemeMode.light),
    ('ckb', ThemeMode.dark),
    ('en', ThemeMode.light)
  ]) {
    testWidgets('promo + credits fit at 320 px with 130 % text ($locale, ${mode.name})', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedWallet(db, credits: 1250000);
      await seedPromo(db, 'GOLDEN2026', type: 'fixed', value: 15000);
      await _pumpCart(
        tester,
        db: db,
        signedIn: true,
        applied: 'GOLDEN2026',
        locale: locale,
        themeMode: mode,
        size: const Size(320, 3000),
        textScale: 1.3,
      );
      final l10n = l10nFor(locale);
      expect(find.text(l10n.promoSaved('15,000 IQD')), findsOneWidget);
      expect(find.text(l10n.useMyCredits('1,250,000 IQD')), findsOneWidget);
      if (locale != 'en') {
        expect(Directionality.of(tester.element(find.byType(PromoCodeField))), TextDirection.rtl);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty promo input + rejection fit at 320 px with 130 % text ($locale, ${mode.name})', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, 'CODE', minOrder: 1500000);
      await _pumpCart(
        tester,
        db: db,
        applied: 'CODE',
        locale: locale,
        themeMode: mode,
        size: const Size(320, 3000),
        textScale: 1.3,
      );
      expect(find.text(l10nFor(locale).promoMinOrderNotMet('1,500,000 IQD')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('promo-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('promo-code-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
