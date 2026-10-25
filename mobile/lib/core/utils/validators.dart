import '../constants/country_codes.dart';

/// Why a field is invalid. Screens map these to localized messages, so the
/// rules stay testable without a BuildContext (SRS AUTH-8).
enum ValidationError {
  required,
  nameTooShort,
  nameTooLong,
  invalidEmail,
  invalidPhone,
  invalidReferralCode,
}

/// Sign-up / profile validation (SRS AUTH-8). Invalid input must never reach
/// Firebase, so screens validate with these before any call.
class Validators {
  Validators._();

  static const nameMin = 2;
  static const nameMax = 50;
  static const referralCodeLength = 6;

  static ValidationError? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return ValidationError.required;
    if (v.runes.length < nameMin) return ValidationError.nameTooShort;
    if (v.runes.length > nameMax) return ValidationError.nameTooLong;
    return null;
  }

  // Practical RFC 5322 subset: local@domain.tld, no spaces, one @.
  static final _email = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\.[A-Za-z]{2,}$",
  );

  /// Email is optional (SRS §2.4) but must be valid when given.
  static ValidationError? email(String? value, {bool required = false}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? ValidationError.required : null;
    if (v.length > 254 || v.contains('..') || !_email.hasMatch(v)) {
      return ValidationError.invalidEmail;
    }
    return null;
  }

  /// Digits only, Eastern Arabic / Persian digits converted, the trunk "0"
  /// removed: "0750 123 4567" → "7501234567".
  static String normalizePhone(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        buffer.writeCharCode(rune);
      } else if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(0x30 + rune - 0x0660); // Arabic-Indic ٠-٩
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(0x30 + rune - 0x06F0); // Extended Arabic-Indic ۰-۹
      }
    }
    final digits = buffer.toString();
    return digits.startsWith('0') ? digits.substring(1) : digits;
  }

  static ValidationError? phone(String? value, CountryCode country) {
    final digits = normalizePhone(value ?? '');
    if (digits.isEmpty) return ValidationError.required;
    if (!country.acceptsLength(digits.length)) return ValidationError.invalidPhone;
    // Iraqi mobile numbers start with 7 (75x Korek, 77x Asiacell, 78x/79x Zain).
    if (country.dialCode == CountryCodes.iraq.dialCode && !digits.startsWith('7')) {
      return ValidationError.invalidPhone;
    }
    return null;
  }

  /// E.164 for Firebase Phone Auth, e.g. +9647501234567.
  static String e164(String value, CountryCode country) => '${country.dialCode}${normalizePhone(value)}';

  static String normalizeReferralCode(String value) =>
      value.replaceAll(RegExp(r'\s'), '').toUpperCase();

  /// Optional; format only. Existence / self / same-device are checked by
  /// `onUserCreate` (SRS AUTH-8).
  static ValidationError? referralCode(String? value) {
    final v = normalizeReferralCode(value ?? '');
    if (v.isEmpty) return null;
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(v)) return ValidationError.invalidReferralCode;
    return null;
  }
}
