import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_providers.dart';

const _kLocaleKey = 'locale';

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier(this._ref)
      : super(Locale(_ref.read(sharedPreferencesProvider).getString(_kLocaleKey) ?? 'en'));
  final Ref _ref;

  Future<void> setLocale(String code) async {
    state = Locale(code);
    await _ref.read(sharedPreferencesProvider).setString(_kLocaleKey, code);
  }
}

final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale>((ref) => LocaleNotifier(ref));
