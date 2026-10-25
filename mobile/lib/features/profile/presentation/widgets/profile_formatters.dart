import '../../../../core/utils/app_dates.dart';

/// Display helpers for the Profile area. Pure functions, unit-tested.

/// "+964 750 123 4567". National digits are grouped in threes with a final
/// group of up to four. Always render the result left-to-right
/// (`textDirection: TextDirection.ltr`), also in Arabic and Kurdish.
String formatPhoneForDisplay(String countryCode, String nationalNumber) {
  final digits = nationalNumber.replaceAll(RegExp(r'\s'), '');
  if (digits.isEmpty) return countryCode;
  final groups = <String>[];
  var rest = digits;
  while (rest.length > 4) {
    groups.add(rest.substring(0, 3));
    rest = rest.substring(3);
  }
  groups.add(rest);
  return '$countryCode ${groups.join(' ')}';
}

/// 15/03/1995 — via AppDates (no intl locale data; Western digits in every language).
String formatBirthday(DateTime date) => AppDates.display(date);

/// Birthdays are stored as UTC noon so the calendar day survives any time
/// zone the profile is read in (±11 h).
DateTime birthdayValue(DateTime picked) => DateTime.utc(picked.year, picked.month, picked.day, 12);

bool sameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
