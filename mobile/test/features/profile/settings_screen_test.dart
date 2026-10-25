import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/providers/theme_provider.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_platform_providers.dart';
import 'package:golden_gift/features/profile/presentation/screens/settings_screen.dart';

import 'profile_test_harness.dart';

void main() {
  final en = l10nFor('en');
  final deleteRow = find.byKey(const ValueKey('settings-delete-account'));

  Future<ProfileHarness> open(
    WidgetTester tester, {
    bool signedIn = true,
    RecordingUserRepository? users,
    bool notificationsEnabled = true,
  }) =>
      pumpProfileApp(
        tester,
        push: [AppRoutes.settings],
        signedIn: signedIn,
        users: users,
        user: testUser(notificationsEnabled: notificationsEnabled),
      );

  bool switchValue(WidgetTester tester) => tester.widget<Switch>(find.byType(Switch)).value;

  testWidgets('shows every section with the version', (tester) async {
    await open(tester);
    expect(find.text(en.settings), findsOneWidget);
    expect(find.text(en.notificationsSetting), findsOneWidget);
    expect(find.text(en.appearance), findsOneWidget);
    expect(find.text(en.language), findsOneWidget);
    expect(find.text(en.privacyPolicy), findsOneWidget);
    expect(find.text(en.termsOfService), findsOneWidget);
    expect(find.text(en.deleteAccount), findsOneWidget);
    expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
  });

  testWidgets('guests see no notifications switch and no delete account', (tester) async {
    await open(tester, signedIn: false);
    expect(find.byType(Switch), findsNothing);
    expect(deleteRow, findsNothing);
    expect(find.text(en.appearance), findsOneWidget);
  });

  testWidgets('theme selection updates themeModeProvider and the app theme', (tester) async {
    final app = await open(tester);
    expect(app.container.read(themeModeProvider), ThemeMode.light);

    await tester.tap(find.byKey(const ValueKey('theme-dark')));
    await tester.pumpAndSettle();
    expect(app.container.read(themeModeProvider), ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness, Brightness.dark);

    await tester.tap(find.byKey(const ValueKey('theme-system')));
    await tester.pumpAndSettle();
    expect(app.container.read(themeModeProvider), ThemeMode.system);
  });

  testWidgets('notifications switch writes the new value', (tester) async {
    final app = await open(tester);
    expect(switchValue(tester), isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(switchValue(tester), isFalse);
    expect(app.users.fieldUpdates.single.$2, {'notificationsEnabled': false});
  });

  testWidgets('notifications switch rolls back when the write fails', (tester) async {
    final users = RecordingUserRepository()..updateFieldsError = Exception('offline');
    await open(tester, users: users);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(switchValue(tester), isTrue);
    expect(find.text(en.somethingWentWrong), findsOneWidget);
  });

  testWidgets('legal links open the public pages', (tester) async {
    final app = await open(tester);
    await tester.tap(find.text(en.privacyPolicy));
    await tester.tap(find.text(en.termsOfService));
    await tester.pumpAndSettle();
    expect(app.openedLinks, [ProfileLinks.privacyPolicy, ProfileLinks.termsOfService]);
  });

  testWidgets('cancelling delete account does nothing', (tester) async {
    final app = await open(tester);
    await tester.tap(deleteRow);
    await tester.pumpAndSettle();
    expect(find.text(en.deleteAccountTitle), findsOneWidget);
    expect(find.text(en.deleteAccountBody), findsOneWidget);
    await tester.tap(find.text(en.cancel));
    await tester.pumpAndSettle();
    expect(app.users.deleteCalls, 0);
  });

  testWidgets('delete account failure shows an error and keeps the session', (tester) async {
    final users = RecordingUserRepository()..deleteError = Exception('functions not deployed');
    final app = await open(tester, users: users);
    await tester.tap(deleteRow);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.deleteAccountConfirm));
    await tester.pumpAndSettle();

    expect(users.deleteCalls, 1);
    expect(app.authFlow.signOutCalls, 0);
    expect(find.text(en.somethingWentWrong), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing); // loader closed
  });

  testWidgets('delete account success signs out and opens Sign Up', (tester) async {
    final app = await open(tester);
    await tester.tap(deleteRow);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.deleteAccountConfirm));
    await tester.pumpAndSettle();

    expect(app.users.deleteCalls, 1);
    expect(app.authFlow.signOutCalls, 1);
    expect(find.text(en.accountDeleted), findsOneWidget);
    expect(find.text(AppRoutes.signUp), findsOneWidget);
  });

  for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light)]) {
    testWidgets('renders in $locale (${mode.name}) at 320 px with 130 % text', (tester) async {
      await pumpProfileApp(
        tester,
        push: [AppRoutes.settings],
        locale: locale,
        themeMode: mode,
        size: const Size(320, 1400),
        textScale: 1.3,
      );
      final context = tester.element(find.byType(SettingsScreen));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(find.text(l10nFor(locale).settings), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
