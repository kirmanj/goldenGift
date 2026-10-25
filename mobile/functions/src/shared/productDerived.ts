/**
 * Derived product query fields (SRS §5.8, §5.8a, §6.4): written by
 * `onProductWrite`, the seeder and the dashboard, never by hand; the app's
 * product queries filter on them so every filter combination is ONE Firestore
 * query with at most one array filter.
 *
 * Shared contract: `mobile/test/fixtures/product_query_keys.json` — the Dart
 * `PriceBands` / `ProductKeys` (lib/features/products/data/product_query.dart),
 * `ProductDerived` (lib/features/products/data/product_derived.dart) and this
 * file are all tested against it (`test/productDerived.test.ts`).
 * Change them together.
 */
import { GiftAudience } from './enums';
import { integer, integerOrNull, string, stringList } from './firestoreParse';
import { keywords } from './searchTokenizer';

/**
 * Lower bounds of price bands 1–4 in IQD; band 0 is everything below the first.
 * The §5.8 filter bands: under 25,000 · 25,000–50,000 · 50,000–100,000 ·
 * 100,000–200,000 · 200,000+.
 */
export const PRICE_BAND_BOUNDS = [25000, 50000, 100000, 200000] as const;
export const PRICE_BAND_COUNT = PRICE_BAND_BOUNDS.length + 1;

/** `cityKeys` value for a product deliverable to every served city. */
export const ALL_CITIES = 'all';

/** The derived fields, in the order they are documented in SRS §6.4. */
export const DERIVED_PRODUCT_FIELDS = [
  'hasDiscount',
  'priceBand',
  'cityKeys',
  'catCityKeys',
  'forKeys',
  'searchKeywords',
] as const;
export type DerivedProductField = (typeof DERIVED_PRODUCT_FIELDS)[number];

export interface DerivedProductFields {
  /** `compareAtPrice > price`. */
  hasDiscount: boolean;
  /** 0–4, see `PRICE_BAND_BOUNDS`. */
  priceBand: number;
  /** `availableCities`, or `['all']` when unrestricted. */
  cityKeys: string[];
  /** Every `{categoryId}|{cityKey}` pair, so category + city is one array filter. */
  catCityKeys: string[];
  /**
   * Gift type alone, × category, × city key and × category × city key (SRS §5.8a),
   * so gift type + category + city is one array filter. Empty without `giftFor`.
   */
  forKeys: string[];
  /** Tokens of the three titles + tags (`SearchTokenizer.keywords`). */
  searchKeywords: string[];
}

/** Band of a whole-IQD price: the number of bounds it reaches. */
export function priceBandOf(price: number): number {
  let band = 0;
  while (band < PRICE_BAND_BOUNDS.length && price >= PRICE_BAND_BOUNDS[band]) band++;
  return band;
}

/**
 * The derived fields of a product document (any shape the app, dashboard or
 * seeder writes — read as tolerantly as `ProductModel.fromMap`).
 */
export function derivedProductFields(product: Readonly<Record<string, unknown>>): DerivedProductFields {
  const price = integer(product.price);
  const compareAtPrice = integerOrNull(product.compareAtPrice);
  const cityKeys = unique(stringList(product.availableCities));
  if (cityKeys.length === 0) cityKeys.push(ALL_CITIES);
  const categoryIds = unique(stringList(product.categoryIds));
  return {
    hasDiscount: compareAtPrice !== null && compareAtPrice > price,
    priceBand: priceBandOf(price),
    cityKeys,
    catCityKeys: categoryIds.flatMap((c) => cityKeys.map((city) => catCityKey(c, city))),
    // Same order as the Dart `ProductDerived.fieldsFor`: per audience, alone, × category, × city, × both.
    forKeys: giftAudiencesOf(product.giftFor).flatMap((a) => [
      forKey(a),
      ...categoryIds.map((c) => forKey(a, { categoryId: c })),
      ...cityKeys.map((city) => forKey(a, { cityKey: city })),
      ...categoryIds.flatMap((c) => cityKeys.map((city) => forKey(a, { categoryId: c, cityKey: city }))),
    ]),
    searchKeywords: keywords([
      string(product.title),
      string(product.titleAr),
      string(product.titleKu),
      ...stringList(product.tags),
    ]),
  };
}

/**
 * The derived fields whose stored value differs from `derived` (arrays compared
 * element by element, in order). Empty when the document is up to date.
 */
export function staleDerivedFields(
  stored: Readonly<Record<string, unknown>>,
  derived: DerivedProductFields = derivedProductFields(stored),
): Partial<DerivedProductFields> {
  const stale: Record<string, unknown> = {};
  for (const field of DERIVED_PRODUCT_FIELDS) {
    if (!sameValue(stored[field], derived[field])) stale[field] = derived[field];
  }
  return stale as Partial<DerivedProductFields>;
}

// ── Query keys (what the app filters with) ───────────────────────────────────

export function catCityKey(categoryId: string, cityKey: string): string {
  return `${categoryId}|${cityKey}`;
}

/** `cityKeys array-contains-any` values for "deliverable to `cityId`". */
export function cityAnyOf(cityId: string): string[] {
  return [cityId, ALL_CITIES];
}

/** `catCityKeys array-contains-any` values for "in `categoryId`, deliverable to `cityId`". */
export function catCityAnyOf(categoryId: string, cityId: string): string[] {
  return cityAnyOf(cityId).map((city) => catCityKey(categoryId, city));
}

/**
 * One `forKeys` entry (Dart `ProductKeys.forKey`): `{audience}`, optionally
 * narrowed to a category (`|cat:{id}`) and / or a city key (`|city:{id or all}`).
 */
export function forKey(audience: GiftAudience, narrow: { categoryId?: string; cityKey?: string } = {}): string {
  return [
    audience,
    ...(narrow.categoryId !== undefined ? [`cat:${narrow.categoryId}`] : []),
    ...(narrow.cityKey !== undefined ? [`city:${narrow.cityKey}`] : []),
  ].join('|');
}

/**
 * `forKeys array-contains(-any)` values for "a gift for `audience`", optionally
 * in `categoryId` and deliverable to `cityId` (Dart `ProductKeys.forAnyOf`).
 */
export function forAnyOf(audience: GiftAudience, filter: { categoryId?: string; cityId?: string } = {}): string[] {
  const { categoryId, cityId } = filter;
  return cityId === undefined
    ? [forKey(audience, { categoryId })]
    : cityAnyOf(cityId).map((city) => forKey(audience, { categoryId, cityKey: city }));
}

// ── Gift types ───────────────────────────────────────────────────────────────

/**
 * `giftFor` as `ProductModel.fromMap` reads it (Dart `giftAudiencesOf`): the
 * known `GiftAudience` values, de-duplicated, in first-seen order.
 */
export function giftAudiencesOf(value: unknown): GiftAudience[] {
  const known = stringList(value).filter((v): v is GiftAudience => (GiftAudience as readonly string[]).includes(v));
  return [...new Set(known)];
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/** De-duplicated, first-seen order, empty strings dropped. */
function unique(values: string[]): string[] {
  return [...new Set(values.filter((v) => v.length > 0))];
}

function sameValue(a: unknown, b: unknown): boolean {
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((x, i) => x === b[i]);
  }
  return a === b;
}
