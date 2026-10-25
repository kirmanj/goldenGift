import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/models/wallet_model.dart';
import 'package:golden_gift_admin/core/router/admin_router.dart';
import 'package:golden_gift_admin/core/router/admin_routes.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/users/data/function_errors.dart';
import 'package:golden_gift_admin/features/users/data/users_admin_repository.dart';
import 'package:golden_gift_admin/features/users/user_detail_screen.dart';
import 'package:golden_gift_admin/features/users/users_screen.dart';

import '../categories/admin_test_harness.dart';
import 'users_test_helpers.dart';

/// A user with everything the detail page shows.
Future<FakeFirebaseFirestore> seedProfile({bool blocked = false, bool deleted = false, bool wallet = true}) async {
  final db = FakeFirebaseFirestore();
  await seedUser(db, 'u0', userMap(name: 'Rebaz', phone: '7709990000', email: 'rebaz@example.com', deviceId: 'dev-0'));
  await seedUser(db, 'u1', userMap(isBlocked: blocked, isDeleted: deleted, referredBy: 'u0'));
  await seedUser(db, 'u3', userMap(name: 'Dilan', phone: '7801112233', email: 'dilan@example.com', deviceId: 'dev-3'));
  if (wallet) await seedWallet(db, 'u1');
  await db.doc('${FirestorePaths.admins}/admin-1').set({'name': 'Test Admin', 'role': 'super'});
  await db.collection(FirestorePaths.walletTxns('u1')).doc('t1').set({
    'type': 'adminAdjustment',
    'amount': 10000,
    'bucket': 'balance',
    'title': 'Goodwill',
    'reason': 'Late delivery',
    'byUid': 'admin-1',
    'balanceAfter': 20000,
    'creditsAfter': 5000,
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 10)),
  });
  await db.collection(FirestorePaths.walletTxns('u1')).doc('t2').set({
    'type': 'referralCredit',
    'amount': -2500,
    'bucket': 'credits',
    'title': 'Credits used',
    'balanceAfter': 10000,
    'creditsAfter': 5000,
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 9)),
  });
  await db.doc(FirestorePaths.orderDoc('o1')).set(orderData(number: 'GG-2610-00011', createdAt: DateTime(2026, 10, 12)));
  await db.doc(FirestorePaths.orderDoc('o2')).set(orderData(number: 'GG-2610-00012', status: 'pending', total: 99000));
  await db.doc(FirestorePaths.orderDoc('o3')).set(orderData(number: 'GG-2610-00099', userId: 'someone-else'));
  await db.collection(FirestorePaths.userAddresses('u1')).doc('a1').set({
    'label': 'Home',
    'name': 'Sara',
    'phone': '7501234567',
    'city': 'erbil',
    'area': 'Ankawa',
    'street': '100m road',
    'isDefault': true,
  });
  await db.doc('${FirestorePaths.referrals}/u3').set(referralData(referrer: 'u1', referred: 'u3', flags: ['monthlyCap']));
  return db;
}

Finder button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

bool enabled(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(button(label)).onPressed != null;

void main() {
  test('the dashboard router serves the Phase 7 pages', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(adminRouterProvider);
    final paths = router.configuration.routes.whereType<GoRoute>().map((r) => r.path).toSet();
    expect(paths, containsAll([AdminRoutes.users, AdminRoutes.userDetail, AdminRoutes.promoCodes, AdminRoutes.referrals]));
    expect(AdminRoutes.user('u1'), '/users/u1');
  });

  group('WalletAdjustment', () {
    const wallet = WalletModel(balance: 20000, credits: 5000);
    WalletAdjustment adj(int amount, {String reason = 'Goodwill', WalletBucket bucket = WalletBucket.balance}) =>
        WalletAdjustment(uid: 'u1', bucket: bucket, amount: amount, reason: reason);

    test('a valid adjustment passes and builds the callable payload', () {
      final a = adj(-5000, reason: '  Expired credit  ', bucket: WalletBucket.credits);
      expect(a.validate(wallet), isEmpty);
      expect(a.resultFor(wallet), 0);
      expect(a.toPayload(), {'uid': 'u1', 'bucket': 'credits', 'amount': -5000, 'reason': 'Expired credit'});
    });

    test('the idempotency key is sent when set', () {
      const a = WalletAdjustment(uid: 'u1', bucket: WalletBucket.balance, amount: 1000, reason: 'Goodwill', requestId: 'r-1');
      expect(a.toPayload()['requestId'], 'r-1');
    });

    test('refuses zero, too large, a short reason and a negative result', () {
      expect(adj(0).validate(wallet), contains('Enter an amount other than 0.'));
      expect(adj(10000001).validate(wallet).single, contains('At most 10,000,000 IQD'));
      expect(adj(1000, reason: ' a ').validate(wallet).single, contains('at least 3 characters'));
      expect(adj(1000, reason: 'x' * 301).validate(wallet).single, contains('under 300'));
      expect(adj(-20001).validate(wallet).single, contains('below zero'));
      expect(adj(-6000, bucket: WalletBucket.credits).validate(wallet).single, contains('credits below zero'));
      expect(adj(-20000).validate(wallet), isEmpty);
    });

    test('the repository refuses invalid input without calling the function', () async {
      final calls = FakeCalls();
      final repo = UsersAdminRepository(FakeFirebaseFirestore(), calls.call);
      await expectLater(repo.adjustWallet(adj(-30000), current: wallet), throwsA(isA<WalletAdjustmentInvalid>()));
      expect(calls.sent, isEmpty);
    });

    test('the repository sends adjustWallet and reads the new amounts', () async {
      final calls = FakeCalls()..responses['adjustWallet'] = {'balance': 25000, 'credits': 5000, 'txnId': 'tx9'};
      final repo = UsersAdminRepository(FakeFirebaseFirestore(), calls.call);
      final r = await repo.adjustWallet(adj(5000), current: wallet);
      expect(calls.sent.single.$1, 'adjustWallet');
      expect(calls.sent.single.$2, {'uid': 'u1', 'bucket': 'balance', 'amount': 5000, 'reason': 'Goodwill'});
      expect((r.balance, r.credits, r.txnId), (25000, 5000, 'tx9'));
    });
  });

  group('setUserBlocked payload', () {
    test('includes a trimmed reason only when given', () {
      expect(UsersAdminRepository.blockPayload(uid: 'u1', blocked: true, reason: ' Fraud '),
          {'uid': 'u1', 'blocked': true, 'reason': 'Fraud'});
      expect(UsersAdminRepository.blockPayload(uid: 'u1', blocked: false, reason: '  '), {'uid': 'u1', 'blocked': false});
    });
  });

  group('functionErrorMessage', () {
    FirebaseFunctionsException ex(String code, [String message = '', Object? details]) =>
        FirebaseFunctionsException(code: code, message: message, details: details);

    test('maps an undeployed function', () {
      for (final e in [ex('not-found', 'NOT_FOUND'), ex('not-found'), ex('unavailable', 'x'), ex('internal', 'INTERNAL'), ex('unimplemented')]) {
        expect(functionErrorMessage('adjustWallet', e), 'The adjustWallet function is not deployed yet.', reason: e.code);
      }
    });

    test('keeps real server errors', () {
      expect(functionErrorMessage('adjustWallet', ex('not-found', 'No wallet for u1')), 'Not found: No wallet for u1.');
      expect(functionErrorMessage('adjustWallet', ex('permission-denied', 'finance only')), contains('not allowed'));
      expect(functionErrorReason(ex('failed-precondition', 'x', {'reason': 'insufficient_funds'})), 'insufficient_funds');
      expect(isFunctionMissing(StateError('x')), isFalse);
    });
  });

  group('UsersScreen', () {
    testWidgets('lists users with phone, email, totals and state chips', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedUser(db, 'u1', userMap(isBlocked: true, createdAt: DateTime(2026, 10, 2)));
      await seedUser(db, 'u2',
          userMap(name: 'Karwan', phone: '7709998877', email: 'k@example.com', isDeleted: true, totalOrders: 7, createdAt: DateTime(2026, 10, 1)));
      await pumpWith(tester, const UsersScreen(), db: db);

      expect(find.text('Sara Ahmed'), findsOneWidget);
      expect(find.text('Karwan'), findsOneWidget);
      expect(find.text('+964 7501234567'), findsOneWidget);
      expect(tester.widget<Text>(find.text('+964 7501234567')).textDirection, TextDirection.ltr);
      expect(find.text('sara@example.com'), findsOneWidget);
      expect(find.text('80,000 IQD'), findsNWidgets(2));
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);
    });

    testWidgets('searching by phone narrows the list and explains the mode', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedUser(db, 'u1', userMap());
      await seedUser(db, 'u2', userMap(name: 'Karwan', phone: '7709998877', email: 'k@example.com'));
      await pumpWith(tester, const UsersScreen(), db: db);

      await tester.enterText(find.byKey(const ValueKey('user-search')), '0770 999 8877');
      await tester.tap(find.text('Search'));
      await settle(tester);
      expect(find.text('Sara Ahmed'), findsNothing);
      expect(find.text('Karwan'), findsOneWidget);
      expect(find.textContaining('Phone +9647709998877'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('user-search')), 'nobody@example.com');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.text('No users match.'), findsOneWidget);
    });

    testWidgets('a row opens /users/:id with the whole profile', (tester) async {
      final db = await seedProfile();
      final router = await pumpRouted(tester, location: '/users', db: db);
      await tester.tap(find.text('Sara Ahmed'));
      await settleRoute(tester);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/users/u1');

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('SARA12'), findsOneWidget);
      expect(find.text('dev-1'), findsOneWidget);
      expect(find.text('Rebaz'), findsOneWidget); // referred by (link)
      expect(find.text('20,000 IQD'), findsWidgets); // balance
      expect(find.text('5,000 IQD'), findsWidgets); // credits
      expect(find.textContaining('Admin adjustment · Goodwill — “Late delivery”'), findsOneWidget);
      expect(find.textContaining('by Test Admin'), findsOneWidget);
      expect(find.text('+10,000 IQD'), findsOneWidget);
      expect(find.text('−2,500 IQD'), findsOneWidget);
      expect(find.text('GG-2610-00011'), findsOneWidget);
      expect(find.text('GG-2610-00012'), findsOneWidget);
      expect(find.text('GG-2610-00099'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Dilan'), findsOneWidget); // referral made
      expect(find.text('Monthly cap reached'), findsOneWidget);

      // The referrer link opens their page.
      await tester.tap(find.text('Rebaz'));
      await settleRoute(tester);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/users/u0');
      expect(find.text('rebaz@example.com'), findsOneWidget);
    });

    for (final mode in ThemeMode.values.where((m) => m != ThemeMode.system)) {
      for (final width in [800.0, 1440.0]) {
        testWidgets('list and detail render in ${mode.name} at $width px', (tester) async {
          final db = await seedProfile();
          final errors = await errorsOutsideCoreNav(() async {
            await pumpWith(tester, const UsersScreen(), db: db, mode: mode, size: Size(width, 1000));
            expect(find.text('Sara Ahmed'), findsOneWidget);
            await pumpWith(tester, const UserDetailScreen(uid: 'u1'), db: db, mode: mode, size: Size(width, 1600));
            expect(find.text('Wallet'), findsOneWidget);
            expect(find.text('Adjust wallet'), findsOneWidget);
          });
          expect(errors, isEmpty);
        });
      }
    }
  });

  group('Block / unblock', () {
    testWidgets('block needs a reason, then calls setUserBlocked', (tester) async {
      final db = await seedProfile();
      final calls = FakeCalls();
      await pumpWith(tester, const UserDetailScreen(uid: 'u1'), db: db, calls: calls);

      await tester.tap(find.text('Block'));
      await settle(tester);
      expect(find.text('Block Sara Ahmed?'), findsOneWidget);
      await tester.tap(find.text('Block user'));
      await settle(tester);
      expect(find.text('A reason of at least 3 characters is required'), findsOneWidget);
      expect(calls.sent, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('block-reason')), ' Fraudulent orders ');
      await tester.tap(find.text('Block user'));
      await settle(tester);
      expect(calls.sent.single.$1, 'setUserBlocked');
      expect(calls.sent.single.$2, {'uid': 'u1', 'blocked': true, 'reason': 'Fraudulent orders'});
      expect(find.text('User blocked and signed out of every device.'), findsOneWidget);
      // The dashboard never writes isBlocked itself.
      expect((await db.doc(FirestorePaths.userDoc('u1')).get()).data()!['isBlocked'], isFalse);
    });

    testWidgets('unblock sends blocked: false with an optional reason', (tester) async {
      final db = await seedProfile(blocked: true);
      final calls = FakeCalls()..responses['setUserBlocked'] = {'uid': 'u1', 'blocked': false};
      await pumpWith(tester, const UserDetailScreen(uid: 'u1'), db: db, calls: calls);

      await tester.tap(find.text('Unblock'));
      await settle(tester);
      await tester.tap(find.text('Unblock user'));
      await settle(tester);
      expect(calls.sent.single.$2, {'uid': 'u1', 'blocked': false});
      expect(find.text('User unblocked.'), findsOneWidget);
    });

    testWidgets('explains when setUserBlocked is not deployed and keeps the dialog', (tester) async {
      final db = await seedProfile();
      final calls = FakeCalls()..error = FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND');
      await pumpWith(tester, const UserDetailScreen(uid: 'u1'), db: db, calls: calls);
      await tester.tap(find.text('Block'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('block-reason')), 'Chargebacks');
      await tester.tap(find.text('Block user'));
      await settle(tester);
      expect(find.text('The setUserBlocked function is not deployed yet.'), findsOneWidget);
      expect(find.text('Block Sara Ahmed?'), findsOneWidget);
    });
  });

  group('Role gating', () {
    testWidgets('content editors cannot open Users at all', (tester) async {
      final db = await seedProfile();
      await pumpWith(tester, const UsersScreen(), db: db, session: sessionAs(AdminRole.content));
      expect(find.text('Your role (content) cannot open Users.'), findsOneWidget);
      expect(find.text('Sara Ahmed'), findsNothing);

      await pumpWith(tester, const UserDetailScreen(uid: 'u1'), db: db, session: sessionAs(AdminRole.content));
      expect(find.text('Your role (content) cannot open Users.'), findsOneWidget);
      expect(find.text('Block'), findsNothing);
      expect(find.text('Adjust wallet'), findsNothing);
    });

    testWidgets('finance adjusts wallets but cannot block', (tester) async {
      final db = await seedProfile();
      await pumpWith(tester, const UserDetailScreen(uid: 'u1'), db: db, session: sessionAs(AdminRole.finance));
      expect(find.text('Block'), findsNothing);
      expect(find.text('Only super admins and ops can block users.'), findsOneWidget);
      expect(enabled(tester, 'Adjust wallet'), isTrue);
    });

    testWidgets('ops blocks but cannot adjust wallets', (tester) async {
      final db = await seedProfile();
      await pumpWith(tester, const UserDetailScreen(uid: 'u1'), db: db, session: sessionAs(AdminRole.ops));
      expect(enabled(tester, 'Block'), isTrue);
      expect(find.text('Adjust wallet'), findsNothing);
      expect(find.text('Only super admins and finance can adjust wallets.'), findsOneWidget);
    });

    testWidgets('deleted accounts are read-only and a missing wallet disables adjusting', (tester) async {
      final db = await seedProfile(deleted: true, wallet: false);
      await pumpWith(tester, const UserDetailScreen(uid: 'u1'), db: db);
      expect(enabled(tester, 'Block'), isFalse);
      expect(enabled(tester, 'Adjust wallet'), isFalse);
      expect(find.textContaining('deleted (anonymized)'), findsOneWidget);
      expect(find.text('No wallet yet.'), findsOneWidget);
    });
  });

  group('Adjust wallet dialog', () {
    Future<FakeCalls> open(WidgetTester tester, {FakeCalls? calls}) async {
      final db = await seedProfile();
      final c = calls ?? FakeCalls();
      await pumpWith(tester, const UserDetailScreen(uid: 'u1'), db: db, calls: c, size: const Size(1440, 1400));
      await tester.tap(find.text('Adjust wallet'));
      await settle(tester);
      expect(find.text('Adjust wallet — Sara Ahmed'), findsOneWidget);
      return c;
    }

    Finder amount() => find.byKey(const ValueKey('adjust-amount'));
    Finder reason() => find.byKey(const ValueKey('adjust-reason'));

    testWidgets('validates amount and reason before calling', (tester) async {
      final calls = await open(tester);
      await tester.tap(find.text('Apply adjustment'));
      await settle(tester);
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('At least 3 characters'), findsOneWidget);
      expect(find.text('Enter an amount other than 0.'), findsOneWidget);

      await tester.enterText(amount(), '0');
      await tester.enterText(reason(), 'Goodwill');
      await tester.tap(find.text('Apply adjustment'));
      await settle(tester);
      expect(find.text('Enter an amount other than 0.'), findsOneWidget);
      expect(calls.sent, isEmpty);
    });

    testWidgets('previews the result and refuses a negative balance', (tester) async {
      final calls = await open(tester);
      await tester.tap(find.textContaining('Credits — promotional'));
      await tester.tap(find.text('Deduct'));
      await tester.enterText(amount(), '6000');
      await tester.enterText(reason(), 'Expired promo credit');
      await settle(tester);
      expect(find.text('Credits: 5,000 IQD → -1,000 IQD  (below zero — not allowed)'), findsOneWidget);
      expect(enabled(tester, 'Apply adjustment'), isFalse);

      await tester.enterText(amount(), '5000');
      await settle(tester);
      expect(find.text('Credits: 5,000 IQD → 0 IQD'), findsOneWidget);
      await tester.tap(find.text('Apply adjustment'));
      await settle(tester);
      expect(calls.sent.single.$1, 'adjustWallet');
      expect(calls.sent.single.$2['requestId'], isA<String>().having((v) => v.length, 'length', greaterThan(10)));
      expect({...calls.sent.single.$2}..remove('requestId'), {'uid': 'u1', 'bucket': 'credits', 'amount': -5000, 'reason': 'Expired promo credit'});
      expect(find.text('Adjust wallet — Sara Ahmed'), findsNothing);
      expect(find.textContaining('Wallet adjusted.'), findsOneWidget);
    });

    testWidgets('adds to the balance', (tester) async {
      final calls = await open(tester);
      await tester.enterText(amount(), '15000');
      await tester.enterText(reason(), 'Refund for broken mug');
      await settle(tester);
      expect(find.text('Balance: 20,000 IQD → 35,000 IQD'), findsOneWidget);
      await tester.tap(find.text('Apply adjustment'));
      await settle(tester);
      expect(calls.sent.single.$2['requestId'], isA<String>().having((v) => v.length, 'length', greaterThan(10)));
      expect({...calls.sent.single.$2}..remove('requestId'), {'uid': 'u1', 'bucket': 'balance', 'amount': 15000, 'reason': 'Refund for broken mug'});
    });

    testWidgets('maps insufficient_funds from the server', (tester) async {
      final calls = FakeCalls()
        ..error = FirebaseFunctionsException(
            code: 'failed-precondition', message: 'Insufficient funds', details: const {'reason': 'insufficient_funds'});
      await open(tester, calls: calls);
      await tester.tap(find.text('Deduct'));
      await tester.enterText(amount(), '20000');
      await tester.enterText(reason(), 'Chargeback');
      await tester.tap(find.text('Apply adjustment'));
      await settle(tester);
      expect(find.textContaining('Insufficient funds: the balance would go below zero.'), findsOneWidget);
      expect(find.text('Adjust wallet — Sara Ahmed'), findsOneWidget);
    });

    testWidgets('explains when adjustWallet is not deployed', (tester) async {
      final calls = FakeCalls()..error = FirebaseFunctionsException(code: 'unavailable', message: 'UNAVAILABLE');
      await open(tester, calls: calls);
      await tester.enterText(amount(), '1000');
      await tester.enterText(reason(), 'Goodwill');
      await tester.tap(find.text('Apply adjustment'));
      await settle(tester);
      expect(find.text('The adjustWallet function is not deployed yet.'), findsOneWidget);
    });
  });
}
