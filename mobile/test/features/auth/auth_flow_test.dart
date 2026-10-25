import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/providers/session_providers.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/auth/presentation/providers/auth_flow.dart';
import 'package:golden_gift/features/profile/data/datasources/user_repository.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_fakes.dart';

Future<(ProviderContainer, FakeUserRepository, FakeAnalytics, SharedPreferences)> _container({
  UserModel? existing,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final users = FakeUserRepository(existing: existing);
  final analytics = FakeAnalytics();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sharedPrefs),
    userRepositoryProvider.overrideWithValue(users),
    analyticsServiceProvider.overrideWithValue(analytics),
    authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
  ]);
  addTearDown(container.dispose);
  return (container, users, analytics, sharedPrefs);
}

void main() {
  group('splitE164', () {
    test('uses the longest matching dial code', () {
      expect(splitE164('+9647501234567'), ('+964', '7501234567'));
      expect(splitE164('+905321234567'), ('+90', '5321234567'));
      expect(splitE164('+12025550123'), ('+1', '2025550123'));
    });
  });

  group('AuthFlow.afterSignIn (SRS AUTH-3/4)', () {
    test('returning user → Main, logs login, clears guest mode, remembers sign-in', () async {
      final (c, users, analytics, prefs) = await _container(
        existing: const UserModel(uid: 'u1', name: 'Sara', phone: '7501234567', locale: 'en'),
        prefs: {PrefsKeys.guestMode: true},
      );
      final outcome = await c.read(authFlowProvider).afterSignIn(
            FakeUser(phoneNumber: '+9647501234567'),
            method: SignInMethod.phone,
          );
      expect(outcome, isA<GoToMain>());
      expect(users.created, isEmpty);
      expect(analytics.events.keys, [AnalyticsEvents.login]);
      expect(c.read(guestModeProvider), isFalse);
      expect(prefs.getBool(PrefsKeys.signedInBefore), isTrue);
    });

    test('returning user with another stored language → profile locale synced', () async {
      final (c, users, _, _) = await _container(
        existing: const UserModel(uid: 'u1', name: 'Sara', phone: '7501234567', locale: 'ar'),
      );
      await c.read(authFlowProvider).afterSignIn(FakeUser(), method: SignInMethod.phone);
      expect(users.fieldUpdates, [
        {'locale': 'en'}
      ]);
    });

    test('new phone user with Sign Up data → users doc created → Main', () async {
      final (c, users, analytics, _) = await _container();
      final outcome = await c.read(authFlowProvider).afterSignIn(
            FakeUser(uid: 'new', phoneNumber: '+9647501234567'),
            method: SignInMethod.phone,
            pending: const PendingSignUp(name: '  Sara Ahmed ', email: 'sara@example.com', referralCode: 'AB3D9K'),
          );
      expect(outcome, isA<GoToMain>());
      final created = users.created.single;
      expect(created.uid, 'new');
      expect(created.name, 'Sara Ahmed');
      expect(created.phone, '7501234567');
      expect(created.countryCode, '+964');
      expect(created.referralCodeEntered, 'AB3D9K');
      expect(created.deviceId, isNotEmpty);
      expect(created.locale, 'en');
      expect(analytics.events[AnalyticsEvents.signUp], {'method': 'phone'});
      // Exactly the creation keys the production rules allow (no server-owned fields).
      expect(created.toCreateMap().keys.toSet(), {
        'name', 'email', 'phone', 'countryCode', 'locale', 'referralCodeEntered', 'deviceId',
        'photoUrl', 'notificationsEnabled', 'profileCompleted',
      });
    });

    test('phone sign-in with an unknown number → complete profile with the verified phone', () async {
      final (c, users, _, _) = await _container();
      final outcome = await c.read(authFlowProvider).afterSignIn(
            FakeUser(phoneNumber: '+9647701234567'),
            method: SignInMethod.phone,
          );
      expect(users.created, isEmpty);
      final prefill = (outcome as GoToCompleteProfile).prefill;
      expect(prefill.phoneVerified, isTrue);
      expect(prefill.phone, '7701234567');
      expect(prefill.countryCode, '+964');
    });

    test('Google user without profile → complete profile, phone still to verify (AUTH-4)', () async {
      final (c, _, _, _) = await _container();
      final outcome = await c.read(authFlowProvider).afterSignIn(
            FakeUser(displayName: 'Sara Ahmed', email: 'sara@gmail.com', providers: ['google.com']),
            method: SignInMethod.google,
          );
      final prefill = (outcome as GoToCompleteProfile).prefill;
      expect(prefill.name, 'Sara Ahmed');
      expect(prefill.email, 'sara@gmail.com');
      expect(prefill.phoneVerified, isFalse);
      expect(prefill.method, SignInMethod.google);
    });

    test('install id is stable and reused as deviceId', () async {
      final (c, users, _, _) = await _container();
      final id = c.read(installIdProvider);
      await c.read(authFlowProvider).createProfile(
            FakeUser(uid: 'x', phoneNumber: '+9647501234567'),
            method: SignInMethod.phone,
            name: 'Sara',
            phone: '7501234567',
            countryCode: '+964',
          );
      expect(users.created.single.deviceId, id);
      expect(c.read(installIdProvider), id);
    });
  });

  test('signOut clears the local cart cache and guest flag but keeps language & theme (AUTH-6)', () async {
    final (c, _, _, prefs) = await _container(prefs: {
      'cart_items': '[]',
      'locale': 'ckb',
      'theme_mode': 'dark',
      PrefsKeys.guestMode: true,
    });
    await c.read(authFlowProvider).signOut();
    expect(prefs.containsKey('cart_items'), isFalse);
    expect(prefs.getString('locale'), 'ckb');
    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getBool(PrefsKeys.guestMode), isFalse);
  });
}
