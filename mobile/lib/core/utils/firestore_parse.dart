import 'package:cloud_firestore/cloud_firestore.dart';

/// Tolerant readers for Firestore maps. Documents may be written by the app,
/// the admin dashboard, Cloud Functions or the seeder, so numbers can arrive
/// as int or double and dates as Timestamp, DateTime, millis or ISO strings.
class FirestoreParse {
  FirestoreParse._();

  static DateTime? date(Object? v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int integer(Object? v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static int? integerOrNull(Object? v) => v == null ? null : integer(v);

  static double decimal(Object? v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static bool boolean(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

  static String? stringOrNull(Object? v) {
    if (v is! String) return null;
    return v.isEmpty ? null : v;
  }

  static List<String> stringList(Object? v) =>
      v is List ? v.whereType<String>().toList() : const [];

  static List<Map<String, dynamic>> mapList(Object? v) => v is List
      ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : const [];

  static Map<String, dynamic> map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// Enum from its stored string value; unknown or missing → [fallback].
  static T enumValue<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static T? enumOrNull<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
