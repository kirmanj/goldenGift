import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/profile/presentation/screens/change_phone_screen.dart';
import 'package:golden_gift/features/profile/presentation/screens/profile_screen.dart';

import '../../helpers/auth_fakes.dart';
import 'profile_test_harness.dart';

void main() {
  final en = l10nFor('en');
  final send = find.byKey(const ValueKey('change-phone-send'));

  Future<ProfileHarness> open(
    WidgetTester tester, {
    FakeAuthRepository? auth,
    RecordingUserRepository? users,
    bool supported = true,
  }) =>
      pumpProfileApp(
        tester,
        push: [AppRoutes.changePhone],
        auth: auth,
        users: users,
        phoneChangeSupported: supported,
      );

  testWidgets('invalid numbers never reach Firebase', (tester) async {
    final app = await open(tester);
    expect(find.text(en.changePhoneTitle), findsOneWidget);
    expect(find.text(en.changePhoneSubtitle), findsOneWidget);

    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text(en.errorRequired), findsOneWidget);

    await tester.enterText(find.byType(TextField), '0650 123 4567'); // Iraqi mobiles start with 7
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text(en.errorInvalidPhone), findsOneWidget);
    expect(app.auth.sentTo, isEmpty);
  });

  testWidgets('sends the code, verifies via OTP, then saves the new number', (tester) async {
    final app = await open(tester);
    await tester.enterText(find.byType(TextField), '0770 123 4567');
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(app.auth.sentTo, ['+9647701234567']);
    expect(find.text(AppRoutes.otp), findsOneWidget);

    await tester.tap(find.text('verify-ok'));
    await tester.pumpAndSettle();

    final (uid, fields) = app.users.fieldUpdates.single;
    expect(uid, 'u1');
    expect(fields, {'phone': '7701234567', 'countryCode': '+964'});
    expect(find.text(en.phoneUpdated), findsOneWidget);
    expect(find.byType(ChangePhoneScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('leaving the OTP screen without verifying changes nothing', (tester) async {
    final app = await open(tester);
    await tester.enterText(find.byType(TextField), '7701234567');
    await tester.tap(send);
    await tester.pumpAndSettle();
    app.router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ChangePhoneScreen), findsOneWidget);
    expect(app.users.fieldUpdates, isEmpty);
  });

  testWidgets('shows the auth failure under the field', (tester) async {
    final auth = FakeAuthRepository(sendError: const AuthFailure(AuthFailureReason.tooManyRequests));
    await open(tester, auth: auth);
    await tester.enterText(find.byType(TextField), '7701234567');
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text(en.authErrorTooManyRequests), findsOneWidget);
    expect(find.text(AppRoutes.otp), findsNothing);
  });

  testWidgets('a failed profile write can be retried without a new SMS', (tester) async {
    final users = RecordingUserRepository()..updateFieldsError = Exception('offline');
    final app = await open(tester, users: users);
    await tester.enterText(find.byType(TextField), '7701234567');
    await tester.tap(send);
    await tester.pumpAndSettle();
    await tester.tap(find.text('verify-ok'));
    await tester.pumpAndSettle();

    expect(find.text(en.somethingWentWrong), findsOneWidget);
    expect(find.text(en.retry), findsOneWidget);
    expect(find.byType(ChangePhoneScreen), findsOneWidget);

    users.updateFieldsError = null;
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(app.auth.sentTo, hasLength(1));
    expect(users.fieldUpdates.single.$2, {'phone': '7701234567', 'countryCode': '+964'});
    expect(find.byType(ChangePhoneScreen), findsNothing);
  });

  testWidgets('on web only explains that the mobile app is needed', (tester) async {
    await open(tester, supported: false);
    expect(find.text(en.phoneChangeMobileOnly), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(send, findsNothing);
  });

  testWidgets('renders in ckb dark at 320 px with 130 % text', (tester) async {
    await pumpProfileApp(
      tester,
      push: [AppRoutes.changePhone],
      locale: 'ckb',
      themeMode: ThemeMode.dark,
      size: const Size(320, 900),
      textScale: 1.3,
    );
    expect(find.text(l10nFor('ckb').changePhoneTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
