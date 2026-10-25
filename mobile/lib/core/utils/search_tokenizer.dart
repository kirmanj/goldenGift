/// Builds `products.searchKeywords` and tokenizes search queries (SRS §5.8).
///
/// MUST stay identical to `functions/src/shared/searchTokenizer.ts` (used by
/// the seeder, and later by the admin dashboard and functions): both are
/// checked against `test/fixtures/search_tokenizer_cases.json`.
///
/// Rules: lower-case; strip Arabic diacritics and tatweel; unify letter
/// variants people type interchangeably on Arabic vs Kurdish keyboards
/// (أ إ آ ٱ → ا, ك → ک, ي ى → ی); split on anything that is not a letter or
/// digit; keep tokens of 2+ characters; de-duplicate, keeping first-seen order.
class SearchTokenizer {
  SearchTokenizer._();

  static final _diacritics = RegExp('[ً-ٰٟـ]');
  static final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static const _letterMap = {
    'أ': 'ا', // أ → ا
    'إ': 'ا', // إ → ا
    'آ': 'ا', // آ → ا
    'ٱ': 'ا', // ٱ → ا
    'ك': 'ک', // ك → ک
    'ي': 'ی', // ي → ی
    'ى': 'ی', // ى → ی
  };

  static String normalize(String input) {
    final lower = input.toLowerCase().replaceAll(_diacritics, '');
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_letterMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// Tokens of one string, in order of first appearance.
  static List<String> tokenize(String input) {
    final seen = <String>{};
    for (final token in normalize(input).split(_separators)) {
      if (token.runes.length >= 2) seen.add(token);
    }
    return seen.toList();
  }

  /// Keywords for a product: tokens of every title variant plus tags.
  static List<String> keywords(Iterable<String> texts) {
    final seen = <String>{};
    for (final text in texts) {
      seen.addAll(tokenize(text));
    }
    return seen.toList();
  }
}
