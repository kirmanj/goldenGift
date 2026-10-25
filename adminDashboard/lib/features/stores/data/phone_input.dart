import 'package:golden_gift/core/constants/country_codes.dart';
import 'package:golden_gift/core/utils/validators.dart';

/// Phone numbers typed by staff: `+<country><number>` as given, or a local
/// Iraqi mobile (`0750 123 4567`, Eastern Arabic digits allowed) → E.164.
/// Returns null when the input is not a valid number.
String? normalizeStaffPhone(String input) {
  final v = input.trim();
  if (v.isEmpty) return null;
  if (v.startsWith('+') || v.startsWith('00')) {
    final digits = Validators.normalizePhone(v.startsWith('00') ? v.substring(2) : v);
    // normalizePhone drops one leading 0; an international number never has one.
    if (digits.length < 8 || digits.length > 15) return null;
    return '+$digits';
  }
  if (Validators.phone(v, CountryCodes.iraq) != null) return null;
  return Validators.e164(v, CountryCodes.iraq);
}

/// Form validator: optional unless [required]; when given it must parse.
String? validateStaffPhone(String? input, {bool required = false}) {
  final v = input?.trim() ?? '';
  if (v.isEmpty) return required ? 'Required' : null;
  return normalizeStaffPhone(v) == null ? 'Enter a valid phone, e.g. 0750 123 4567 or +9647501234567' : null;
}

/// Form validator for an optional email.
String? validateStaffEmail(String? input) =>
    Validators.email(input) == null ? null : 'Enter a valid email address';
