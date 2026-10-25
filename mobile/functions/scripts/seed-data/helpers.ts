/** Shared helpers and types for the dev data seeder. */

/** The only project the seeder will ever write to (emulator or real). */
export const PROJECT_ID = 'goldengift-iq';

/** The in-house store every demo product belongs to. */
export const HOME_STORE_ID = 'golden-gift-home';

/**
 * Trilingual catalogue text (SRS §4.2): English, Arabic, Kurdish Sorani (Arabic script).
 * Kurdish strings need a native-speaker review before launch (SRS §8, Localization).
 */
export interface Tri {
  en: string;
  ar: string;
  ku: string;
}

export type FirestoreData = Record<string, unknown>;

/** A document the seeder writes with `set()` (full overwrite). */
export interface SeedDoc {
  collection: string;
  id: string;
  data: FirestoreData;
}

/**
 * Trilingual field as three siblings, matching `LocalizedText.toMap(field)` in
 * mobile/lib/models/localized_text.dart: `{title, titleAr, titleKu}`.
 */
export function loc(field: string, text: Tri): Record<string, string> {
  return { [field]: text.en, [`${field}Ar`]: text.ar, [`${field}Ku`]: text.ku };
}

/** Same text in every language (sizes, model names, numbers). */
export function same(text: string): Tri {
  return { en: text, ar: text, ku: text };
}
