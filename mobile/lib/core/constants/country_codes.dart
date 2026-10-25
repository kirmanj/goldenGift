/// Country codes offered by the phone field (SRS AUTH-1, AUTH-8).
///
/// `nationalLength` is the number of digits after the country code, without
/// the trunk prefix "0" that people often type (0750… → 750…).
class CountryCode {
  const CountryCode({
    required this.isoCode,
    required this.dialCode,
    required this.flag,
    required this.name,
    required this.nationalLength,
    this.nationalLengthMax,
  });

  final String isoCode;
  final String dialCode;
  final String flag;

  /// English name; the picker also shows the dial code, which is universal.
  final String name;
  final int nationalLength;
  final int? nationalLengthMax;

  bool acceptsLength(int length) =>
      length >= nationalLength && length <= (nationalLengthMax ?? nationalLength);
}

class CountryCodes {
  CountryCodes._();

  static const iraq = CountryCode(
      isoCode: 'IQ', dialCode: '+964', flag: '🇮🇶', name: 'Iraq', nationalLength: 10);

  /// Iraq first (default, SRS §2.4), then neighbours and the main diaspora countries.
  static const all = <CountryCode>[
    iraq,
    CountryCode(isoCode: 'TR', dialCode: '+90', flag: '🇹🇷', name: 'Türkiye', nationalLength: 10),
    CountryCode(isoCode: 'IR', dialCode: '+98', flag: '🇮🇷', name: 'Iran', nationalLength: 10),
    CountryCode(isoCode: 'SY', dialCode: '+963', flag: '🇸🇾', name: 'Syria', nationalLength: 9),
    CountryCode(isoCode: 'JO', dialCode: '+962', flag: '🇯🇴', name: 'Jordan', nationalLength: 9),
    CountryCode(isoCode: 'SA', dialCode: '+966', flag: '🇸🇦', name: 'Saudi Arabia', nationalLength: 9),
    CountryCode(isoCode: 'KW', dialCode: '+965', flag: '🇰🇼', name: 'Kuwait', nationalLength: 8),
    CountryCode(isoCode: 'AE', dialCode: '+971', flag: '🇦🇪', name: 'United Arab Emirates', nationalLength: 9),
    CountryCode(isoCode: 'LB', dialCode: '+961', flag: '🇱🇧', name: 'Lebanon', nationalLength: 7, nationalLengthMax: 8),
    CountryCode(isoCode: 'DE', dialCode: '+49', flag: '🇩🇪', name: 'Germany', nationalLength: 10, nationalLengthMax: 11),
    CountryCode(isoCode: 'SE', dialCode: '+46', flag: '🇸🇪', name: 'Sweden', nationalLength: 7, nationalLengthMax: 9),
    CountryCode(isoCode: 'GB', dialCode: '+44', flag: '🇬🇧', name: 'United Kingdom', nationalLength: 10),
    CountryCode(isoCode: 'US', dialCode: '+1', flag: '🇺🇸', name: 'United States', nationalLength: 10),
  ];

  static CountryCode byDialCode(String dialCode) =>
      all.firstWhere((c) => c.dialCode == dialCode, orElse: () => iraq);
}
