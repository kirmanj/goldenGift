import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/features/promo_codes/data/promo_repository.dart';
import 'package:golden_gift/features/promo_codes/presentation/widgets/promo_ticket.dart';
import 'package:golden_gift/features/wallet/presentation/widgets/wallet_ui.dart';

import '../referrals/rewards_test_harness.dart';

void main() {
  final en = l10nFor('en');
  final now = DateTime.now();
  final soon = DateTime(now.year, now.month, now.day).add(const Duration(days: 20));
  final later = DateTime(now.year, now.month, now.day).add(const Duration(days: 90));

  Future<FakeFirebaseFirestore> seeded() async {
    final db = FakeFirebaseFirestore();
    await seedPromo(db, 'GOLD10',
        value: 10, expiresAt: soon, maxDiscount: 20000, description: 'Use GOLD10 to enjoy 10% off.');
    await seedPromo(db, 'WELCOME5',
        type: 'fixed', value: 5000, expiresAt: later, minOrder: 25000, firstOrderOnly: true);
    await seedPromo(db, 'FOREVER', value: 15);
    await seedPromo(db, 'VIPONLY', isPublic: false); // private: works in the cart only
    await seedPromo(db, 'OLD', expiresAt: now.subtract(const Duration(days: 1)));
    await seedPromo(db, 'PAUSED', isActive: false);
    return db;
  }

  testWidgets('lists public, active, unexpired codes as tickets (soonest expiry first)', (tester) async {
    await pumpRewardsApp(tester, initialPath: AppRoutes.promoCodes, firestore: await seeded());
    expect(find.text(en.promoCodes), findsOneWidget);
    expect(find.text(en.promoHeaderTitle), findsOneWidget);

    expect(find.byType(PromoTicket), findsNWidgets(3));
    for (final hidden in ['VIPONLY', 'OLD', 'PAUSED']) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
    final ys = [
      for (final c in ['GOLD10', 'WELCOME5', 'FOREVER']) tester.getTopLeft(find.text(c)).dy
    ];
    expect(ys, orderedEquals([...ys]..sort()));

    // Ribbons, description, notes and the green expiry line.
    expect(find.text('10% Off'), findsOneWidget);
    expect(find.text('5,000 IQD Off'), findsOneWidget);
    expect(find.text('Use GOLD10 to enjoy 10% off.'), findsOneWidget);
    expect(find.text(en.promoMaxDiscount('20,000 IQD')), findsOneWidget);
    expect(find.text(en.promoMinOrder('25,000 IQD')), findsOneWidget);
    expect(find.text(en.promoFirstOrderOnly), findsOneWidget);
    final expiry = en.expiresOn(AppDates.display(soon));
    expect(find.text(expiry), findsOneWidget);
    expect(textColor(tester, expiry), successTextColor(tester.element(find.text(expiry))));
    expect(find.textContaining('Expires on'), findsNWidgets(2)); // FOREVER has no expiry
  });

  testWidgets('copy puts the code on the clipboard and confirms', (tester) async {
    final app = await pumpRewardsApp(tester, initialPath: AppRoutes.promoCodes, firestore: await seeded());
    final ticket = find.byKey(const ValueKey('promo-WELCOME5'));
    await tester.tap(find.descendant(of: ticket, matching: find.byTooltip(en.promoCopyCode)));
    await tester.pump();
    expect(app.clipboard, ['WELCOME5']);
    expect(find.text(en.codeCopied), findsOneWidget);
  });

  testWidgets('Use applies the code to the cart (persisted) and opens the Cart tab', (tester) async {
    final app = await pumpRewardsApp(
      tester,
      initialPath: AppRoutes.main,
      push: [AppRoutes.promoCodes],
      firestore: await seeded(),
    );
    await tester.tap(find.byKey(const ValueKey('promo-use-GOLD10')));
    await tester.pumpAndSettle();
    expect(app.container.read(appliedPromoProvider), 'GOLD10');
    expect(app.prefs.getString(AppliedPromoController.prefsKey), 'GOLD10');
    expect(app.location, AppRoutes.mainTab(1));
    expect(find.text('main tab 1'), findsOneWidget);
    expect(find.text(en.promoAppliedSnack('GOLD10')), findsOneWidget);
  });

  testWidgets('the code already in the cart shows "Applied" instead of Use', (tester) async {
    await pumpRewardsApp(
      tester,
      initialPath: AppRoutes.promoCodes,
      firestore: await seeded(),
      prefs: {AppliedPromoController.prefsKey: 'FOREVER'},
    );
    expect(find.byKey(const ValueKey('promo-applied-FOREVER')), findsOneWidget);
    expect(find.byKey(const ValueKey('promo-use-FOREVER')), findsNothing);
    expect(find.byKey(const ValueKey('promo-use-GOLD10')), findsOneWidget);
  });

  testWidgets('no public codes: empty state', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedPromo(db, 'VIPONLY', isPublic: false);
    await pumpRewardsApp(tester, initialPath: AppRoutes.promoCodes, firestore: db);
    expect(find.byType(PromoTicket), findsNothing);
    expect(find.text(en.noPromoCodesTitle), findsOneWidget);
    expect(find.text(en.noPromoCodesBody), findsOneWidget);
  });

  for (final (locale, mode) in [('ar', ThemeMode.light), ('ckb', ThemeMode.dark), ('en', ThemeMode.dark)]) {
    testWidgets('renders in $locale (${mode.name}) at 320 px with 130 % text', (tester) async {
      await pumpRewardsApp(
        tester,
        initialPath: AppRoutes.promoCodes,
        firestore: await seeded(),
        locale: locale,
        themeMode: mode,
        size: const Size(320, 3000),
        textScale: 1.3,
      );
      final l10n = l10nFor(locale);
      expect(find.text(l10n.promoHeaderTitle), findsOneWidget);
      expect(find.text(l10n.promoPercentOff(10)), findsOneWidget);
      if (locale != 'en') {
        expect(Directionality.of(tester.element(find.byType(PromoTicket).first)), TextDirection.rtl);
        expect(find.text(locale == 'ar' ? 'استخدم GOLD10 عند الدفع' : 'GOLD10 لە کاتی پارەداندا بەکاربهێنە'),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
