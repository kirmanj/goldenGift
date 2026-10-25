import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift_admin/core/theme/admin_theme.dart';
import 'package:golden_gift_admin/features/auth/login_screen.dart';

class FakeAuthRepository extends Fake implements AuthRepository {
  final sent = <String>[];
  final confirmed = <(String, String)>[];
  AuthFailure? confirmError;

  @override
  Future<PhoneCodeSession> sendCode(String phoneE164, {bool forPhoneChange = false}) async {
    sent.add(phoneE164);
    return PhoneCodeSession(phoneE164: phoneE164);
  }

  @override
  Future<UserCredential> confirmCode(PhoneCodeSession session, String smsCode) async {
    confirmed.add((session.phoneE164, smsCode));
    if (confirmError != null) throw confirmError!;
    throw const AuthFailure(AuthFailureReason.unknown, 'no credential in tests');
  }
}

Future<FakeAuthRepository> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = FakeAuthRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
    child: MaterialApp(theme: AdminTheme.light(), home: const LoginScreen()),
  ));
  return auth;
}

void main() {
  testWidgets('partners sign in with their phone: Iraqi number → code → verify', (tester) async {
    final auth = await pump(tester);
    await tester.tap(find.text('Partner (phone)'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid Iraqi mobile number'), findsOneWidget);
    expect(auth.sent, isEmpty);

    await tester.enterText(find.byType(TextFormField).first, '0750 123 4567');
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();
    expect(auth.sent, ['+9647501234567']);
    expect(find.text('Verify and sign in'), findsOneWidget);

    auth.confirmError = const AuthFailure(AuthFailureReason.invalidCode);
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();
    expect(auth.confirmed, [('+9647501234567', '123456')]);
    expect(find.text('Wrong code. Check it and try again.'), findsOneWidget);

    await tester.tap(find.text('Use another number'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('staff keep email + password', (tester) async {
    await pump(tester);
    expect(find.text('Email'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  test('every phone failure has a message', () {
    for (final r in AuthFailureReason.values) {
      expect(phoneFailureMessage(r), isNotEmpty);
    }
  });
}
