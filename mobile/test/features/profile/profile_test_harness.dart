import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/providers/locale_provider.dart';
import 'package:golden_gift/core/providers/theme_provider.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/auth/presentation/providers/auth_flow.dart';
import 'package:golden_gift/features/profile/data/datasources/user_repository.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_platform_providers.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/features/profile/presentation/screens/change_phone_screen.dart';
import 'package:golden_gift/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:golden_gift/features/profile/presentation/screens/profile_screen.dart';
import 'package:golden_gift/features/profile/presentation/screens/settings_screen.dart';
import 'package:golden_gift/features/wallet/data/wallet_repository.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:golden_gift/models/wallet_model.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_fakes.dart';

/// Records every write; set an `*Error` to make that call throw.
class RecordingUserRepository implements UserRepository {
  final updatedProfiles = <UserModel>[];
  final fieldUpdates = <(String, Map<String, Object?>)>[];
  final uploads = <Uint8List>[];
  int deleteCalls = 0;

  Object? updateProfileError;
  Object? updateFieldsError;
  Object? uploadError;
  Object? deleteError;
  String uploadUrl = 'https://example.com/avatar.jpg';

  @override
  Stream<UserModel?> watch(String uid) => const Stream.empty();

  @override
  Future<UserModel?> fetch(String uid) async => null;

  @override
  Future<void> create(UserModel user) async {}

  @override
  Future<void> updateProfile(UserModel user) async {
    if (updateProfileError != null) throw updateProfileError!;
    updatedProfiles.add(user);
  }

  @override
  Future<void> updateFields(String uid, Map<String, Object?> fields) async {
    if (updateFieldsError != null) throw updateFieldsError!;
    fieldUpdates.add((uid, fields));
  }

  @override
  Future<String> uploadAvatar(String uid, Uint8List jpegBytes) async {
    if (uploadError != null) throw uploadError!;
    uploads.add(jpegBytes);
    return uploadUrl;
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
  }
}

/// Counts sign-outs instead of touching Firebase.
class FakeAuthFlow extends AuthFlow {
  FakeAuthFlow(super.ref);
  int signOutCalls = 0;

  @override
  Future<void> signOut() async => signOutCalls++;
}

class FakeAvatarPicker implements AvatarPicker {
  FakeAvatarPicker([this.bytes]);
  Uint8List? bytes;
  final sources = <ImageSource>[];

  @override
  Future<Uint8List?> pick(ImageSource source) async {
    sources.add(source);
    return bytes;
  }
}

UserModel testUser({
  String name = 'Krmanj',
  String phone = '7505448229',
  String? email = 'krmanj@example.com',
  DateTime? birthday,
  String? gender = 'male',
  String? city = 'erbil',
  bool notificationsEnabled = true,
}) =>
    UserModel(
      uid: 'u1',
      name: name,
      phone: phone,
      email: email,
      birthday: birthday ?? DateTime.utc(1995, 3, 10, 12),
      gender: gender,
      city: city,
      notificationsEnabled: notificationsEnabled,
    );

const testCities = [
  CityModel(id: 'erbil', name: LocalizedText('Erbil', ar: 'أربيل', ku: 'هەولێر')),
  CityModel(id: 'duhok', name: LocalizedText('Duhok', ar: 'دهوك', ku: 'دهۆک')),
];

class ProfileHarness {
  ProfileHarness(this.container, this.router, this.users, this.auth, this.picker, this.openedLinks);
  final ProviderContainer container;
  final GoRouter router;
  final RecordingUserRepository users;
  final FakeAuthRepository auth;
  final FakeAvatarPicker picker;
  final List<Uri> openedLinks;

  FakeAuthFlow get authFlow => container.read(authFlowProvider) as FakeAuthFlow;
}

/// Paths that render a stub page showing the path (e.g. find.text('/sign-in')).
const _stubPaths = [
  AppRoutes.signIn,
  AppRoutes.signUp,
  AppRoutes.completeProfile,
  AppRoutes.orders,
  AppRoutes.wishlists,
  AppRoutes.secretSanta,
  AppRoutes.savedCards,
  AppRoutes.wallet,
  AppRoutes.inviteAndEarn,
  AppRoutes.specialRequests,
  AppRoutes.addresses,
  AppRoutes.giftCards,
  AppRoutes.promoCodes,
  AppRoutes.contactUs,
];

/// Pumps the Profile area inside a real GoRouter: `/main` = ProfileScreen,
/// the three profile sub-screens are real, `/otp` is a stub with a
/// "verify-ok" button that pops `true` (like the OTP screen for changePhone).
/// Locale and theme follow `localeProvider` / `themeModeProvider`.
Future<ProfileHarness> pumpProfileApp(
  WidgetTester tester, {
  String initialPath = AppRoutes.main,
  List<String> push = const [],
  UserModel? user,
  bool signedIn = true,
  Stream<UserModel?> Function()? profileStream,
  ReferralSettings referral = const ReferralSettings(),
  PaymentSettings payments = const PaymentSettings(),
  WalletModel wallet = WalletModel.empty,
  RecordingUserRepository? users,
  FakeAuthRepository? auth,
  FakeAvatarPicker? picker,
  bool phoneChangeSupported = true,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 1600),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'locale': locale, 'theme_mode': themeMode.name});
  final prefs = await SharedPreferences.getInstance();

  final repository = users ?? RecordingUserRepository();
  final authRepository = auth ?? FakeAuthRepository();
  final avatarPicker = picker ?? FakeAvatarPicker();
  final opened = <Uri>[];
  final profile = signedIn ? (user ?? testUser()) : null;

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    authStateProvider.overrideWith((ref) => Stream.value(null)),
    currentUserProfileProvider.overrideWith((ref) => profileStream?.call() ?? Stream.value(profile)),
    isSignedInProvider.overrideWithValue(signedIn),
    referralSettingsProvider.overrideWith((ref) => Stream.value(referral)),
    paymentSettingsProvider.overrideWith((ref) => Stream.value(payments)),
    walletProvider.overrideWith((ref) => Stream.value(wallet)),
    activeCitiesProvider.overrideWithValue(const AsyncValue.data(testCities)),
    userRepositoryProvider.overrideWithValue(repository),
    authRepositoryProvider.overrideWithValue(authRepository),
    authFlowProvider.overrideWith((ref) => FakeAuthFlow(ref)),
    appVersionLabelProvider.overrideWith((ref) async => '1.0.0 (1)'),
    phoneChangeSupportedProvider.overrideWithValue(phoneChangeSupported),
    avatarPickerProvider.overrideWithValue(avatarPicker),
    externalLinkOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return true;
    }),
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: initialPath,
    routes: [
      GoRoute(path: AppRoutes.main, builder: (_, __) => const ProfileScreen()),
      GoRoute(path: AppRoutes.editProfile, builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: AppRoutes.changePhone, builder: (_, __) => const ChangePhoneScreen()),
      GoRoute(path: AppRoutes.settings, builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, _) => Scaffold(
          body: Column(
            children: [
              const Text(AppRoutes.otp),
              TextButton(onPressed: () => context.pop(true), child: const Text('verify-ok')),
            ],
          ),
        ),
      ),
      for (final path in _stubPaths)
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(path))),
    ],
  );

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final appLocale = ref.watch(localeProvider);
        return MaterialApp.router(
          routerConfig: router,
          locale: appLocale,
          theme: AppTheme.lightTheme(appLocale),
          darkTheme: AppTheme.darkTheme(appLocale),
          themeMode: ref.watch(themeModeProvider),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...KurdishFallbackLocalizations.delegates,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        );
      },
    ),
  ));
  for (final path in push) {
    unawaited(router.push(path));
    await tester.pump();
  }
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return ProfileHarness(container, router, repository, authRepository, avatarPicker, opened);
}

AppLocalizations l10nFor(String code) => lookupAppLocalizations(Locale(code));
