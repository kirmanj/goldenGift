// Dashboard constants. The shared enums (OrderStatus, PaymentMethod, …) are
// re-exported from the customer app package so they can't diverge
// (CLAUDE.md); Firestore stores their `.name` strings (SRS §6.15).
export 'package:golden_gift/core/constants/app_constants.dart' hide AppConstants;

class AdminConstants {
  AdminConstants._();

  static const String appName = 'Golden Gift';
  static const String currencyCode = 'IQD';
  static const String defaultCountryCode = '+964';
  static const String defaultLocale = 'en';
  static const List<String> supportedLocales = ['en', 'ar', 'ckb'];

  /// Cities served (SRS §4.3). Admin can extend via app_settings/cities.
  static const List<String> defaultCities = [
    'Erbil', 'Sulaymaniyah', 'Duhok', 'Baghdad', 'Basra', 'Mosul', 'Kirkuk',
  ];
}
