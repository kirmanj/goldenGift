import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Flutter ships no Material / Cupertino / Widgets localizations for Kurdish
/// Sorani (`ckb`). Without these delegates, `ckb` renders left-to-right and
/// widgets that need MaterialLocalizations (back-button tooltips, text
/// fields, date pickers) throw. For `ckb` they load the Arabic resources,
/// which gives right-to-left layout and Arabic-script system strings.
///
/// List them in `localizationsDelegates` BEFORE the Global* delegates —
/// Localizations uses the first delegate that supports a locale for each type.
class KurdishFallbackLocalizations {
  KurdishFallbackLocalizations._();

  static const delegates = <LocalizationsDelegate<dynamic>>[
    _CkbMaterialDelegate(),
    _CkbCupertinoDelegate(),
    _CkbWidgetsDelegate(),
  ];

  static const _fallback = Locale('ar');

  static bool _isCkb(Locale locale) => locale.languageCode == 'ckb';
}

class _CkbMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _CkbMaterialDelegate();

  @override
  bool isSupported(Locale locale) => KurdishFallbackLocalizations._isCkb(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(KurdishFallbackLocalizations._fallback);

  @override
  bool shouldReload(_CkbMaterialDelegate old) => false;
}

class _CkbCupertinoDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CkbCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => KurdishFallbackLocalizations._isCkb(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(KurdishFallbackLocalizations._fallback);

  @override
  bool shouldReload(_CkbCupertinoDelegate old) => false;
}

class _CkbWidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _CkbWidgetsDelegate();

  @override
  bool isSupported(Locale locale) => KurdishFallbackLocalizations._isCkb(locale);

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(KurdishFallbackLocalizations._fallback);

  @override
  bool shouldReload(_CkbWidgetsDelegate old) => false;
}
