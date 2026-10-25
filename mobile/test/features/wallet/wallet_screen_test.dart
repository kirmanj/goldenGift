import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/wallet/presentation/screens/wallet_screen.dart';
import 'package:golden_gift/features/wallet/presentation/widgets/wallet_ui.dart';

import '../../helpers/auth_fakes.dart';
import '../referrals/rewards_test_harness.dart';

void main() {
  final en = l10nFor('en');

  Future<FakeFirebaseFirestore> seeded({int expiryDays = 0, bool withTxns = true}) async {
    final db = FakeFirebaseFirestore();
    await seedReferralSettings(db, expiryDays: expiryDays);
    await seedWallet(db, balance: 12000, credits: 5000);
    if (withTxns) {
      await seedTxn(db, 'ref',
          amount: 5000, title: 'Referral bonus', titleAr: 'مكافأة إحالة صديق', at: DateTime(2026, 10, 3, 14, 5));
      await seedTxn(db, 'pay', amount: -8000, type: 'orderPayment', bucket: 'balance', at: DateTime(2026, 10, 2, 9, 0));
      await seedTxn(db, 'refund',
          amount: 20000,
          type: 'refund',
          bucket: 'balance',
          title: 'Refund GG-2610-00001',
          at: DateTime(2026, 10, 1, 8, 0));
    }
    return db;
  }

  group('signed in', () {
    testWidgets('balance card shows the spendable total and the Balance · Credits split', (tester) async {
      await pumpRewardsApp(tester, initialPath: AppRoutes.wallet, user: FakeUser(), firestore: await seeded());
      expect(find.text(en.myWallet), findsOneWidget);
      expect(find.text(en.availableBalance), findsOneWidget);
      expect(find.text('17,000 IQD'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('wallet-balance')), matching: find.text('12,000 IQD')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('wallet-credits')), matching: find.text('5,000 IQD')),
          findsOneWidget);
      // No top-up until an online gateway exists (Phase 9).
      expect(find.byType(PrimaryButton), findsNothing);
    });

    testWidgets('transactions: newest first, signed amounts in success / error colours, bucket tags', (tester) async {
      await pumpRewardsApp(tester, initialPath: AppRoutes.wallet, user: FakeUser(), firestore: await seeded());
      expect(find.text(en.walletTransactions), findsOneWidget);
      final tiles = find.byType(WalletTxnTile);
      expect(tiles, findsNWidgets(3));

      // Title from the txn, else the localized type label.
      expect(find.text('Referral bonus'), findsOneWidget);
      expect(find.text(en.txnOrderPayment), findsOneWidget);
      expect(find.text('Refund GG-2610-00001'), findsOneWidget);
      expect(find.text('03/10/2026 14:05'), findsOneWidget);

      final context = tester.element(tiles.first);
      expect(textColor(tester, '+5,000 IQD'), successTextColor(context));
      expect(textColor(tester, '−8,000 IQD'), isNot(successTextColor(context)));
      expect(textColor(tester, '−8,000 IQD'), AppColors.error);
      expect(find.text('+20,000 IQD'), findsOneWidget);

      final ys = [
        for (final t in ['Referral bonus', en.txnOrderPayment, 'Refund GG-2610-00001'])
          tester.getTopLeft(find.text(t)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.descendant(of: tiles.first, matching: find.text(en.walletCredits)), findsOneWidget);
      expect(find.descendant(of: tiles.at(1), matching: find.text(en.walletBalance)), findsOneWidget);
    });

    testWidgets('expired credits (expireCredits) show their type label and a negative amount', (tester) async {
      final db = await seeded(withTxns: false);
      await seedTxn(db, 'exp', amount: -2000, type: 'creditExpiry');
      await pumpRewardsApp(tester, initialPath: AppRoutes.wallet, user: FakeUser(), firestore: db);
      expect(find.text(en.txnCreditExpiry), findsOneWidget);
      expect(find.text('\u22122,000 IQD'), findsOneWidget);
      expect(find.descendant(of: find.byType(WalletTxnTile), matching: find.text(en.walletCredits)), findsOneWidget);
    });

    testWidgets('empty history shows "No Transactions Yet"', (tester) async {
      await pumpRewardsApp(tester,
          initialPath: AppRoutes.wallet, user: FakeUser(), firestore: await seeded(withTxns: false));
      expect(find.text(en.noTransactionsYet), findsOneWidget);
      expect(find.text(en.transactionHistoryHint), findsOneWidget);
      expect(find.text(en.walletTransactions), findsNothing);
    });

    testWidgets('a wallet not created yet (onUserCreate pending) reads 0 IQD', (tester) async {
      await pumpRewardsApp(tester, initialPath: AppRoutes.wallet, user: FakeUser());
      expect(find.byKey(const ValueKey('wallet-spendable')), findsOneWidget);
      expect(find.text('0 IQD'), findsNWidgets(3)); // total + balance + credits
      expect(find.text(en.noTransactionsYet), findsOneWidget);
    });

    testWidgets('credits expiry note only when creditsExpiryDays > 0', (tester) async {
      await pumpRewardsApp(tester,
          initialPath: AppRoutes.wallet, user: FakeUser(), firestore: await seeded(expiryDays: 90));
      expect(find.text(en.creditsExpiryNote(90)), findsOneWidget);
      expect(find.text('Credits expire 90 days after you receive them.'), findsOneWidget);
    });

    testWidgets('no expiry note when credits never expire', (tester) async {
      await pumpRewardsApp(tester, initialPath: AppRoutes.wallet, user: FakeUser(), firestore: await seeded());
      expect(find.textContaining('expire'), findsNothing);
    });

    testWidgets('back with nothing to pop (deep link) opens the Profile tab', (tester) async {
      final app = await pumpRewardsApp(tester, initialPath: AppRoutes.wallet, user: FakeUser());
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(app.location, AppRoutes.mainTab(2));
    });
  });

  group('guest', () {
    testWidgets('sees a sign-in card instead of the balance', (tester) async {
      final app = await pumpRewardsApp(tester, initialPath: AppRoutes.wallet);
      expect(find.byKey(const ValueKey('wallet-guest-card')), findsOneWidget);
      expect(find.text(en.walletSignInBody), findsOneWidget);
      expect(find.byType(WalletBalanceCard), findsNothing);
      expect(find.byType(WalletTxnTile), findsNothing);
      await tester.tap(find.text(en.signIn));
      await tester.pumpAndSettle();
      expect(app.location, AppRoutes.signIn);
    });
  });

  group('RTL, dark mode, small screens', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('renders in $locale (${mode.name}) at 320 px with 130 % text', (tester) async {
        await pumpRewardsApp(
          tester,
          initialPath: AppRoutes.wallet,
          user: FakeUser(),
          firestore: await seeded(expiryDays: 30),
          locale: locale,
          themeMode: mode,
          size: const Size(320, 2400),
          textScale: 1.3,
        );
        final l10n = l10nFor(locale);
        expect(find.text(l10n.myWallet), findsOneWidget);
        expect(find.text(l10n.availableBalance), findsOneWidget);
        expect(Directionality.of(tester.element(find.byType(WalletBalanceCard))), TextDirection.rtl);
        // Arabic txn title; Kurdish falls back to English for this txn.
        expect(find.text(locale == 'ar' ? 'مكافأة إحالة صديق' : 'Referral bonus'), findsOneWidget);
        expect(find.text(l10n.txnOrderPayment), findsOneWidget);
        // The sign stays in front of the digits in RTL.
        expect(find.text('−8,000 IQD'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('guest card fits at 320 px with 130 % text (ckb, dark)', (tester) async {
      await pumpRewardsApp(
        tester,
        initialPath: AppRoutes.wallet,
        locale: 'ckb',
        themeMode: ThemeMode.dark,
        size: const Size(320, 1400),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
