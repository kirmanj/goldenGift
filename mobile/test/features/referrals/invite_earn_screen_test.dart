import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/referrals/presentation/screens/invite_earn_screen.dart';
import 'package:golden_gift/features/referrals/presentation/widgets/referral_rules_sheet.dart';

import '../../helpers/auth_fakes.dart';
import 'rewards_test_harness.dart';

void main() {
  final en = l10nFor('en');

  Future<FakeFirebaseFirestore> seeded({
    int joinBonus = 5000,
    int orderBonus = 5000,
    int maxPerMonth = 0,
    int expiryDays = 0,
  }) async {
    final db = FakeFirebaseFirestore();
    await seedReferralSettings(db,
        joinBonus: joinBonus, orderBonus: orderBonus, maxPerMonth: maxPerMonth, expiryDays: expiryDays);
    await seedWallet(db, balance: 40000, credits: 15000);
    await seedReferral(db, 'f1', status: 'completed', name: 'Shilan Ahmed', at: DateTime(2026, 9, 1));
    await seedReferral(db, 'f2', status: 'completed', name: 'Dara', at: DateTime(2026, 9, 20));
    await seedReferral(db, 'f3', status: 'pending', at: DateTime(2026, 10, 5));
    await seedReferral(db, 'f4', status: 'cancelled', name: 'Rebin', at: DateTime(2026, 10, 6));
    await seedReferral(db, 'other', referrer: 'someone-else', status: 'completed');
    return db;
  }

  Finder statCount(String key, String count) =>
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(count));

  testWidgets('header shows the credits; stat cards count successful / pending referrals', (tester) async {
    await pumpRewardsApp(tester, initialPath: AppRoutes.inviteAndEarn, user: FakeUser(), firestore: await seeded());
    expect(find.text(en.inviteAndEarn), findsOneWidget);
    expect(find.text(en.creditsBalance), findsOneWidget);
    expect(find.text('15,000 IQD'), findsOneWidget); // credits only, not the 40,000 balance
    expect(find.text(en.successfulReferralsHint), findsOneWidget);
    expect(find.text(en.pendingReferralsHint), findsOneWidget);
    expect(statCount('stat-successful', '2'), findsOneWidget);
    expect(statCount('stat-pending', '1'), findsOneWidget);
  });

  testWidgets('referral code box: spaced code, copy (clipboard + snackbar + analytics), reward line', (tester) async {
    final app =
        await pumpRewardsApp(tester, initialPath: AppRoutes.inviteAndEarn, user: FakeUser(), firestore: await seeded());
    expect(find.text(en.yourReferralCode), findsOneWidget);
    expect(find.byKey(const ValueKey('referral-code')), findsOneWidget);
    expect(find.text('ZQC8YC'), findsOneWidget);
    expect(find.text("Share it with friends — you'll both get 5,000 IQD"), findsOneWidget);

    await tester.tap(find.byTooltip(en.copyReferralCode));
    await tester.pump();
    expect(app.clipboard, ['ZQC8YC']);
    expect(find.text(en.codeCopied), findsOneWidget);
    expect(app.analytics.events[AnalyticsEvents.referralShare], {'method': 'copy'});
  });

  testWidgets('Invite Friends shares a localized text with the code and the /r/ link and logs referral_share',
      (tester) async {
    final app =
        await pumpRewardsApp(tester, initialPath: AppRoutes.inviteAndEarn, user: FakeUser(), firestore: await seeded());
    await tester.tap(find.byKey(const ValueKey('invite-share')));
    await tester.pumpAndSettle();
    expect(app.shares, hasLength(1));
    final text = app.shares.single.text;
    expect(text, contains('ZQC8YC'));
    expect(text, contains('https://goldengift.app/r/ZQC8YC'));
    expect(text, contains('5,000 IQD'));
    expect(app.shares.single.subject, en.referralShareSubject);
    expect(app.analytics.events[AnalyticsEvents.referralShare], {'method': 'share'});
  });

  testWidgets('a share failure shows an error instead of crashing', (tester) async {
    await pumpRewardsApp(
      tester,
      initialPath: AppRoutes.inviteAndEarn,
      user: FakeUser(),
      firestore: await seeded(),
      shareError: Exception('no share sheet'),
    );
    await tester.tap(find.byKey(const ValueKey('invite-share')));
    await tester.pumpAndSettle();
    expect(find.text(en.somethingWentWrong), findsOneWidget);
  });

  group('reward line wording', () {
    for (final (join, order, expected) in [
      (5000, 10000, 'Share it with friends — they get 5,000 IQD, you get 10,000 IQD'),
      (0, 10000, 'Share it with friends — you get 10,000 IQD after their first paid order'),
      (5000, 0, 'Share it with friends — they get 5,000 IQD when they join'),
    ]) {
      testWidgets('join $join / order $order', (tester) async {
        final app = await pumpRewardsApp(
          tester,
          initialPath: AppRoutes.inviteAndEarn,
          user: FakeUser(),
          firestore: await seeded(joinBonus: join, orderBonus: order),
        );
        expect(find.text(expected), findsOneWidget);
        if (join == 0) {
          await tester.tap(find.byKey(const ValueKey('invite-share')));
          await tester.pumpAndSettle();
          expect(app.shares.single.text, en.referralShareTextNoBonus('ZQC8YC', 'https://goldengift.app/r/ZQC8YC'));
        }
      });
    }

    testWidgets('no line when both bonuses are 0', (tester) async {
      await pumpRewardsApp(
        tester,
        initialPath: AppRoutes.inviteAndEarn,
        user: FakeUser(),
        firestore: await seeded(joinBonus: 0, orderBonus: 0),
      );
      expect(find.textContaining('Share it with friends'), findsNothing);
    });
  });

  testWidgets('while onUserCreate has not written the code: skeleton, Invite and copy disabled', (tester) async {
    final app = await pumpRewardsApp(
      tester,
      initialPath: AppRoutes.inviteAndEarn,
      user: FakeUser(),
      profile: rewardsUser(referralCode: null),
      firestore: await seeded(),
      settle: false,
    );
    expect(find.byKey(const ValueKey('referral-code-skeleton')), findsOneWidget);
    expect(find.byKey(const ValueKey('referral-code')), findsNothing);
    final invite = tester.widget<PrimaryButton>(find.byKey(const ValueKey('invite-share')));
    expect(invite.onPressed, isNull);
    await tester.tap(find.byTooltip(en.copyReferralCode), warnIfMissed: false);
    await tester.pump();
    expect(app.clipboard, isEmpty);
  });

  testWidgets('Learn more opens the rules with amounts, cap, expiry, "delivered and paid" and fair use',
      (tester) async {
    await pumpRewardsApp(
      tester,
      initialPath: AppRoutes.inviteAndEarn,
      user: FakeUser(),
      firestore: await seeded(joinBonus: 3000, orderBonus: 7000, maxPerMonth: 10, expiryDays: 180),
    );
    await tester.tap(find.byKey(const ValueKey('invite-learn-more')));
    await tester.pumpAndSettle();
    expect(find.byType(ReferralRulesSheet), findsOneWidget);
    expect(find.text(en.referralRulesTitle), findsOneWidget);
    expect(find.text('Your friend signs up with your code and gets 3,000 IQD in credits.'), findsOneWidget);
    expect(find.text('You get 7,000 IQD in credits when their first order is delivered and paid.'), findsOneWidget);
    expect(find.text('You can be rewarded for up to 10 friends per month.'), findsOneWidget);
    expect(find.text('Credits expire 180 days after you receive them.'), findsOneWidget);
    expect(find.text(en.referralRuleFairUse), findsOneWidget);
    await tester.tap(find.text(en.ok));
    await tester.pumpAndSettle();
    expect(find.byType(ReferralRulesSheet), findsNothing);
  });

  testWidgets('rules hide the monthly cap and expiry when they are 0', (tester) async {
    await pumpRewardsApp(tester, initialPath: AppRoutes.inviteAndEarn, user: FakeUser(), firestore: await seeded());
    await tester.tap(find.byKey(const ValueKey('invite-learn-more')));
    await tester.pumpAndSettle();
    expect(find.textContaining('per month'), findsNothing);
    expect(find.textContaining('expire'), findsNothing);
    expect(find.text(en.referralRuleSpend), findsOneWidget);
  });

  testWidgets('invited friends: first name (or "A friend"), status and date, newest first', (tester) async {
    await pumpRewardsApp(tester, initialPath: AppRoutes.inviteAndEarn, user: FakeUser(), firestore: await seeded());
    expect(find.text(en.referralInvitesTitle), findsOneWidget);
    expect(find.text('Shilan'), findsOneWidget);
    expect(find.text('Dara'), findsOneWidget);
    expect(find.text(en.referralAFriend), findsOneWidget);
    expect(find.text('Rebin'), findsOneWidget);
    expect(find.text(en.referralStatusCompleted), findsNWidgets(2));
    expect(find.text(en.referralStatusPending), findsOneWidget);
    expect(find.text(en.referralStatusCancelled), findsOneWidget);
    expect(find.text('05/10/2026'), findsOneWidget);
    final ys = [
      for (final n in ['Rebin', en.referralAFriend, 'Dara', 'Shilan']) tester.getTopLeft(find.text(n)).dy
    ];
    expect(ys, orderedEquals([...ys]..sort()));
  });

  testWidgets('guests see a sign-in card', (tester) async {
    final app = await pumpRewardsApp(tester, initialPath: AppRoutes.inviteAndEarn, firestore: await seeded());
    expect(find.byKey(const ValueKey('invite-guest-card')), findsOneWidget);
    expect(find.text(en.inviteSignInBody), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-share')), findsNothing);
    await tester.tap(find.text(en.signUp));
    await tester.pumpAndSettle();
    expect(app.location, AppRoutes.signUp);
  });

  for (final (locale, mode) in [('ar', ThemeMode.light), ('ar', ThemeMode.dark), ('ckb', ThemeMode.dark)]) {
    testWidgets('renders in $locale (${mode.name}) at 320 px with 130 % text', (tester) async {
      final app = await pumpRewardsApp(
        tester,
        initialPath: AppRoutes.inviteAndEarn,
        user: FakeUser(),
        firestore: await seeded(joinBonus: 5000, orderBonus: 10000, maxPerMonth: 5, expiryDays: 90),
        locale: locale,
        themeMode: mode,
        size: const Size(320, 3200),
        textScale: 1.3,
      );
      final l10n = l10nFor(locale);
      expect(find.text(l10n.successfulReferrals), findsOneWidget);
      expect(Directionality.of(tester.element(find.byType(InviteEarnScreen))), TextDirection.rtl);
      // The Latin code stays left-to-right.
      expect(Directionality.of(tester.element(find.text('ZQC8YC'))), TextDirection.ltr);
      await tester.tap(find.byKey(const ValueKey('invite-share')));
      await tester.pumpAndSettle();
      expect(app.shares.single.text, l10n.referralShareText('5,000 IQD', 'ZQC8YC', 'https://goldengift.app/r/ZQC8YC'));
      await tester.tap(find.byKey(const ValueKey('invite-learn-more')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.referralRulesTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
