import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/utils/search_tokenizer.dart';

/// The same fixture is checked by functions/test/searchTokenizer.test.ts, so
/// the app, the seeder and (later) the admin dashboard produce identical keywords.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/search_tokenizer_cases.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  group('tokenize', () {
    for (final c in (fixture['tokenize'] as List).cast<Map<String, dynamic>>()) {
      test('"${c['input']}"', () {
        expect(SearchTokenizer.tokenize(c['input'] as String), c['output']);
      });
    }
  });

  group('keywords', () {
    for (final c in (fixture['keywords'] as List).cast<Map<String, dynamic>>()) {
      test('${c['input']}', () {
        expect(SearchTokenizer.keywords((c['input'] as List).cast<String>()), c['output']);
      });
    }
  });
}
