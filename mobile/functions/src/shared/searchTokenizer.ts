/**
 * Builds `products.searchKeywords` and tokenizes search queries (SRS §5.8).
 *
 * Exact port of `mobile/lib/core/utils/search_tokenizer.dart` — both are checked
 * against `mobile/test/fixtures/search_tokenizer_cases.json`
 * (`test/searchTokenizer.test.ts`). Change both together.
 *
 * Rules: lower-case; strip Arabic diacritics and tatweel; unify letter variants
 * people type interchangeably on Arabic vs Kurdish keyboards
 * (أ إ آ ٱ → ا, ك → ک, ي ى → ی); split on anything that is not a letter or digit;
 * keep tokens of 2+ characters (code points); de-duplicate, keeping first-seen order.
 */

/** Harakat U+064B–U+065F, superscript alef U+0670, tatweel U+0640. */
const DIACRITICS = /[ً-ٰٟـ]/g;
const SEPARATORS = /[^\p{L}\p{N}]+/u;

const LETTER_MAP: Readonly<Record<string, string>> = {
  'أ': 'ا', // أ → ا
  'إ': 'ا', // إ → ا
  'آ': 'ا', // آ → ا
  'ٱ': 'ا', // ٱ → ا
  'ك': 'ک', // ك → ک
  'ي': 'ی', // ي → ی
  'ى': 'ی', // ى → ی
};

export function normalize(input: string): string {
  const lower = input.toLowerCase().replace(DIACRITICS, '');
  let out = '';
  for (const ch of lower) out += LETTER_MAP[ch] ?? ch;
  return out;
}

/** Tokens of one string, in order of first appearance. */
export function tokenize(input: string): string[] {
  const seen = new Set<string>();
  for (const token of normalize(input).split(SEPARATORS)) {
    if ([...token].length >= 2) seen.add(token);
  }
  return [...seen];
}

/** Keywords for a product: tokens of every title variant plus tags. */
export function keywords(texts: Iterable<string>): string[] {
  const seen = new Set<string>();
  for (const text of texts) {
    for (const token of tokenize(text)) seen.add(token);
  }
  return [...seen];
}

export const SearchTokenizer = { normalize, tokenize, keywords } as const;
