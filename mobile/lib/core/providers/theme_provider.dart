import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_providers.dart';

const _kThemeKey = 'theme_mode';

/// Light = Gold & White · Dark = Gold & Black · System follows the device.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._ref)
      : super(ThemeMode.values.byName(
            _ref.read(sharedPreferencesProvider).getString(_kThemeKey) ?? 'system'));
  final Ref _ref;

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _ref.read(sharedPreferencesProvider).setString(_kThemeKey, mode.name);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ThemeModeNotifier(ref));
