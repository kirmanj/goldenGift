import type { DocumentData, Firestore } from 'firebase-admin/firestore';
import { reelSourceChanged, syncReelsOfProduct } from '../reels/onReelWrite';
import { staleDerivedFields } from '../shared/productDerived';
import { FirestorePaths } from '../shared/paths';
import type { AlgoliaIndex } from '../search/algolia';
import { buildProductRecord, isIndexable } from '../search/productRecord';

export type AlgoliaOutcome =
  | 'saved' // record upserted
  | 'deleted' // product deleted or inactive → record removed
  | 'unchanged' // nothing the record shows changed (e.g. a viewCount bump, or our own write-back)
  | 'notConfigured'; // no Algolia credentials yet: nothing sent

export interface ProductSyncResult {
  /** Derived fields written back to the product (empty when already up to date or deleted). */
  derivedWritten: string[];
  /** Reels of the product whose derived fields were rewritten (0 when nothing a reel shows changed). */
  reelsUpdated: number;
  algolia: AlgoliaOutcome;
}

/**
 * `onProductWrite` (SRS §6.4, §6.4a, §7): keeps the derived query fields, the
 * reels of the product and the Algolia record of `products/{id}` in step with
 * the document.
 *
 *  1. When the derived fields of `after` are stale, re-reads the CURRENT document
 *     in a transaction and updates only the fields that differ — never
 *     `updatedAt`, so the admin's edit time stays meaningful. That write fires
 *     the trigger again; the second run finds nothing stale and writes nothing,
 *     so there is no loop. Reading the current document (not the event's
 *     snapshot) means a late or retried event never writes old values back.
 *  2. When the event changes anything a reel shows or filters on (titles, first
 *     image, prices, categories, gift types, `isActive`, `storeId`, or the
 *     product appeared / was deleted): every reel with this `productId` gets its
 *     stale derived fields from the CURRENT product (`syncReelsOfProduct`; a
 *     deleted product hides them). The write-back run of step 1 changes none of
 *     these, so it queries no reels.
 *  3. With Algolia configured (`algolia` not null), and when the record built
 *     from `before` differs from the one built from `after`: reads the current
 *     document and upserts its record, or deletes the record when the product
 *     is gone or `isActive == false`. Records recompute the derived fields, so
 *     the write-back run of step 1 is `unchanged` and costs no Algolia call.
 *
 * Idempotent: any run can repeat (retries) and converges to the same state.
 * Throws when Firestore or Algolia fails, so the trigger is retried; the reels
 * are synced before Algolia is called, so an Algolia outage never holds them.
 */
export async function syncProduct(
  db: Firestore,
  id: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
  algolia: AlgoliaIndex | null,
): Promise<ProductSyncResult> {
  const ref = db.collection(FirestorePaths.products).doc(id);
  let current: DocumentData | null | undefined; // undefined = not read yet

  let derivedWritten: string[] = [];
  if (after !== undefined && Object.keys(staleDerivedFields(after)).length > 0) {
    const outcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.data();
      if (data === undefined) return { data: null, written: [] as string[] };
      const stale = staleDerivedFields(data);
      const written = Object.keys(stale);
      if (written.length > 0) tx.update(ref, stale);
      return { data: { ...data, ...stale }, written };
    });
    current = outcome.data;
    derivedWritten = outcome.written;
  }

  const reelsUpdated = reelSourceChanged(before, after) ? await syncReelsOfProduct(db, id) : 0;

  if (algolia === null) return { derivedWritten, reelsUpdated, algolia: 'notConfigured' };
  if (!searchRecordChanged(id, before, after)) return { derivedWritten, reelsUpdated, algolia: 'unchanged' };

  if (current === undefined) current = (await ref.get()).data() ?? null;
  if (isIndexable(current)) {
    await algolia.saveObject(buildProductRecord(id, current));
    return { derivedWritten, reelsUpdated, algolia: 'saved' };
  }
  await algolia.deleteObject(id);
  return { derivedWritten, reelsUpdated, algolia: 'deleted' };
}

/**
 * Whether the event changes what the search index holds for the product: its
 * record (or its absence, for a deleted / inactive product) before vs after.
 */
export function searchRecordChanged(
  id: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): boolean {
  return recordKey(id, before) !== recordKey(id, after);
}

function recordKey(id: string, product: DocumentData | undefined): string | null {
  return isIndexable(product) ? JSON.stringify(buildProductRecord(id, product)) : null;
}
