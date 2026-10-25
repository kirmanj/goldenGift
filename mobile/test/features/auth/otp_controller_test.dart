import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/auth/presentation/providers/otp_controller.dart';
import 'package:golden_gift/features/profile/data/datasources/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_fakes.dart';

void main() {
  group('AuthFailure mapping for the OTP functions (sendOtp / verifyOtp / changePhone)', () {
    AuthFailureReason map(String code, {bool verifying = false}) =>
        AuthFailure.from(FirebaseFunctionsException(code: code, message: 'x'), verifying: verifying).reason;

    test('sending', () {
      expect(map('invalid-argument'), AuthFailureReason.invalidPhone);
      expect(map('resource-exhausted'), AuthFailureReason.tooManyRequests);
      expect(map('unavailable'), AuthFailureReason.deliveryFailed);
      expect(map('already-exists'), AuthFailureReason.phoneInUse);
      expect(map('not-found'), AuthFailureReason.providerUnavailable); // function not deployed
    });

    test('verifying', () {
      expect(map('invalid-argument', verifying: true), AuthFailureReason.invalidCode);
      expect(map('unauthenticated', verifying: true), AuthFailureReason.invalidCode);
      expect(map('resource-exhausted', verifying: true), AuthFailureReason.tooManyRequests);
      expect(map('permission-denied', verifying: true), AuthFailureReason.accountDisabled);
    });
  });

  group('OtpController', () {
    Future<(ProviderContainer, FakeAuthRepository)> setUp() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = FakeAuthRepository();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(auth),
        userRepositoryProvider.overrideWithValue(FakeUserRepository()),
        analyticsServiceProvider.overrideWithValue(FakeAnalytics()),
      ]);
      addTearDown(c.dispose);
      return (c, auth);
    }

    test('change phone: a correct code updates the phone, no sign-in happens', () async {
      final (c, auth) = await setUp();
      final args = OtpArgs(
        purpose: OtpPurpose.changePhone,
        session: testSession('+9647701234567', forPhoneChange: true),
        displayPhone: '+964 7701234567',
      );
      final sub = c.listen(otpControllerProvider(args), (_, __) {});
      await c.read(otpControllerProvider(args).notifier).verify('123456');
      expect(sub.read().result, isA<OtpPhoneUpdated>());
      expect(auth.changedTo, ['+9647701234567']);
      expect(auth.user, isNull); // changePhone never signs anyone in
    });

    test('resend keeps the purpose (a change-phone code stays bound to the user)', () async {
      final (c, auth) = await setUp();
      final args = OtpArgs(
        purpose: OtpPurpose.changePhone,
        session: testSession('+9647701234567', forPhoneChange: true),
        displayPhone: '+964 7701234567',
      );
      final sub = c.listen(otpControllerProvider(args), (_, __) {});
      // Pretend the countdown finished.
      c.read(otpControllerProvider(args).notifier).state = sub.read().copyWith(secondsLeft: 0);
      await c.read(otpControllerProvider(args).notifier).resend();
      expect(auth.phoneChangeCodes, ['+9647701234567']);
    });

    test('incomplete codes never reach the server', () async {
      final (c, auth) = await setUp();
      final args = OtpArgs(
        purpose: OtpPurpose.signIn,
        session: testSession('+9647501234567'),
        displayPhone: '+964 7501234567',
      );
      final sub = c.listen(otpControllerProvider(args), (_, __) {});
      await c.read(otpControllerProvider(args).notifier).verify('12345');
      expect(auth.confirmedCodes, isEmpty);
      expect(sub.read().verifying, isFalse);
    });
  });
}
