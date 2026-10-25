import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/providers/session_providers.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/onboarding/presentation/providers/startup_decider.dart';
import 'package:golden_gift/features/profile/data/datasources/user_repository.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_fakes.dart';

Future<StartupDecision> _decide({
  GeneralSettings settings = const GeneralSettings(),
  FakeUser? user,
  FakeUserRepository? users,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sharedPrefs),
    generalSettingsProvider.overrideWith((ref) => Stream.value(settings)),
    authRepositoryProvider.overrideWithValue(FakeAuthRepository(user: user)),
    userRepositoryProvider.overrideWithValue(users ?? FakeUserRepository()),
    analyticsServiceProvider.overrideWithValue(FakeAnalytics()),
  ]);
  addTearDown(container.dispose);
  return container.read(startupDeciderProvider).decide();
}

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    PackageInfo.setMockInitialValues(
      appName: 'Golden Gift',
      packageName: 'com.goldengift.golden_gift',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  const profile = UserModel(uid: 'u1', name: 'Sara', phone: '7501234567');

  test('maintenance mode wins over everything', () async {
    final d = await _decide(settings: const GeneralSettings(maintenanceMode: true), user: FakeUser());
    expect(d.destination, StartupDestination.maintenance);
  });

  test('installed version below minAppVersion → update required', () async {
    final d = await _decide(settings: const GeneralSettings(minAppVersionAndroid: '2.0.0'));
    expect(d.destination, StartupDestination.updateRequired);
  });

  test('version at the minimum passes', () async {
    final d = await _decide(settings: const GeneralSettings(minAppVersionAndroid: '1.0.0'));
    expect(d.destination, isNot(StartupDestination.updateRequired));
  });

  test('signed in with a profile → main', () async {
    final d = await _decide(user: FakeUser(), users: FakeUserRepository(existing: profile));
    expect(d.destination, StartupDestination.main);
  });

  test('signed in without a profile (quit mid sign-up) → complete profile', () async {
    final d = await _decide(user: FakeUser(phoneNumber: '+9647501234567'));
    expect(d.destination, StartupDestination.completeProfile);
    expect(d.prefill!.phone, '7501234567');
  });

  test('signed in but offline → main from cache', () async {
    final d = await _decide(user: FakeUser(), users: FakeUserRepository()..fetchError = Exception('offline'));
    expect(d.destination, StartupDestination.main);
  });

  test('first launch → onboarding', () async {
    final d = await _decide();
    expect(d.destination, StartupDestination.onboarding);
  });

  test('guest who skipped sign-up → main', () async {
    final d = await _decide(prefs: {PrefsKeys.onboardingDone: true, PrefsKeys.guestMode: true});
    expect(d.destination, StartupDestination.main);
  });

  test('logged out after using an account → sign in', () async {
    final d = await _decide(prefs: {PrefsKeys.onboardingDone: true, PrefsKeys.signedInBefore: true});
    expect(d.destination, StartupDestination.signIn);
  });

  test('never had an account → sign up', () async {
    final d = await _decide(prefs: {PrefsKeys.onboardingDone: true});
    expect(d.destination, StartupDestination.signUp);
  });
}
