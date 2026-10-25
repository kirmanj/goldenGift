/// What the Users search box was given (SRS §9 Users "Search"): a phone, an
/// email or the start of a name. Empty input lists the newest users.
enum UserSearchMode { recent, phone, email, name }

/// An Iraqi mobile number in the two shapes Firestore may hold it:
/// `users/{uid}.phone` stores the national number (`7501234567`, with
/// `countryCode: +964`), Auth and older docs the E.164 form (`+9647501234567`).
class PhoneSearch {
  const PhoneSearch({required this.e164, required this.national});
  final String e164;
  final String national;

  @override
  bool operator ==(Object other) => other is PhoneSearch && other.e164 == e164 && other.national == national;

  @override
  int get hashCode => Object.hash(e164, national);
}

/// Arabic-Indic (٠-٩) and Extended Arabic-Indic (۰-۹) digits to ASCII; drops
/// everything else except a leading `+`.
String _asciiDigits(String input) {
  final b = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x30 && r <= 0x39) {
      b.writeCharCode(r);
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    }
  }
  return b.toString();
}

final _phoneChars = RegExp(r'^[+0-9٠-٩۰-۹\s\-().]+$');

/// True when [input] reads as a phone number rather than a name or email.
bool looksLikePhone(String input) {
  final t = input.trim();
  return t.isNotEmpty && !t.contains('@') && _phoneChars.hasMatch(t) && _asciiDigits(t).length >= 6;
}

/// `0750 123 4567`, `750-123-4567`, `+964 750 123 4567`, `00964 750…`,
/// `9647501234567` (and the same in Arabic digits) → `+9647501234567`.
/// Null unless it is an Iraqi mobile number (10 national digits starting with 7).
PhoneSearch? normalizeIraqiPhone(String input) {
  final t = input.trim();
  if (t.isEmpty || t.contains('@')) return null;
  var digits = _asciiDigits(t);
  final international = t.startsWith('+') || digits.startsWith('00');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('964') && (international || digits.length >= 12)) {
    digits = digits.substring(3);
  } else if (international) {
    return null; // another country code
  }
  if (digits.startsWith('0')) digits = digits.substring(1);
  if (digits.length != 10 || !digits.startsWith('7')) return null;
  return PhoneSearch(e164: '+964$digits', national: digits);
}

/// The parsed search box.
class UserSearchQuery {
  const UserSearchQuery._(this.mode, this.text, {this.phoneValues = const []});

  static const recent = UserSearchQuery._(UserSearchMode.recent, '');

  /// What the query matches: lower-cased email, name prefix or the display phone.
  final UserSearchMode mode;
  final String text;

  /// Phone mode: the `phone` values to match (one `whereIn` query).
  final List<String> phoneValues;

  /// False when a phone-looking input isn't an Iraqi mobile number (searched as typed).
  bool get isIraqiPhone => mode == UserSearchMode.phone && phoneValues.any((v) => v.startsWith('+964'));

  static UserSearchQuery parse(String input) {
    final t = input.trim();
    if (t.isEmpty) return recent;
    if (t.contains('@')) return UserSearchQuery._(UserSearchMode.email, t.toLowerCase());
    if (looksLikePhone(t)) {
      final iraqi = normalizeIraqiPhone(t);
      if (iraqi != null) {
        return UserSearchQuery._(UserSearchMode.phone, iraqi.e164, phoneValues: [iraqi.national, iraqi.e164]);
      }
      final digits = _asciiDigits(t);
      return UserSearchQuery._(UserSearchMode.phone, t.startsWith('+') ? '+$digits' : digits,
          phoneValues: {digits, '+$digits'}.toList());
    }
    return UserSearchQuery._(UserSearchMode.name, t);
  }

  /// One line under the search box saying how the input was read.
  String get description => switch (mode) {
        UserSearchMode.recent => 'Newest users first.',
        UserSearchMode.phone => isIraqiPhone
            ? 'Phone $text'
            : 'Phone digits "$text" (not an Iraqi mobile number — matched exactly as typed).',
        UserSearchMode.email => 'Email $text',
        UserSearchMode.name => 'Names starting with "$text" (case-sensitive).',
      };

  @override
  bool operator ==(Object other) => other is UserSearchQuery && other.mode == mode && other.text == text;

  @override
  int get hashCode => Object.hash(mode, text);
}
