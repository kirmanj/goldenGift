import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/providers/session_providers.dart';
import '../../../../core/utils/app_version.dart';
import '../../../../models/app_settings_model.dart';
import '../../../auth/data/datasources/auth_repository.dart';
import '../../../auth/presentation/providers/auth_flow.dart';
import '../../../profile/data/datasources/user_repository.dart';

enum StartupDestination { maintenance, updateRequired, onboarding, signUp, signIn, completeProfile, main }

class StartupDecision {
  const StartupDecision(this.destination, [this.prefill]);
  final StartupDestination destination;
  final ProfilePrefill? prefill;
}

/// Where the splash screen goes (SRS §5.1, §3, §8 Versioning). Never blocks
/// longer than the timeouts: offline launches fall through to cached state.
class StartupDecider {
  StartupDecider(this._ref);
  final Ref _ref;

  static const settingsTimeout = Duration(seconds: 4);
  static const authTimeout = Duration(seconds: 3);
  static const profileTimeout = Duration(seconds: 4);

  Future<StartupDecision> decide() async {
    final general = await _generalSettings();
    if (general.maintenanceMode) return const StartupDecision(StartupDestination.maintenance);
    if (await _updateRequired(general)) return const StartupDecision(StartupDestination.updateRequired);

    final user = await _restoredUser();
    if (user != null) {
      try {
        final profile = await _ref.read(userRepositoryProvider).fetch(user.uid).timeout(profileTimeout);
        if (profile == null) {
          return StartupDecision(
            StartupDestination.completeProfile,
            _ref.read(authFlowProvider).prefillFor(user),
          );
        }
      } catch (_) {
        // Offline or slow: the session is valid, open the app from cache.
      }
      return const StartupDecision(StartupDestination.main);
    }

    if (!_ref.read(onboardingDoneProvider)) return const StartupDecision(StartupDestination.onboarding);
    if (_ref.read(guestModeProvider)) return const StartupDecision(StartupDestination.main);
    final signedInBefore =
        _ref.read(sharedPreferencesProvider).getBool(PrefsKeys.signedInBefore) ?? false;
    return StartupDecision(signedInBefore ? StartupDestination.signIn : StartupDestination.signUp);
  }

  Future<GeneralSettings> _generalSettings() async {
    try {
      return await _ref.read(generalSettingsProvider.future).timeout(settingsTimeout);
    } catch (_) {
      return const GeneralSettings();
    }
  }

  Future<bool> _updateRequired(GeneralSettings general) async {
    if (kIsWeb) return false;
    final minimum = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => general.minAppVersionIos,
      TargetPlatform.android => general.minAppVersionAndroid,
      _ => '',
    };
    if (minimum.isEmpty) return false;
    try {
      final info = await PackageInfo.fromPlatform();
      return AppVersion.isBelow(info.version, minimum);
    } catch (_) {
      return false;
    }
  }

  Future<User?> _restoredUser() async {
    final auth = _ref.read(authRepositoryProvider);
    try {
      return await auth.authStateChanges().first.timeout(authTimeout);
    } catch (_) {
      return auth.currentUser;
    }
  }
}

final startupDeciderProvider = Provider<StartupDecider>((ref) => StartupDecider(ref));
