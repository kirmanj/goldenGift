/**
 * Maintenance (SRS §5.8a, §6.4, §12 item 14): products saved before Phase 11 have
 * no `giftFor`, so no gift-type filter (`forKeys`) finds them. This gives every
 * product whose `giftFor` is missing or holds no known `GiftAudience` value:
 *  - a seed product (scripts/seed-data/products.ts): its seed gift types;
 *  - any other product: For him + For her (`men`, `women` — PROVISIONAL, §12).
 * In the same write it sets every stale derived field (`staleDerivedFields`), so
 * `forKeys` is right at once — even before `onProductWrite` runs (which then
 * finds nothing to rewrite, but re-syncs the product's reels and search record).
 *
 * Idempotent: a product with a known gift type is never touched again, so the
 * script can be re-run at any time. Only `giftFor` and the derived fields are
 * written — not `updatedAt` (a maintenance fix is not an edit). Each write is
 * conditional on the document being unchanged since it was read, so a product
 * edited meanwhile is never overwritten (the batch fails; run it again).
 */
import { FieldPath, type Firestore, type QueryDocumentSnapshot, type QuerySnapshot } from 'firebase-admin/firestore';
import type { GiftAudience } from '../../src/shared/enums';
import { FirestorePaths } from '../../src/shared/paths';
import { DERIVED_PRODUCT_FIELDS, giftAudiencesOf, staleDerivedFields } from '../../src/shared/productDerived';
import { PRODUCTS } from '../seed-data/products';

/** Products read per page (only the fields the derived values need are fetched). */
export const BACKFILL_PAGE_SIZE = 300;
/** Writes per batch (Firestore allows 500). */
export const BACKFILL_BATCH_SIZE = 400;

/** What a product saved before Phase 11 is a gift for (SRS §5.8a, §12 item 14). */
export const DEFAULT_GIFT_FOR: readonly GiftAudience[] = ['men', 'women'];

/** Every field `staleDerivedFields` reads: the sources and the stored derived values. */
const READ_FIELDS = [
  'giftFor',
  'price',
  'compareAtPrice',
  'availableCities',
  'categoryIds',
  'title',
  'titleAr',
  'titleKu',
  'tags',
  ...DERIVED_PRODUCT_FIELDS,
];

const SEED_GIFT_FOR = new Map(PRODUCTS.map((p) => [p.id, p.giftFor]));

export interface GiftForBackfillResult {
  scanned: number;
  /** Products that got (or, with `dryRun`, would get) `giftFor`. */
  updated: number;
  /** Of those, seed products given their own seed gift types. */
  fromSeed: number;
  /** Products that already had a known gift type. */
  alreadySet: number;
  /** The first 20 updated product ids (for the console). */
  sample: string[];
}

/**
 * The `giftFor` to write for a product, or null when it already has a known
 * gift type (nothing to do).
 */
export function backfillGiftForOf(productId: string, giftFor: unknown): GiftAudience[] | null {
  if (giftAudiencesOf(giftFor).length > 0) return null;
  return [...(SEED_GIFT_FOR.get(productId) ?? DEFAULT_GIFT_FOR)];
}

export async function backfillGiftFor(
  db: Firestore,
  options: { dryRun?: boolean; pageSize?: number; onPage?: (scanned: number, updated: number) => void } = {},
): Promise<GiftForBackfillResult> {
  const pageSize = options.pageSize ?? BACKFILL_PAGE_SIZE;
  const result: GiftForBackfillResult = { scanned: 0, updated: 0, fromSeed: 0, alreadySet: 0, sample: [] };
  const base = db
    .collection(FirestorePaths.products)
    .orderBy(FieldPath.documentId())
    .select(...READ_FIELDS)
    .limit(pageSize);
  let last: QueryDocumentSnapshot | null = null;

  for (;;) {
    const page: QuerySnapshot = await (last === null ? base : base.startAfter(last)).get();
    if (page.empty) break;
    let batch = db.batch();
    let pending = 0;
    for (const doc of page.docs) {
      result.scanned++;
      const giftFor = backfillGiftForOf(doc.id, doc.get('giftFor'));
      if (giftFor === null) {
        result.alreadySet++;
        continue;
      }
      result.updated++;
      if (SEED_GIFT_FOR.has(doc.id)) result.fromSeed++;
      if (result.sample.length < 20) result.sample.push(doc.id);
      if (options.dryRun) continue;
      const stale = staleDerivedFields({ ...doc.data(), giftFor });
      batch.update(doc.ref, { giftFor, ...stale }, { lastUpdateTime: doc.updateTime });
      if (++pending >= BACKFILL_BATCH_SIZE) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
    options.onPage?.(result.scanned, result.updated);
    if (page.size < pageSize) break;
    last = page.docs[page.docs.length - 1];
  }
  return result;
}
