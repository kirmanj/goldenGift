// End-to-end Phase 2 exit check (SRS §10): a new user signs up with phone OTP
// in English, Arabic and Kurdish; `users/{uid}` and `wallets/{uid}` exist with
// a unique referral code (written by the `onUserCreate` function).
//
// Codes come from the `sendOtp` function (OTPIQ in production; on the emulator the
// log driver sends nothing and mirrors the code to `otp_debug/{digits}`).
// Runs the real app on a simulator against the local Emulator Suite:
//   (repo root) firebase emulators:start --only auth,firestore,functions --project goldengift-iq
//   (mobile)    flutter test integration_test/auth_e2e_test.dart -d <simulator> --dart-define=USE_EMULATOR=true
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/config/app_env.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/widgets/main_shell.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/firebase_options.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emulator_admin.dart';

/// The code `sendOtp` issued for [phoneE164]. On the emulator the functions use
/// the log driver (nothing is sent) and mirror the code to `otp_debug/{digits}`.

/// Waits for `onUserCreate` (functions emulator) to finish its writes.
Future<(Map<String, dynamic>, Map<String, dynamic>)> _waitForServerDocs(
    String uid) async {
  final db = FirebaseFirestore.instance;
  for (var attempt = 0; attempt < 60; attempt++) {
    final user =
        await db.doc('users/$uid').get(const GetOptions(source: Source.server));
    final wallet = await db
        .doc('wallets/$uid')
        .get(const GetOptions(source: Source.server));
    if ((user.data()?['referralCode'] as String?) != null && wallet.exists) {
      return (user.data()!, wallet.data()!);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError(
      'onUserCreate did not run for $uid — is the functions emulator up?');
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder,
    {int maxTries = 80}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw StateError('timed out waiting for $finder');
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(AppEnv.useEmulator, isTrue,
        reason: 'run with --dart-define=USE_EMULATOR=true');
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await configureFirebase();
  });

  final referralCodes = <String>{};

  for (final code in ['en', 'ar', 'ckb']) {
    testWidgets('new user signs up with OTP in $code', (tester) async {
      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      // Onboarding already seen; start on Sign Up in the target language.
      await prefs.setBool('onboarding_done', true);
      await prefs.setString('locale', code);

      final l10n = lookupAppLocalizations(Locale(code));
      final national = '750${Random().nextInt(9000000) + 1000000}';
      final e164 = '+964$national';

      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const GoldenGiftApp(),
      ));
      await _pumpUntil(tester, find.text(l10n.createYourAccount));

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'E2E $code user');
      await tester.enterText(fields.at(2), national);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _scrollTo(tester, find.byType(PrimaryButton));
      await tester.tap(find.byType(PrimaryButton));

      await _pumpUntil(tester, find.text(l10n.otpTitle));
      final smsCode = await emulatorCode(e164);
      await tester.enterText(find.byType(TextField), smsCode);
      await _pumpUntil(tester, find.byType(MainShell));

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final (user, wallet) = await _waitForServerDocs(uid);
      expect(user['name'], 'E2E $code user');
      expect(user['phone'], national);
      expect(user['locale'], code);
      expect(user['role'], 'customer');
      expect(wallet['balance'], 0);
      expect(wallet['credits'], 0);
      final referralCode = user['referralCode'] as String;
      expect(referralCode, matches(RegExp(r'^[A-HJ-NP-Z2-9]{6}$')));
      expect(referralCodes.add(referralCode), isTrue,
          reason: 'referral codes must be unique');
    });
  }
}
