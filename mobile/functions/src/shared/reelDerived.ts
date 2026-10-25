/**
 * Derived reel fields (SRS §5.27, §6.4a): copied / computed from the reel's
 * product so the Reels feed is ONE query (`visible == true` + at most one
 * `filterKeys` array filter + `priceBand in`) and needs no product reads.
 * Written by the dashboard on save, kept current by `onReelWrite` and the reel
 * sync of `onProductWrite`; never by hand.
 *
 * Shared contract: `mobile/test/fixtures/product_query_keys.json` (`reelKeys`) —
 * the Dart `ReelKeys` / `ReelDerived` (lib/features/reels/data/reel_derived.dart)
 * and `ReelProduct.toMap` (lib/models/reel_model.dart) and this file are all
 * tested against it (`test/reelDerived.test.ts`). Change them together.
 */
import type { GiftAudience } from './enums';
import { boolean, integer, integerOrNull, string, stringList } from './firestoreParse';
import { giftAudiencesOf, priceBandOf } from './productDerived';

/** The derived fields, in the order they are documented in SRS §6.4a. */
export const REEL_DERIVED_FIELDS = [
  'storeId',
  'product',
  'categoryIds',
  'giftFor',
  'priceBand',
  'filterKeys',
  'visible',
] as const;
export type ReelDerivedField = (typeof REEL_DERIVED_FIELDS)[number];

/** `reels.product`: what the reel's product card shows (Dart `ReelProduct.toMap`). */
export interface ReelProductSnapshot {
  title: string;
  /** Only when the product has a non-empty Arabic / Kurdish title. */
  titleAr?: string;
  titleKu?: string;
  /** The product's first image; null without images. */
  image: string | null;
  price: number;
  compareAtPrice: number | null;
  isActive: boolean;
}

export interface DerivedReelFields {
  /** The product's store; '' without a product. */
  storeId: string;
  /** null when the product does not exist (any more). */
  product: ReelProductSnapshot | null;
  /** The product's categories (non-empty, de-duplicated). */
  categoryIds: string[];
  /** The product's gift types (`GiftAudience` values). */
  giftFor: GiftAudience[];
  /** `priceBandOf(product.price)`; 0 without a product. */
  priceBand: number;
  /** `cat:{c}`, `for:{a}` and every `cat:{c}|for:{a}` — category + gift type in one array filter. */
  filterKeys: string[];
  /** The reel's `isActive` and the product exists and is active: what the feed filters on. */
  visible: boolean;
}

// ── Filter keys (what the app filters with) ──────────────────────────────────

export function reelCategoryKey(categoryId: string): string {
  return `cat:${categoryId}`;
}

export function reelAudienceKey(audience: GiftAudience): string {
  return `for:${audience}`;
}

/** The `filterKeys array-contains` value for a Reels filter; null = no filter (Dart `ReelKeys.filterKey`). */
export function reelFilterKey(filter: { categoryId?: string | null; audience?: GiftAudience | null }): string | null {
  const { categoryId, audience } = filter;
  if (categoryId != null && audience != null) return `${reelCategoryKey(categoryId)}|${reelAudienceKey(audience)}`;
  if (categoryId != null) return reelCategoryKey(categoryId);
  if (audience != null) return reelAudienceKey(audience);
  return null;
}

/** Every key a reel of these categories / gift types answers to (Dart `ReelKeys.filterKeysOf`). */
export function reelFilterKeysOf(categoryIds: readonly string[], giftFor: readonly GiftAudience[]): string[] {
  return [
    ...categoryIds.map(reelCategoryKey),
    ...giftFor.map(reelAudienceKey),
    ...categoryIds.flatMap((c) => giftFor.map((a) => reelFilterKey({ categoryId: c, audience: a })!)),
  ];
}

// ── Derived fields ───────────────────────────────────────────────────────────

/** `reels.product` from a product document, read as tolerantly as `ProductModel.fromMap`. */
export function reelProductSnapshot(product: Readonly<Record<string, unknown>>): ReelProductSnapshot {
  const nonEmpty = (v: unknown) => (typeof v === 'string' && v.length > 0 ? v : null);
  const titleAr = nonEmpty(product.titleAr);
  const titleKu = nonEmpty(product.titleKu);
  return {
    title: nonEmpty(product.title) ?? '',
    ...(titleAr !== null && { titleAr }),
    ...(titleKu !== null && { titleKu }),
    image: stringList(product.images)[0] ?? null,
    price: integer(product.price),
    compareAtPrice: integerOrNull(product.compareAtPrice),
    isActive: boolean(product.isActive, true),
  };
}

/**
 * The derived fields of `reel` for its product document (`null` = the product
 * does not exist) — exactly what the Dart `ReelDerived.fieldsFor` writes.
 */
export function derivedReelFields(
  reel: Readonly<Record<string, unknown>>,
  product: Readonly<Record<string, unknown>> | null | undefined,
): DerivedReelFields {
  const isActive = boolean(reel.isActive, true);
  if (product == null) {
    return { storeId: '', product: null, categoryIds: [], giftFor: [], priceBand: 0, filterKeys: [], visible: false };
  }
  const snapshot = reelProductSnapshot(product);
  const categoryIds = [...new Set(stringList(product.categoryIds).filter((c) => c.length > 0))];
  const giftFor = giftAudiencesOf(product.giftFor);
  return {
    storeId: string(product.storeId),
    product: snapshot,
    categoryIds,
    giftFor,
    priceBand: priceBandOf(snapshot.price),
    filterKeys: reelFilterKeysOf(categoryIds, giftFor),
    visible: isActive && snapshot.isActive,
  };
}

/**
 * The derived fields whose stored value differs from `derived` (deep: map key
 * order does not matter, arrays are compared in order). Empty when up to date.
 */
export function staleReelFields(
  stored: Readonly<Record<string, unknown>>,
  derived: DerivedReelFields,
): Partial<DerivedReelFields> {
  const stale: Record<string, unknown> = {};
  for (const field of REEL_DERIVED_FIELDS) {
    if (!sameData(stored[field], derived[field])) stale[field] = derived[field];
  }
  return stale as Partial<DerivedReelFields>;
}

/** Deep equality of Firestore-like data (plain objects by keys, arrays in order). */
function sameData(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (Array.isArray(a) || Array.isArray(b)) {
    return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((x, i) => sameData(x, b[i]));
  }
  if (isPlainMap(a) && isPlainMap(b)) {
    const keys = Object.keys(a);
    return keys.length === Object.keys(b).length && keys.every((k) => k in b && sameData(a[k], b[k]));
  }
  return false;
}

function isPlainMap(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && Object.getPrototypeOf(v) === Object.prototype;
}
