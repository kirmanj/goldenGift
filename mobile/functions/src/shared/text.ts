/**
 * User-visible text length, counted the way Flutter's `TextField.maxLength`
 * counts it (grapheme clusters: an emoji with skin tone or a letter with
 * combining marks is one), so a server limit is never stricter than the input
 * field that enforced it.
 */
const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

export function graphemeLength(value: string): number {
  return Array.from(segmenter.segment(value)).length;
}

/** Number of Unicode code points (Dart `String.runes.length`). */
export function codePointLength(value: string): number {
  return Array.from(value).length;
}
