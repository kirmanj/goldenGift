import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/referral_model.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/referrals/data/referrals_admin_data.dart';
import 'package:golden_gift_admin/features/referrals/referral_ui.dart';
import 'package:golden_gift_admin/features/referrals/referrals_screen.dart';

import '../categories/admin_test_harness.dart';
import '../users/users_test_helpers.dart';

UserModel user(String uid, {String? deviceId, bool blocked = false}) =>
    UserModel(uid: uid, name: uid, phone: '', deviceId: deviceId, isBlocked: blocked);

ReferralModel referral({List<String> flags = const [], String referrer = 'a', String referred = 'b'}) =>
    ReferralModel(id: referred, referrerUid: referrer, referredUid: referred, code: 'CODE12', flags: flags);

/// Referrer Sara (dev-1); friends Dilan (same device!) and Karwan (own device).
Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  await seedUser(db, 'u1', userMap(deviceId: 'dev-1'));
  await seedUser(db, 'u2', userMap(name: 'Dilan', phone: '7801112233', deviceId: 'dev-1'));
  await seedUser(db, 'u3', userMap(name: 'Karwan', phone: '7709998877', deviceId: 'dev-3'));
  await seedUser(db, 'u4', userMap(name: 'Hana', phone: '7712223344', deviceId: 'dev-4'));
  await db.doc('${FirestorePaths.referrals}/u2').set(referralData(referrer: 'u1', referred: 'u2', createdAt: DateTime(2026, 10, 3)));
  await db.doc('${FirestorePaths.referrals}/u3').set(referralData(
      referrer: 'u1', referred: 'u3', status: 'completed', joinPaid: true, orderPaid: true, createdAt: DateTime(2026, 10, 2)));
  await db.doc('${FirestorePaths.referrals}/u4').set(referralData(
      referrer: 'u1', referred: 'u4', status: 'cancelled', joinPaid: true, flags: ['monthlyCap'], createdAt: DateTime(2026, 10, 1)));
  await db.doc(FirestorePaths.settingsDoc('referral'))
      .set({'joinBonus': 2000, 'orderBonus': 5000, 'maxReferralsPerMonth': 0, 'creditsExpiryDays': 0});
  return db;
}

Finder flag(String label) => find.text(label);

void main() {
  group('referralFlags', () {
    test('keeps stored flags and detects a shared device', () {
      final flags = referralFlags(referral(flags: ['monthlyCap']),
          referrer: user('a', deviceId: 'd1'), referred: user('b', deviceId: 'd1'));
      expect(flags, [const ReferralFlag('monthlyCap'), const ReferralFlag('sameDevice', computed: true)]);
      expect(flags.map((f) => f.label), ['Monthly cap reached', 'Same device (detected)']);
    });

    test('does not duplicate a stored same-device flag, ignores missing device ids', () {
      expect(
          referralFlags(referral(flags: ['sameDevice']), referrer: user('a', deviceId: 'd1'), referred: user('b', deviceId: 'd1')),
          [const ReferralFlag('sameDevice')]);
      expect(referralFlags(referral(), referrer: user('a'), referred: user('b')), isEmpty);
      expect(referralFlags(referral(), referrer: user('a', deviceId: 'd1'), referred: user('b', deviceId: 'd2')), isEmpty);
      // Users not loaded yet: only what is stored.
      expect(referralFlags(referral(flags: ['selfReferral'])), [const ReferralFlag('selfReferral')]);
    });

    test('detects blocked users and self-referrals', () {
      expect(referralFlags(referral(), referrer: user('a', blocked: true), referred: user('b')),
          [const ReferralFlag('blocked', computed: true)]);
      expect(referralFlags(referral(referrer: 'x', referred: 'x')), [const ReferralFlag('selfReferral', computed: true)]);
      expect(const ReferralFlag('somethingNew').label, 'somethingNew');
    });
  });

  group('ReferralsAdminRepository', () {
    test('newest first, filtered by status', () async {
      final db = await seeded();
      final repo = ReferralsAdminRepository(db);
      Future<List<String>> ids(ReferralStatus? s) async => [for (final r in await repo.watch(s).first) r.id];
      expect(await ids(null), ['u2', 'u3', 'u4']);
      expect(await ids(ReferralStatus.completed), ['u3']);
      expect(await ids(ReferralStatus.cancelled), ['u4']);
    });

    test('summary counts and the credits estimate', () async {
      final db = await seeded();
      final s = await ReferralsAdminRepository(db).summary();
      expect((s.total, s.pending, s.completed, s.cancelled), (3, 1, 1, 1));
      expect((s.joinBonusesPaid, s.orderBonusesPaid), (2, 1));
      expect(s.creditsPaidEstimate(const ReferralSettings(joinBonus: 2000, orderBonus: 5000)), 9000);
    });
  });

  group('ReferralsScreen', () {
    testWidgets('lists referrals with names, settings, totals and flags', (tester) async {
      final db = await seeded();
      await pumpWith(tester, const ReferralsScreen(), db: db, size: const Size(1440, 1400));

      // Settings card: 0 means no limit / never.
      expect(find.text('2,000 IQD'), findsOneWidget);
      expect(find.text('5,000 IQD'), findsOneWidget);
      expect(find.text('No limit'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
      expect(find.text('Edit in Settings'), findsOneWidget);
      // Totals.
      expect(find.text('9,000 IQD'), findsOneWidget);
      expect(find.textContaining('2 join + 1 order bonuses'), findsOneWidget);

      expect(find.text('Sara Ahmed'), findsNWidgets(3)); // referrer of every row
      expect(find.text('Dilan'), findsOneWidget);
      expect(find.text('Karwan'), findsOneWidget);
      expect(find.text('Hana'), findsOneWidget);
      // Stored flag + the flag computed from both users' deviceId.
      expect(flag('Monthly cap reached'), findsOneWidget);
      expect(flag('Same device (detected)'), findsOneWidget);
    });

    testWidgets('the status chips filter the table', (tester) async {
      final db = await seeded();
      await pumpWith(tester, const ReferralsScreen(), db: db, size: const Size(1440, 1400));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Completed'));
      await settle(tester);
      expect(find.text('Karwan'), findsOneWidget);
      expect(find.text('Dilan'), findsNothing);
      expect(find.text('Hana'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await settle(tester);
      expect(find.text('Dilan'), findsOneWidget);
    });

    testWidgets('names link to the user and the settings button opens Settings', (tester) async {
      final db = await seeded();
      final router = await pumpRouted(tester, location: '/referrals', db: db, size: const Size(1440, 1400));
      await tester.tap(find.text('Dilan'));
      await settleRoute(tester);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/users/u2');

      router.go('/referrals');
      await settleRoute(tester);
      await tester.tap(find.text('Edit in Settings'));
      await settleRoute(tester);
      expect(find.text('Settings page'), findsOneWidget);
    });

    testWidgets('content editors cannot open Referrals', (tester) async {
      final db = await seeded();
      await pumpWith(tester, const ReferralsScreen(), db: db, session: sessionAs(AdminRole.content));
      expect(find.text('Your role (content) cannot open Referrals.'), findsOneWidget);
      expect(find.text('Dilan'), findsNothing);

      await pumpWith(tester, const ReferralsScreen(), db: db, session: sessionAs(AdminRole.finance));
      expect(find.text('Dilan'), findsOneWidget);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final width in [800.0, 1440.0]) {
        testWidgets('renders in ${mode.name} at $width px', (tester) async {
          final db = await seeded();
          final errors = await errorsOutsideCoreNav(() async {
            await pumpWith(tester, const ReferralsScreen(), db: db, mode: mode, size: Size(width, 1000));
            expect(find.text('Referral settings'), findsOneWidget);
            expect(find.text('Credits paid (estimate)'), findsOneWidget);
          });
          expect(errors, isEmpty);
        });
      }
    }
  });
}
