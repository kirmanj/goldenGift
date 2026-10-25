import 'package:flutter/foundation.dart';

/// Build-time switches, passed with `--dart-define`.
///
///   flutter run --dart-define=USE_EMULATOR=true
///   flutter run --dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=192.168.1.20
///
/// EMULATOR_HOST defaults to localhost (10.0.2.2 on the Android emulator).
/// For a physical device, pass your Mac's LAN IP.
class AppEnv {
  AppEnv._();

  static const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');

  static const String _emulatorHost = String.fromEnvironment('EMULATOR_HOST');

  static String get emulatorHost {
    if (_emulatorHost.isNotEmpty) return _emulatorHost;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return '10.0.2.2';
    return 'localhost';
  }

  /// Ports match `emulators` in the repo-root firebase.json.
  static const int authPort = 9099;
  static const int firestorePort = 8080;
  static const int storagePort = 9199;
  static const int functionsPort = 5001;

  /// Address map pin (SRS §5.20, Phase 9). Needs a Google Maps key on the
  /// platform (Android `-PMAPS_API_KEY`, iOS `MAPS_API_KEY` build setting) —
  /// build with `--dart-define=MAPS_ENABLED=true` once it is set. Off on web.
  static const bool _mapsFlag = bool.fromEnvironment('MAPS_ENABLED');
  static bool get mapsEnabled => _mapsFlag && !kIsWeb;

  /// App Check on web (SRS §8 Security) needs a reCAPTCHA Enterprise site key
  /// registered for the goldengift-iq web app: `--dart-define=RECAPTCHA_SITE_KEY=…`.
  /// Empty = web runs without App Check (fine until ENFORCE_APP_CHECK is on).
  static const String recaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');

  /// Cloud Functions region (SRS §7).
  static const String functionsRegion = 'europe-west1';
}
