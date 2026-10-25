/// Semantic-version comparison for the forced-update check (SRS §8 Versioning).
class AppVersion {
  AppVersion._();

  /// True when [current] is lower than [minimum]. Missing parts count as 0 and
  /// build suffixes ("1.2.0+5", "1.2.0-beta") are ignored; an unparsable
  /// minimum never blocks the app.
  static bool isBelow(String current, String minimum) {
    final cur = _parts(current);
    final min = _parts(minimum);
    if (min == null || cur == null) return false;
    for (var i = 0; i < 3; i++) {
      if (cur[i] != min[i]) return cur[i] < min[i];
    }
    return false;
  }

  static List<int>? _parts(String version) {
    final core = version.trim().split(RegExp(r'[+-]')).first;
    if (core.isEmpty) return null;
    final parts = core.split('.');
    if (parts.length > 3) return null;
    final numbers = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0) return null;
      numbers.add(n);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers;
  }
}
