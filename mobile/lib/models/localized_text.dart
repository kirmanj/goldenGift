/// A trilingual catalogue string (SRS §4.2, §6).
///
/// Firestore stores it as three sibling fields: `title`, `titleAr`, `titleKu`
/// (English is the base field). [resolve] falls back to English when the
/// requested translation is missing or empty.
class LocalizedText {
  const LocalizedText(this.en, {this.ar, this.ku});

  final String en;
  final String? ar;
  final String? ku;

  static const empty = LocalizedText('');

  factory LocalizedText.fromMap(Map<String, dynamic> map, String field) {
    String? read(String key) {
      final v = map[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    return LocalizedText(
      read(field) ?? '',
      ar: read('${field}Ar'),
      ku: read('${field}Ku'),
    );
  }

  Map<String, dynamic> toMap(String field) => {
        field: en,
        if (ar != null) '${field}Ar': ar,
        if (ku != null) '${field}Ku': ku,
      };

  /// Text for a language code (`en`, `ar`, `ckb`); falls back to English.
  String resolve(String languageCode) {
    switch (languageCode) {
      case 'ar':
        return ar ?? en;
      case 'ckb':
        return ku ?? en;
      default:
        return en;
    }
  }

  bool get isEmpty => en.isEmpty && ar == null && ku == null;

  /// All non-empty variants — used to build search keywords.
  Iterable<String> get all => [en, if (ar != null) ar!, if (ku != null) ku!];

  @override
  bool operator ==(Object other) =>
      other is LocalizedText && other.en == en && other.ar == ar && other.ku == ku;

  @override
  int get hashCode => Object.hash(en, ar, ku);

  @override
  String toString() => en;
}
