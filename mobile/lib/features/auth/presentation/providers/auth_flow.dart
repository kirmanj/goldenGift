import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/country_codes.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../../../core/providers/session_providers.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/push_service.dart';
import '../../../../models/user_model.dart';
import '../../../profile/data/datasources/user_repository.dart';
import '../../data/datasources/auth_repository.dart';

enum SignInMethod { phone, google, apple }

/// What the user typed on Sign Up before the OTP step (SRS AUTH-1).
class PendingSignUp {
  const PendingSignUp({
    required this.name,
    this.email,
    this.referralCode,
  });

  final String name;
  final String? email;
  final String? referralCode;
}

/// Prefill for "Complete your account" when someone signs in without a profile
/// (phone sign-in with a new number, or Google / Apple).
class ProfilePrefill {
  const ProfilePrefill({
    required this.method,
    this.name,
    this.email,
    this.phone,
    this.countryCode = AppConstants.defaultCountryCode,
  });

  final SignInMethod method;
  final String? name;
  final String? email;

  /// National number when the account already has a verified phone.
  final String? phone;
  final String countryCode;

  bool get phoneVerified => phone != null && phone!.isNotEmpty;
}

sealed class AuthOutcome {
  const AuthOutcome();
}

class GoToMain extends AuthOutcome {
  const GoToMain();
}

class GoToCompleteProfile extends AuthOutcome {
  const GoToCompleteProfile(this.prefill);
  final ProfilePrefill prefill;
}

/// Splits "+9647501234567" into (+964, 7501234567) using the longest matching dial code.
(String, String) splitE164(String e164) {
  final codes = [...CountryCodes.all]..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
  for (final c in codes) {
    if (e164.startsWith(c.dialCode)) return (c.dialCode, e164.substring(c.dialCode.length));
  }
  // Not in our list: keep the whole number; the dial code is unknown.
  return ('+', e164.replaceFirst('+', ''));
}

/// Runs after any successful sign-in (SRS AUTH-3/4/5): returning user → Main;
/// new user with Sign Up data → create `users/{uid}` → Main; otherwise ask
/// for the missing profile fields.
class AuthFlow {
  AuthFlow(this._ref);
  final Ref _ref;

  UserRepository get _users => _ref.read(userRepositoryProvider);
  AnalyticsService get _analytics => _ref.read(analyticsServiceProvider);

  Future<AuthOutcome> afterSignIn(User user, {required SignInMethod method, PendingSignUp? pending}) async {
    final existing = await _users.fetch(user.uid);
    if (existing != null) {
      await _analytics.log(AnalyticsEvents.login, {'method': method.name});
      await _onSignedIn();
      final locale = _ref.read(localeProvider).languageCode;
      if (existing.locale != locale) {
        await _users.updateFields(user.uid, {'locale': locale});
      }
      return const GoToMain();
    }
    final phone = user.phoneNumber;
    if (pending != null && phone != null) {
      final (dial, national) = splitE164(phone);
      await createProfile(
        user,
        method: method,
        name: pending.name,
        email: pending.email,
        phone: national,
        countryCode: dial,
        referralCode: pending.referralCode,
      );
      return const GoToMain();
    }
    return GoToCompleteProfile(prefillFor(user, method: method));
  }

  /// What we already know about a signed-in user without a profile document.
  ProfilePrefill prefillFor(User user, {SignInMethod? method}) {
    final phone = user.phoneNumber;
    final (dial, national) = phone == null ? (AppConstants.defaultCountryCode, null) : splitE164(phone);
    return ProfilePrefill(
      method: method ?? methodOf(user),
      name: user.displayName,
      email: user.email,
      phone: national,
      countryCode: dial,
    );
  }

  static SignInMethod methodOf(User user) {
    final providers = user.providerData.map((p) => p.providerId);
    if (providers.contains('google.com')) return SignInMethod.google;
    if (providers.contains('apple.com')) return SignInMethod.apple;
    return SignInMethod.phone;
  }

  /// Writes the first `users/{uid}` document (SRS AUTH-3); `onUserCreate`
  /// adds the wallet, referral code and server-owned fields.
  Future<void> createProfile(
    User user, {
    required SignInMethod method,
    required String name,
    String? email,
    String? phone,
    required String countryCode,
    String? referralCode,
  }) async {
    await _users.create(UserModel(
      uid: user.uid,
      name: name.trim(),
      email: (email == null || email.trim().isEmpty) ? null : email.trim(),
      phone: phone ?? '',
      countryCode: countryCode,
      photoUrl: user.photoURL,
      locale: _ref.read(localeProvider).languageCode,
      referralCodeEntered: (referralCode == null || referralCode.isEmpty) ? null : referralCode,
      deviceId: _ref.read(installIdProvider),
    ));
    await _analytics.log(AnalyticsEvents.signUp, {'method': method.name});
    await _onSignedIn();
  }

  Future<void> _onSignedIn() async {
    await _ref.read(guestModeProvider.notifier).set(false);
    await _ref.read(sharedPreferencesProvider).setBool(PrefsKeys.signedInBefore, true);
  }

  /// SRS AUTH-6: sign out, clear the local cart cache, keep the language.
  /// The device's push token is removed first, while still signed in.
  Future<void> signOut() async {
    final uid = _ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid != null) {
      try {
        await _ref.read(pushServiceProvider).unregister(uid);
      } catch (_) {
        // never block sign-out on push cleanup
      }
    }
    await _ref.read(authRepositoryProvider).signOut();
    await clearSessionPrefs(_ref.read(sharedPreferencesProvider));
    _ref.invalidate(guestModeProvider);
  }
}

final authFlowProvider = Provider<AuthFlow>((ref) => AuthFlow(ref));
