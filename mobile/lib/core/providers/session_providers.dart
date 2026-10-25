import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'firebase_providers.dart';

/// Device-local session flags (SharedPreferences). Language and theme live in
/// locale_provider.dart / theme_provider.dart and survive logout (SRS AUTH-6).
class PrefsKeys {
  PrefsKeys._();
  static const onboardingDone = 'onboarding_done';
  static const guestMode = 'guest_mode';
  static const installId = 'install_id';

  /// Someone has signed in on this install before → logged-out launches open
  /// Sign In instead of Sign Up.
  static const signedInBefore = 'signed_in_before';

  /// Keys starting with this prefix are wiped on logout (local guest cart, Phase 4).
  static const cartPrefix = 'cart_';
}

/// Random per-install id, written to `users/{uid}.deviceId` at sign-up so
/// `onUserCreate` can reject same-device self-referrals (SRS §5.19).
final installIdProvider = Provider<String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final existing = prefs.getString(PrefsKeys.installId);
  if (existing != null) return existing;
  final id = const Uuid().v4();
  prefs.setString(PrefsKeys.installId, id);
  return id;
});

class BoolPrefNotifier extends StateNotifier<bool> {
  BoolPrefNotifier(this._prefs, this._key) : super(_prefs.getBool(_key) ?? false);
  final SharedPreferences _prefs;
  final String _key;

  Future<void> set(bool value) async {
    state = value;
    await _prefs.setBool(_key, value);
  }
}

/// Onboarding is shown once per install (SRS §5.1).
final onboardingDoneProvider = StateNotifierProvider<BoolPrefNotifier, bool>(
  (ref) => BoolPrefNotifier(ref.watch(sharedPreferencesProvider), PrefsKeys.onboardingDone),
);

/// The user chose "Continue as a guest" (SRS AUTH-5); next launch opens Main.
final guestModeProvider = StateNotifierProvider<BoolPrefNotifier, bool>(
  (ref) => BoolPrefNotifier(ref.watch(sharedPreferencesProvider), PrefsKeys.guestMode),
);

/// Clears device-local data that belongs to the signed-in session (SRS AUTH-6):
/// the local cart cache and the guest flag. Keeps language, theme, onboarding
/// and the install id.
Future<void> clearSessionPrefs(SharedPreferences prefs) async {
  for (final key in prefs.getKeys().toList()) {
    if (key.startsWith(PrefsKeys.cartPrefix)) await prefs.remove(key);
  }
  await prefs.setBool(PrefsKeys.guestMode, false);
}
