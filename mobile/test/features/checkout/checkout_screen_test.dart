import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/orders/data/orders_repository.dart';
import 'package:golden_gift/features/promo_codes/data/promo_repository.dart';
import 'package:golden_gift/features/wallet/data/wallet_repository.dart';
import 'package:golden_gift/models/address_model.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/product_model.dart';

import 'phase6_test_harness.dart';

final _en = l10nFor('en');
const _placeKey = ValueKey('place-order');

final _products = {'box': testProduct('box'), 'mug': testProduct('mug')};
final _lines = [testLine('l1', 'box'), testLine('l2', 'mug')];

Future<Phase6Harness> _pumpCheckout(
  WidgetTester tester, {
  DateTime? now,
  GeneralSettings settings = const GeneralSettings(),
  PaymentSettings payments = const PaymentSettings(),
  List<CartItemModel>? cartItems,
  Map<String, ProductModel>? cartProducts,
  List<AddressModel>? addresses,
  bool guest = false,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 2400),
  double textScale = 1,
  Future<void> Function(FakeFirebaseFirestore db)? seed,
}) async {
  final db = FakeFirebaseFirestore();
  for (final a in addresses ?? [testAddress('a1', isDefault: true)]) {
    await seedAddress(db, a);
  }
  await seed?.call(db);
  return pumpPhase6(
    tester,
    initialPath: AppRoutes.checkout,
    firestore: db,
    guest: guest,
    cartItems: cartItems ?? _lines,
    cartProducts: cartProducts ?? _products,
    settings: settings,
    payments: payments,
    now: now,
    locale: locale,
    themeMode: themeMode,
    size: size,
    textScale: textScale,
  );
}

CategoryChip _dateChip(WidgetTester tester, String iso) =>
    tester.widget<CategoryChip>(find.byKey(ValueKey('date-$iso')));

void main() {
  group('delivery date & slot (SRS §5.11)', () {
    testWidgets('before the cut-off the earliest date is today; after it, tomorrow', (tester) async {
      await _pumpCheckout(tester, now: DateTime(2026, 10, 21, 9));
      expect(_dateChip(tester, '2026-10-21').selected, isTrue);
      expect(_dateChip(tester, '2026-10-21').label, _en.today);
      expect(_dateChip(tester, '2026-10-22').label, _en.tomorrow);
      expect(_dateChip(tester, '2026-10-23').label, '23/10');
    });

    testWidgets('ordering after the cut-off starts tomorrow', (tester) async {
      await _pumpCheckout(tester, now: DateTime(2026, 10, 21, 15));
      expect(find.byKey(const ValueKey('date-2026-10-21')), findsNothing);
      expect(_dateChip(tester, '2026-10-22').selected, isTrue);
      expect(find.byKey(const ValueKey('slot-morning')), findsOneWidget);
    });

    testWidgets('preparation days push the earliest date', (tester) async {
      await _pumpCheckout(
        tester,
        now: DateTime(2026, 10, 21, 9),
        cartItems: [testLine('l1', 'box', preparationDays: 2), testLine('l2', 'mug')],
      );
      expect(find.byKey(const ValueKey('date-2026-10-22')), findsNothing);
      expect(_dateChip(tester, '2026-10-23').selected, isTrue);
    });

    testWidgets('today offers only the slots that have not started', (tester) async {
      final h = await _pumpCheckout(tester, now: DateTime(2026, 10, 21, 13, 30));
      expect(_dateChip(tester, '2026-10-21').selected, isTrue);
      expect(find.byKey(const ValueKey('slot-morning')), findsNothing);
      expect(find.byKey(const ValueKey('slot-afternoon')), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-evening')), findsOneWidget);
      expect(find.text('14:00–18:00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('date-2026-10-22')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slot-morning')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('slot-evening')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      final request = h.orders.placeRequests.single;
      expect(request.deliveryDate, DateTime(2026, 10, 22));
      expect(request.deliverySlot, 'evening');
    });

    testWidgets('no slots left today → message and the next date is picked', (tester) async {
      await _pumpCheckout(
        tester,
        now: DateTime(2026, 10, 21, 19),
        settings: const GeneralSettings(sameDayCutoff: '20:00'),
      );
      expect(find.byKey(const ValueKey('no-slots-today')), findsOneWidget);
      expect(find.text(_en.noSlotsToday), findsOneWidget);
      expect(_dateChip(tester, '2026-10-21').onTap, isNull);
      expect(_dateChip(tester, '2026-10-22').selected, isTrue);
      expect(find.byKey(const ValueKey('slot-morning')), findsOneWidget);
    });
  });

  group('address & city (SRS §4.3)', () {
    testWidgets('a line restricted to other cities shows its own error and blocks Place order', (tester) async {
      await _pumpCheckout(tester, cartProducts: {
        'box': testProduct('box', availableCities: ['duhok']),
        'mug': testProduct('mug'),
      });
      expect(find.text(_en.itemNotDeliverableToCity('Gift Box')), findsOneWidget);
      expect(find.text(_en.itemNotDeliverableToCity('Photo Mug')), findsNothing);
      expect(primaryButton(tester, _placeKey).onPressed, isNull);
    });

    testWidgets('a city that is not served blocks every line', (tester) async {
      await _pumpCheckout(tester, addresses: [testAddress('a1', city: 'baghdad', isDefault: true)]);
      expect(find.text(_en.itemNotDeliverableToCity('Gift Box')), findsOneWidget);
      expect(find.text(_en.itemNotDeliverableToCity('Photo Mug')), findsOneWidget);
      expect(primaryButton(tester, _placeKey).onPressed, isNull);
    });

    testWidgets('change opens the address picker and uses the chosen address + its city fee', (tester) async {
      await _pumpCheckout(tester, addresses: [
        testAddress('a1', isDefault: true),
        testAddress('a2', label: 'Work', city: 'duhok'),
      ]);
      expect(find.text('75,000 IQD'), findsNWidgets(2)); // 70,000 + Erbil 5,000
      await tester.tap(find.byKey(const ValueKey('change-address')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('address-a2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('address-a2')));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Duhok'), findsOneWidget);
      expect(find.text('4,000 IQD'), findsOneWidget);
      expect(find.text('74,000 IQD'), findsNWidgets(2));
    });

    testWidgets('without an address: Add address → form → back with the new address', (tester) async {
      final h = await _pumpCheckout(tester, addresses: const []);
      expect(primaryButton(tester, _placeKey).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('checkout-add-address')));
      await tester.pumpAndSettle();

      Future<void> type(String key, String text) async {
        await tester.enterText(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)), text);
      }

      await type('address-label', 'Home');
      await type('address-name', 'Sara Ahmed');
      await type('address-phone', '0750 123 4567');
      await type('address-area', 'Ankawa');
      await type('address-street', '100m Road');
      await tester.tap(find.byKey(const ValueKey('address-city')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('city-erbil')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('address-save')));
      await tester.pumpAndSettle();

      expect(h.location, AppRoutes.checkout);
      expect(find.text('Home'), findsOneWidget);
      expect(primaryButton(tester, _placeKey).onPressed, isNotNull);
      final saved = await h.firestore.collection('users/u1/addresses').get();
      expect(saved.docs.single.data()['phone'], '+9647501234567');
    });
  });

  group('placing the order', () {
    testWidgets('a retry reuses ONE clientRequestId; success opens Order Success', (tester) async {
      final h = await _pumpCheckout(tester);
      expect(h.analytics.events.containsKey(AnalyticsEvents.beginCheckout), isTrue);
      h.orders.placeResults.add(const OrderFailure(OrderFailureReason.unavailable));

      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      expect(find.text(_en.orderFailedUnavailable), findsOneWidget);
      expect(h.location, AppRoutes.checkout);

      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      expect(h.orders.placeRequests, hasLength(2));
      final ids = h.orders.placeRequests.map((r) => r.clientRequestId).toSet();
      expect(ids, hasLength(1));
      expect(ids.single, isNotEmpty);
      final r = h.orders.placeRequests.last;
      expect(r.addressId, 'a1');
      expect(r.deliveryDate, DateTime(2026, 10, 21));
      expect(r.deliverySlot, 'morning');
      expect(r.paymentMethod, PaymentMethod.cashOnDelivery);
      expect(r.isGift, isFalse);

      expect(h.location, AppRoutes.orderSuccessFor('o-new'));
      expect(h.analytics.events[AnalyticsEvents.purchase],
          {'currency': 'IQD', 'value': 75000, 'transaction_id': 'GG-2610-00042'});
      expect(h.cart.items, isEmpty);
    });

    testWidgets('a blocking overlay shows while placeOrder runs', (tester) async {
      final h = await _pumpCheckout(tester);
      final gate = Completer<void>();
      h.orders.placeGate = gate;
      await tester.tap(find.byKey(_placeKey));
      await tester.pump();
      expect(find.byKey(const ValueKey('placing-overlay')), findsOneWidget);
      expect(find.text(_en.placingOrder), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.orderSuccessFor('o-new'));
    });

    for (final (reason, message) in [
      (OrderFailureReason.cartChanged, _en.orderFailedCartChanged),
      (OrderFailureReason.outOfStock, _en.orderFailedOutOfStock),
    ]) {
      testWidgets('${reason.name} → message and back to the cart', (tester) async {
        final h = await _pumpCheckout(tester);
        h.orders.placeResults.add(OrderFailure(reason, productIds: const ['box']));
        await tester.tap(find.byKey(_placeKey));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(find.text('main tab 1'), findsOneWidget);
      });
    }

    for (final (reason, message) in [
      (OrderFailureReason.cityNotAllowed, _en.orderFailedCity),
      (OrderFailureReason.minimumNotMet, _en.minimumOrderNotMet('0 IQD')),
      (OrderFailureReason.unknown, _en.somethingWentWrong),
    ]) {
      testWidgets('${reason.name} → "$message" and stays', (tester) async {
        final h = await _pumpCheckout(tester);
        h.orders.placeResults.add(OrderFailure(reason));
        await tester.tap(find.byKey(_placeKey));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(h.location, AppRoutes.checkout);
      });
    }

    testWidgets('gift options are sent with the order', (tester) async {
      final h = await _pumpCheckout(tester);
      expect(find.byKey(const ValueKey('gift-message')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('gift-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hide-prices-switch')));
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('gift-message')), matching: find.byType(TextField)),
        'Happy birthday',
      );
      await tester.pumpAndSettle();
      expect(find.text('14/200'), findsOneWidget);
      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      final r = h.orders.placeRequests.single;
      expect(r.isGift, isTrue);
      expect(r.hidePrices, isTrue);
      expect(r.giftMessage, 'Happy birthday');
    });
  });

  testWidgets('below the minimum order: message and Place order disabled', (tester) async {
    await _pumpCheckout(tester, settings: const GeneralSettings(minOrder: 100000));
    expect(find.text(_en.minimumOrderNotMet('100,000 IQD')), findsOneWidget);
    expect(primaryButton(tester, _placeKey).onPressed, isNull);
  });

  testWidgets('summary: subtotal + the city delivery fee = total', (tester) async {
    await _pumpCheckout(tester);
    expect(find.text('70,000 IQD'), findsOneWidget);
    expect(find.text('5,000 IQD'), findsOneWidget);
    expect(find.text('75,000 IQD'), findsNWidgets(2)); // summary + sticky bar
  });

  testWidgets('payment: enabled methods are listed; cash and wallet selectable, card not yet', (tester) async {
    await _pumpCheckout(tester, payments: const PaymentSettings(wallet: true, card: true));
    final cod = tester.widget<RadioListTile<PaymentMethod>>(find.byKey(const ValueKey('payment-cashOnDelivery')));
    final wallet = tester.widget<RadioListTile<PaymentMethod>>(find.byKey(const ValueKey('payment-wallet')));
    final card = tester.widget<RadioListTile<PaymentMethod>>(find.byKey(const ValueKey('payment-card')));
    expect(cod.enabled, isNot(false));
    expect(wallet.enabled, isNot(false));
    expect(card.enabled, isFalse);
  });

  group('promo, credits and wallet (Phase 7)', () {
    Future<void> seedWallet(FakeFirebaseFirestore db, {int balance = 0, int credits = 0}) =>
        db.doc(FirestorePaths.walletDoc('u1')).set({'balance': balance, 'credits': credits, 'currency': 'IQD'});
    Future<void> seedPromo(FakeFirebaseFirestore db) => db.doc('${FirestorePaths.promoCodes}/GOLD10').set({
          'code': 'GOLD10',
          'title': '10% off',
          'type': 'percent',
          'value': 10,
          'isActive': true,
          'isPublic': true,
          'perUserLimit': 1,
        });

    testWidgets('an applied code and credits lower the total and are sent to placeOrder', (tester) async {
      final h = await _pumpCheckout(tester, seed: (db) async {
        await seedWallet(db, credits: 10000);
        await seedPromo(db);
      });
      h.container.read(appliedPromoProvider.notifier).apply('gold10');
      await tester.pumpAndSettle();
      // 70,000 − 7,000 promo + 5,000 delivery − 10,000 credits = 58,000.
      expect(find.text(CurrencyFormatter.format(58000)), findsWidgets);

      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      final r = h.orders.placeRequests.single;
      expect(r.promoCode, 'GOLD10');
      expect(r.useCredits, isTrue);
      expect(r.useWallet, isFalse);
      expect(h.container.read(appliedPromoProvider), isNull);
    });

    testWidgets('turning credits off keeps them', (tester) async {
      final h = await _pumpCheckout(tester, seed: (db) => seedWallet(db, credits: 10000));
      h.container.read(useCreditsProvider.notifier).state = false;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      expect(h.orders.placeRequests.single.useCredits, isFalse);
    });

    testWidgets('wallet payment must cover the rest; then it is sent with useWallet', (tester) async {
      final h = await _pumpCheckout(tester,
          payments: const PaymentSettings(wallet: true), seed: (db) => seedWallet(db, balance: 20000));
      await tester.tap(find.byKey(const ValueKey('payment-wallet')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wallet-short')), findsOneWidget);
      expect(primaryButton(tester, _placeKey).onPressed, isNull);

      await h.firestore.doc(FirestorePaths.walletDoc('u1')).set({'balance': 100000, 'credits': 0});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wallet-short')), findsNothing);
      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      final r = h.orders.placeRequests.single;
      expect(r.paymentMethod, PaymentMethod.wallet);
      expect(r.useWallet, isTrue);
    });

    testWidgets('a code the server rejects is removed with a message', (tester) async {
      final h = await _pumpCheckout(tester, seed: seedPromo);
      h.container.read(appliedPromoProvider.notifier).apply('GOLD10');
      await tester.pumpAndSettle();
      h.orders.placeResults.add(const OrderFailure(OrderFailureReason.promoInvalid));
      await tester.tap(find.byKey(_placeKey));
      await tester.pumpAndSettle();
      expect(find.text(_en.orderFailedPromo), findsOneWidget);
      expect(h.container.read(appliedPromoProvider), isNull);
      expect(h.location, AppRoutes.checkout);
    });
  });

  testWidgets('an unavailable cart line blocks Place order until removed', (tester) async {
    await _pumpCheckout(tester, cartProducts: {'box': testProduct('box')}); // the mug is gone
    expect(find.byKey(const ValueKey('remove-unavailable')), findsOneWidget);
    expect(primaryButton(tester, _placeKey).onPressed, isNull);
  });

  testWidgets('invalid-argument (slot / payment no longer allowed) has its own message', (tester) async {
    final h = await _pumpCheckout(tester);
    h.orders.placeResults.add(const OrderFailure(OrderFailureReason.invalidChoice));
    await tester.tap(find.byKey(_placeKey));
    await tester.pumpAndSettle();
    expect(find.text(_en.orderFailedInvalidChoice), findsOneWidget);
    expect(h.location, AppRoutes.checkout);
  });

  testWidgets('wallet / card hidden when disabled in app_settings/payments', (tester) async {
    await _pumpCheckout(tester, payments: const PaymentSettings(wallet: false));
    expect(find.byKey(const ValueKey('payment-cashOnDelivery')), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-wallet')), findsNothing);
    expect(find.byKey(const ValueKey('payment-card')), findsNothing);
  });

  testWidgets('an empty cart goes back to the cart', (tester) async {
    await _pumpCheckout(tester, cartItems: const []);
    expect(find.text('main tab 1'), findsOneWidget);
  });

  testWidgets('guests get "Sign in to continue"; closing it leaves checkout', (tester) async {
    await _pumpCheckout(tester, guest: true);
    expect(find.text(_en.signInToContinue), findsWidgets);
    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await tester.pumpAndSettle();
    expect(find.text('main tab 1'), findsOneWidget);
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [
      ('ar', ThemeMode.light),
      ('ar', ThemeMode.dark),
      ('ckb', ThemeMode.light),
      ('ckb', ThemeMode.dark),
      ('en', ThemeMode.dark),
    ]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await _pumpCheckout(
          tester,
          locale: locale,
          themeMode: mode,
          cartProducts: {
            'box': testProduct('box', availableCities: ['duhok']),
            'mug': testProduct('mug')
          },
          settings: const GeneralSettings(minOrder: 100000),
        );
        await tester.tap(find.byKey(const ValueKey('gift-switch')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(_placeKey), findsOneWidget);
      });
    }

    testWidgets('320 px wide with 1.3× text (Kurdish)', (tester) async {
      await _pumpCheckout(
        tester,
        locale: 'ckb',
        size: const Size(320, 3000),
        textScale: 1.3,
        payments: const PaymentSettings(wallet: true, card: true),
        cartProducts: {
          'box': testProduct('box', availableCities: ['duhok']),
          'mug': testProduct('mug')
        },
        settings: const GeneralSettings(minOrder: 100000),
      );
      await tester.tap(find.byKey(const ValueKey('gift-switch')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 px wide with 1.3× text (English)', (tester) async {
      await _pumpCheckout(tester, size: const Size(320, 3000), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });
}
