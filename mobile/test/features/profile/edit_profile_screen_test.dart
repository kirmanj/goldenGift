import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/features/profile/presentation/screens/change_phone_screen.dart';
import 'package:golden_gift/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:golden_gift/features/profile/presentation/screens/profile_screen.dart';
import 'package:image_picker/image_picker.dart';

import 'profile_test_harness.dart';

Finder _field(String key) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

void main() {
  final en = l10nFor('en');

  Future<ProfileHarness> openEdit(
    WidgetTester tester, {
    RecordingUserRepository? users,
    FakeAvatarPicker? picker,
    bool phoneChangeSupported = true,
    String phone = '7505448229',
    String? gender = 'male',
  }) =>
      pumpProfileApp(
        tester,
        push: [AppRoutes.editProfile],
        users: users,
        picker: picker,
        phoneChangeSupported: phoneChangeSupported,
        user: testUser(phone: phone, gender: gender),
      );

  testWidgets('prefills the form from the profile', (tester) async {
    await openEdit(tester);
    expect(find.text(en.editProfile), findsOneWidget);
    expect(find.text('Krmanj'), findsOneWidget);
    expect(find.text('krmanj@example.com'), findsOneWidget);
    expect(find.text('+964 750 544 8229'), findsOneWidget);
    expect(find.text('10/03/1995'), findsOneWidget);
    expect(find.text('Erbil'), findsOneWidget);
    expect(find.text(en.changePhone), findsOneWidget);
  });

  testWidgets('blocks Save on an empty or too-short name', (tester) async {
    final app = await openEdit(tester);
    await tester.enterText(_field('edit-name'), '');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();
    expect(find.text(en.errorRequired), findsOneWidget);

    await tester.enterText(_field('edit-name'), 'A');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();
    expect(find.text(en.errorNameLength), findsOneWidget);
    expect(app.users.updatedProfiles, isEmpty);
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  testWidgets('blocks Save on an invalid email', (tester) async {
    final app = await openEdit(tester);
    await tester.enterText(_field('edit-email'), 'krmanj@');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();
    expect(find.text(en.errorInvalidEmail), findsOneWidget);
    expect(app.users.updatedProfiles, isEmpty);
  });

  testWidgets('saves the edited name, gender, city and birthday, then pops', (tester) async {
    final app = await openEdit(tester);

    await tester.enterText(_field('edit-name'), '  Krmanj Mzuri ');
    await tester.tap(find.byKey(const ValueKey('gender-female')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('edit-city')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('city-duhok')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('edit-birthday')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('15/03/1995'), findsOneWidget);
    expect(find.text('Duhok'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();

    final saved = app.users.updatedProfiles.single;
    expect(saved.uid, 'u1');
    expect(saved.name, 'Krmanj Mzuri');
    expect(saved.email, 'krmanj@example.com');
    expect(saved.gender, 'female');
    expect(saved.city, 'duhok');
    expect([saved.birthday!.year, saved.birthday!.month, saved.birthday!.day], [1995, 3, 15]);
    expect(saved.phone, '7505448229');
    expect(saved.toProfileMap()['profileCompleted'], isTrue);

    expect(find.text(en.profileSaved), findsOneWidget);
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('"Prefer not to say" and an empty email are saved as null', (tester) async {
    final app = await openEdit(tester);
    await tester.tap(find.byKey(const ValueKey('gender-none')));
    await tester.enterText(_field('edit-email'), '');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();

    final saved = app.users.updatedProfiles.single;
    expect(saved.gender, isNull);
    expect(saved.email, isNull);
    expect(saved.toProfileMap()['profileCompleted'], isFalse);
  });

  testWidgets('a failed save keeps the screen and shows an error', (tester) async {
    final users = RecordingUserRepository()..updateProfileError = Exception('offline');
    await openEdit(tester, users: users);
    await tester.enterText(_field('edit-name'), 'Krmanj M');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();
    expect(find.text(en.somethingWentWrong), findsOneWidget);
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  testWidgets('back with unsaved changes asks before discarding', (tester) async {
    final app = await openEdit(tester);
    await tester.enterText(_field('edit-name'), 'Someone Else');
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text(en.unsavedChanges), findsOneWidget);

    await tester.tap(find.text(en.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.discard));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(app.users.updatedProfiles, isEmpty);
  });

  testWidgets('opened by deep link, Save returns to Main instead of popping', (tester) async {
    final app = await pumpProfileApp(tester, initialPath: AppRoutes.editProfile);
    await tester.enterText(_field('edit-name'), 'Krmanj M');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();
    expect(app.users.updatedProfiles.single.name, 'Krmanj M');
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back without changes pops straight away', (tester) async {
    await openEdit(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text(en.unsavedChanges), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('photo upload failure shows a snackbar and keeps the old photo', (tester) async {
    final users = RecordingUserRepository()..uploadError = Exception('storage not set up');
    final picker = FakeAvatarPicker(Uint8List.fromList([1, 2, 3]));
    final app = await openEdit(tester, users: users, picker: picker);

    await tester.tap(find.text(en.changePhoto).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.chooseFromGallery));
    await tester.pumpAndSettle();

    expect(picker.sources, [ImageSource.gallery]);
    expect(find.text(en.photoUploadFailed), findsOneWidget);
    expect(app.users.fieldUpdates, isEmpty);
    expect(find.text('K'), findsOneWidget); // still the initial avatar
  });

  testWidgets('a picked photo is uploaded and saved to the profile', (tester) async {
    final users = RecordingUserRepository()..uploadUrl = '';
    final picker = FakeAvatarPicker(Uint8List.fromList([1, 2, 3]));
    final app = await openEdit(tester, users: users, picker: picker);

    await tester.tap(find.text(en.changePhoto).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.takePhoto));
    await tester.pumpAndSettle();

    expect(picker.sources, [ImageSource.camera]);
    expect(app.users.uploads.single, [1, 2, 3]);
    expect(app.users.fieldUpdates.single.$2, {'photoUrl': ''});
    expect(find.text(en.photoUploadFailed), findsNothing);
  });

  testWidgets('Change opens the change-phone screen', (tester) async {
    await openEdit(tester);
    await tester.tap(find.text(en.changePhone));
    await tester.pumpAndSettle();
    expect(find.byType(ChangePhoneScreen), findsOneWidget);
  });

  testWidgets('without a phone the field offers "Add mobile number"', (tester) async {
    await openEdit(tester, phone: '');
    expect(find.text(en.addPhoneNumber), findsWidgets);
    expect(find.text(en.phoneLaterNote), findsOneWidget);
  });

  testWidgets('on web the phone can only be changed in the mobile app', (tester) async {
    await openEdit(tester, phoneChangeSupported: false);
    expect(find.text(en.phoneChangeMobileOnly), findsOneWidget);
    expect(find.text(en.changePhone), findsNothing);
  });

  for (final (locale, mode) in [('ar', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
    testWidgets('renders in $locale (${mode.name}) at 320 px with 130 % text', (tester) async {
      await pumpProfileApp(
        tester,
        push: [AppRoutes.editProfile],
        locale: locale,
        themeMode: mode,
        size: const Size(320, 2000),
        textScale: 1.3,
      );
      final context = tester.element(find.byType(EditProfileScreen));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(find.text(l10nFor(locale).editProfile), findsOneWidget);
      // The phone stays left-to-right inside the RTL form.
      final phone = find.text('+964 750 544 8229');
      expect(tester.widget<Text>(phone).textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });
  }
}
