import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/auth/presentation/providers/auth_flow.dart';
import 'package:golden_gift/features/auth/presentation/providers/otp_controller.dart';
import 'package:golden_gift/features/auth/presentation/screens/otp_screen.dart';
import 'package:golden_gift/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:golden_gift/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:golden_gift/models/user_model.dart';

import '../../helpers/auth_fakes.dart';
import '../../helpers/auth_test_app.dart';

Finder _field(int index) => find.byType(TextField).at(index);

/// The auth screens are lazily built lists taller than the test viewport.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _tapPrimary(WidgetTester tester) async {
  await _reveal(tester, find.byType(PrimaryButton));
  await tester.tap(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
}

void main() {
  group('Sign Up (SRS §5.2, AUTH-1/8)', () {
    Future<FakeAuthRepository> pumpSignUp(WidgetTester tester, {String path = '/sign-up', Locale locale = const Locale('en')}) async {
      final auth = FakeAuthRepository();
      await pumpAuthApp(
        tester,
        initialPath: path,
        auth: auth,
        locale: locale,
        screens: {'/sign-up': (s) => SignUpScreen(referralCode: s.uri.queryParameters['ref'])},
      );
      return auth;
    }

    testWidgets('empty form: inline errors and nothing sent to Firebase', (tester) async {
      final auth = await pumpSignUp(tester);
      await _tapPrimary(tester);
      expect(find.text('This field is required'), findsNWidgets(2)); // name + phone
      expect(auth.sentTo, isEmpty);
    });

    testWidgets('invalid email / phone / referral never reach Firebase', (tester) async {
      final auth = await pumpSignUp(tester, path: '/sign-up?ref=AB');
      await tester.enterText(_field(0), 'Sara Ahmed');
      await tester.enterText(_field(1), 'sara@');
      await tester.enterText(_field(2), '750123');
      await _tapPrimary(tester);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Enter a valid mobile number'), findsOneWidget);
      expect(find.text('Referral codes have 6 letters or digits'), findsOneWidget);
      expect(auth.sentTo, isEmpty);
    });

    testWidgets('valid form sends the code to the E.164 number and opens OTP', (tester) async {
      final auth = await pumpSignUp(tester);
      await tester.enterText(_field(0), 'Sara Ahmed');
      await tester.enterText(_field(2), '0750 123 4567');
      await _tapPrimary(tester);
      expect(auth.sentTo, ['+9647501234567']);
      expect(find.text('/otp'), findsOneWidget);
    });

    testWidgets('referral link /r/{code} opens Sign Up with the code filled in', (tester) async {
      await pumpSignUp(tester, path: '/sign-up?ref=AB3D9K');
      await _reveal(tester, find.text('AB3D9K'));
      expect(find.text('AB3D9K'), findsOneWidget);
      expect(find.text('Have a referral code?'), findsNothing);
    });

    testWidgets('referral link is collapsed by default and expands on tap', (tester) async {
      await pumpSignUp(tester);
      await _reveal(tester, find.text('Have a referral code?'));
      expect(find.text('Referral code'), findsNothing);
      await _reveal(tester, find.text('Have a referral code?'));
      await tester.tap(find.text('Have a referral code?'));
      await tester.pumpAndSettle();
      expect(find.text('Referral code'), findsOneWidget);
    });

    testWidgets('continue as guest opens Main without any auth call (AUTH-5)', (tester) async {
      final auth = await pumpSignUp(tester);
      await _reveal(tester, find.text('Continue as a guest'));
      await tester.tap(find.text('Continue as a guest'));
      await tester.pumpAndSettle();
      expect(find.text('/main'), findsOneWidget);
      expect(auth.sentTo, isEmpty);
    });

    for (final code in ['ar', 'ckb']) {
      testWidgets('renders right-to-left in $code', (tester) async {
        await pumpSignUp(tester, locale: Locale(code));
        expect(Directionality.of(tester.element(find.byType(SignUpScreen))), TextDirection.rtl);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('complete-profile mode for a Google account: no phone field, creates the profile', (tester) async {
      final auth = FakeAuthRepository(user: FakeUser(uid: 'g1', providers: ['google.com']));
      final users = FakeUserRepository();
      await pumpAuthApp(
        tester,
        initialPath: '/complete-profile',
        auth: auth,
        users: users,
        screens: {
          '/complete-profile': (_) => const SignUpScreen(
                prefill: ProfilePrefill(method: SignInMethod.google, name: 'Sara Ahmed', email: 'sara@gmail.com'),
              ),
        },
      );
      await _reveal(tester, find.textContaining('add your mobile number later'));
      expect(find.text('Mobile Number'), findsNothing); // no phone field for Google/Apple
      expect(find.textContaining('add your mobile number later'), findsOneWidget);
      await _tapPrimary(tester);
      expect(users.created.single.name, 'Sara Ahmed');
      expect(users.created.single.hasPhone, isFalse);
      expect(find.text('/main'), findsOneWidget);
      expect(auth.sentTo, isEmpty);
    });
  });

  group('Sign In (AUTH-4)', () {
    testWidgets('invalid number is rejected locally; valid one sends a code', (tester) async {
      final auth = FakeAuthRepository();
      await pumpAuthApp(tester, initialPath: '/sign-in', auth: auth, screens: {'/sign-in': (_) => const SignInScreen()});
      await tester.enterText(_field(0), '12345');
      await _tapPrimary(tester);
      expect(find.text('Enter a valid mobile number'), findsOneWidget);
      expect(auth.sentTo, isEmpty);

      await tester.enterText(_field(0), '7701234567');
      await _tapPrimary(tester);
      expect(auth.sentTo, ['+9647701234567']);
      expect(find.text('/otp'), findsOneWidget);
    });

    testWidgets('a provider error is shown, not swallowed', (tester) async {
      final auth = FakeAuthRepository(sendError: const AuthFailure(AuthFailureReason.tooManyRequests));
      await pumpAuthApp(tester, initialPath: '/sign-in', auth: auth, screens: {'/sign-in': (_) => const SignInScreen()});
      await tester.enterText(_field(0), '7701234567');
      await _tapPrimary(tester);
      expect(find.text('Too many attempts. Please try again later.'), findsOneWidget);
    });
  });

  group('OTP (AUTH-2, AUTH-3)', () {
    OtpArgs args(OtpPurpose purpose, {PendingSignUp? pending}) => OtpArgs(
          purpose: purpose,
          session: testSession('+9647501234567'),
          displayPhone: '+964 7501234567',
          pending: pending,
        );

    testWidgets('6 digits verify automatically and a new sign-up creates users/{uid}', (tester) async {
      final auth = FakeAuthRepository(signedInUser: FakeUser(uid: 'new', phoneNumber: '+9647501234567'));
      final users = FakeUserRepository();
      final a = args(OtpPurpose.signUp, pending: const PendingSignUp(name: 'Sara', referralCode: 'AB3D9K'));
      await pumpAuthApp(tester, initialPath: '/code', auth: auth, users: users, screens: {'/code': (_) => OtpScreen(args: a)});

      expect(find.text('Resend code in 60s'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();

      expect(auth.confirmedCodes, ['123456']);
      expect(users.created.single.referralCodeEntered, 'AB3D9K');
      expect(users.created.single.phone, '7501234567');
      expect(find.text('/main'), findsOneWidget);
    });

    testWidgets('wrong code shows the error and clears the boxes', (tester) async {
      final auth = FakeAuthRepository(confirmError: const AuthFailure(AuthFailureReason.invalidCode));
      await pumpAuthApp(tester,
          initialPath: '/code', auth: auth, screens: {'/code': (_) => OtpScreen(args: args(OtpPurpose.signIn))});
      await tester.enterText(find.byType(TextField), '000000');
      await tester.pumpAndSettle();
      expect(find.text("That code isn't right. Check it and try again."), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      expect(find.text('/main'), findsNothing);
    });

    testWidgets('resend is disabled for 60 s, then sends a new code', (tester) async {
      final auth = FakeAuthRepository();
      await pumpAuthApp(tester,
          initialPath: '/code', auth: auth, screens: {'/code': (_) => OtpScreen(args: args(OtpPurpose.signIn))});
      expect(find.text('Resend code'), findsNothing);
      await tester.pump(const Duration(seconds: 59));
      expect(find.text('Resend code in 1s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      expect(auth.sentTo, ['+9647501234567']);
      expect(find.text('Resend code in 60s'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // dispose the countdown timer
    });

    testWidgets('returning user signs in straight to Main', (tester) async {
      final auth = FakeAuthRepository();
      final users = FakeUserRepository(existing: const UserModel(uid: 'u1', name: 'Sara', phone: '7501234567'));
      await pumpAuthApp(tester,
          initialPath: '/code',
          auth: auth,
          users: users,
          screens: {'/code': (_) => OtpScreen(args: args(OtpPurpose.signIn))});
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();
      expect(users.created, isEmpty);
      expect(find.text('/main'), findsOneWidget);
    });
  });
}
