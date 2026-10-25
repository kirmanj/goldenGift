import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 10 translation guard (SRS §8 Localization: 100 % string coverage in
/// en / ar / ckb). Pure file checks on assets/lang/*.arb — runs without
/// building the app.
///
/// * every app_en.arb key exists in app_ar.arb and app_ckb.arb, non-empty,
///   with the same placeholders;
/// * ICU plural / select messages parse, and each has an `other` branch;
/// * no ar / ckb value is identical to English, or mostly Latin letters
///   (brand names, codes and units in [_latinAllowed] don't count);
/// * Arabic values don't use Kurdish-only letters and Kurdish values don't
///   use the Arabic ك / ي (a sign of text pasted into the wrong file);
/// * no duplicate keys (JSON parsing would silently keep the last one);
/// * untranslated.txt (written by `flutter gen-l10n`) stays `{}`.

const _locales = ['ar', 'ckb'];

/// Keys whose translation is legitimately identical to English (language
/// names are shown in their own script; no letters at all).
const _sameAsEnglishAllowed = {
  'languageEnglish', // "English" is listed in English in every language
  'languageArabic', // "العربية" in every language
  'languageKurdish', // "کوردی" in every language
  'priceBetween', // "{min} – {max}"
};

/// Latin tokens that may appear in Arabic / Kurdish text.
final _latinAllowed = RegExp(
  r'\b(IQD|GG|Golden Gift|Golden|Gift|WhatsApp|Instagram|Google|Apple|Gemini|SMS|OTP|PIN|QR|ID|URL|AI|'
  r'FastPay|ZainCash|Zain|Visa|Mastercard|Algolia|Erbil|https?|goldengift\.app|XXXX|cm|kg|km|English)\b',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('assets/lang/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;

Iterable<String> _messageKeys(Map<String, dynamic> arb) => arb.keys.where((k) => !k.startsWith('@'));

// ─── A small ICU MessageFormat reader ───────────────────────────────────────

class IcuMessage {
  IcuMessage(this.placeholders, this.literal);

  /// Argument names: `{name}`, `{count, plural, …}`, `{kind, select, …}`.
  final Set<String> placeholders;

  /// All literal text of every branch, without the ICU syntax.
  final String literal;
}

class IcuError implements Exception {
  IcuError(this.message);
  final String message;
  @override
  String toString() => message;
}

IcuMessage parseIcu(String source) {
  final placeholders = <String>{};
  final literal = StringBuffer();
  var i = 0;

  String readName() {
    final start = i;
    while (i < source.length && RegExp(r'[\w]').hasMatch(source[i])) {
      i++;
    }
    return source.substring(start, i);
  }

  void skipSpaces() {
    while (i < source.length && source[i].trim().isEmpty) {
      i++;
    }
  }

  late void Function({required bool nested}) readMessage;

  void readArgument() {
    // At '{'.
    i++;
    skipSpaces();
    final name = readName();
    if (name.isEmpty) throw IcuError('empty argument name at $i in "$source"');
    placeholders.add(name);
    skipSpaces();
    if (i >= source.length) throw IcuError('unclosed "{" in "$source"');
    if (source[i] == '}') {
      i++;
      return;
    }
    if (source[i] != ',') throw IcuError('expected "," or "}" after "$name" in "$source"');
    i++;
    skipSpaces();
    final kind = readName();
    if (!{'plural', 'select', 'selectordinal'}.contains(kind)) {
      throw IcuError('unknown argument type "$kind" in "$source"');
    }
    skipSpaces();
    if (i >= source.length || source[i] != ',') throw IcuError('expected "," after "$kind" in "$source"');
    i++;
    final branches = <String>{};
    while (true) {
      skipSpaces();
      if (i >= source.length) throw IcuError('unclosed $kind in "$source"');
      if (source[i] == '}') {
        i++;
        break;
      }
      final start = i;
      while (i < source.length && source[i] != '{' && source[i].trim().isNotEmpty) {
        i++;
      }
      final selector = source.substring(start, i);
      if (selector.isEmpty) throw IcuError('empty selector in "$source"');
      branches.add(selector);
      skipSpaces();
      if (i >= source.length || source[i] != '{') throw IcuError('expected "{" after "$selector" in "$source"');
      i++;
      readMessage(nested: true);
    }
    if (!branches.contains('other')) throw IcuError('$kind without an "other" branch in "$source"');
    if (kind == 'plural') {
      const valid = {'zero', 'one', 'two', 'few', 'many', 'other'};
      final bad = branches.where((b) => !valid.contains(b) && !RegExp(r'^=\d+$').hasMatch(b));
      if (bad.isNotEmpty) throw IcuError('invalid plural selectors $bad in "$source"');
    }
  }

  readMessage = ({required bool nested}) {
    while (i < source.length) {
      final c = source[i];
      if (c == '{') {
        readArgument();
      } else if (c == '}') {
        if (!nested) throw IcuError('unbalanced "}" in "$source"');
        i++;
        return;
      } else {
        literal.write(c);
        i++;
      }
    }
    if (nested) throw IcuError('unclosed branch in "$source"');
  };

  readMessage(nested: false);
  return IcuMessage(placeholders, literal.toString());
}

/// Share of Latin letters among all letters of [text] (allowed tokens removed).
double latinShare(String text) {
  final cleaned = text.replaceAll(_latinAllowed, '');
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(cleaned).map((m) => m.group(0)!).toList();
  if (letters.isEmpty) return 0;
  final latin = letters.where((l) => RegExp('[A-Za-z]').hasMatch(l)).length;
  return latin / letters.length;
}

void main() {
  final en = _arb('en');
  final enKeys = _messageKeys(en).toList();

  test('icu parser sanity', () {
    expect(parseIcu('{count, plural, =1{one gift} other{{count} gifts}}').placeholders, {'count'});
    expect(parseIcu('{count, plural, =1{one gift} other{{count} gifts}}').literal, 'one gift gifts');
    expect(() => parseIcu('{count, plural, =1{one}}'), throwsA(isA<IcuError>()));
    expect(() => parseIcu('Hello {name'), throwsA(isA<IcuError>()));
    expect(latinShare(parseIcu('{count} صورة').literal), 0);
    expect(latinShare('Saved Cards'), 1);
    expect(latinShare('بەردەوامبە لەگەڵ Google'), 0);
  });

  test('every English message is valid ICU', () {
    final bad = <String>[];
    for (final k in enKeys) {
      try {
        parseIcu(en[k] as String);
      } on IcuError catch (e) {
        bad.add('$k: $e');
      }
    }
    expect(bad, isEmpty);
  });

  test('ARB files have no duplicate keys', () {
    for (final locale in ['en', ..._locales]) {
      final src = File('assets/lang/app_$locale.arb').readAsStringSync();
      final keys = RegExp(r'^  "([^"]+)"\s*:', multiLine: true).allMatches(src).map((m) => m.group(1)!).toList();
      final seen = <String>{};
      final dups = [for (final k in keys) if (!seen.add(k)) k];
      expect(dups, isEmpty, reason: 'app_$locale.arb');
      expect(keys.length, _arb(locale).length, reason: 'app_$locale.arb: top-level keys must be indented by 2 spaces');
    }
  });

  for (final locale in _locales) {
    group(locale, () {
      final arb = _arb(locale);

      test('has every key, non-empty, with the same placeholders and valid ICU', () {
        final problems = <String>[];
        for (final k in enKeys) {
          final value = arb[k];
          if (value is! String) {
            problems.add('$k: missing');
            continue;
          }
          if (value.trim().isEmpty) {
            problems.add('$k: empty');
            continue;
          }
          try {
            final want = parseIcu(en[k] as String).placeholders;
            final got = parseIcu(value).placeholders;
            if (want.length != got.length || !want.containsAll(got)) {
              problems.add('$k: placeholders $got, English has $want');
            }
          } on IcuError catch (e) {
            problems.add('$k: $e');
          }
        }
        final extra = _messageKeys(arb).where((k) => !en.containsKey(k));
        problems.addAll(extra.map((k) => '$k: not in app_en.arb'));
        expect(problems, isEmpty);
      });

      test('no value is left in English', () {
        final problems = <String>[];
        for (final k in enKeys) {
          final value = arb[k];
          if (value is! String || _sameAsEnglishAllowed.contains(k)) continue;
          if (value == en[k]) {
            problems.add('$k: identical to English "$value"');
            continue;
          }
          try {
            final share = latinShare(parseIcu(value).literal);
            if (share > 0.5) problems.add('$k: mostly Latin letters "$value"');
          } on IcuError catch (_) {
            // Reported by the test above.
          }
        }
        expect(problems, isEmpty);
      });

      test('uses the right script variant', () {
        // Kurdish (Sorani) writes ک / ی; Arabic writes ك / ي and has no
        // ە ێ ۆ ڵ ڕ ڤ — a value with the other language's letters was pasted
        // into the wrong file. Language names are the exception.
        final wrong = locale == 'ckb' ? RegExp('[كي]') : RegExp('[ەێۆڵڕڤ]');
        final problems = [
          for (final k in enKeys)
            if (arb[k] is String && !_sameAsEnglishAllowed.contains(k) && wrong.hasMatch(arb[k] as String))
              '$k: "${arb[k]}"',
        ];
        expect(problems, isEmpty);
      });
    });
  }

  test('untranslated.txt is empty after flutter gen-l10n', () {
    final file = File('untranslated.txt');
    if (!file.existsSync()) return;
    expect(jsonDecode(file.readAsStringSync().trim().isEmpty ? '{}' : file.readAsStringSync()), isEmpty);
  });
}
