/**
 * Maintenance (SRS §5.26, §6.7): orders placed before Phase 9 have no
 * `productIds`, and the review rules only accept a review for a product listed
 * there ("the customer bought it"). This sets `productIds` — the distinct
 * `productId`s of the order's lines, in line order, exactly what `placeOrder`
 * writes — on every order that lacks the field.
 *
 * Idempotent: an order that has `productIds` (even `[]`, e.g. a gift-card or
 * special-request order whose line is not a catalogue product) is never touched
 * again, so the script can be re-run at any time. Only `productIds` is written —
 * not `updatedAt` (a maintenance fix is not an edit) and never `status`, so
 * `onOrderStatusChange` ignores the update.
 */
import { FieldPath, type Firestore, type QueryDocumentSnapshot, type QuerySnapshot } from 'firebase-admin/firestore';
import { mapList, string } from '../../src/shared/firestoreParse';
import { FirestorePaths } from '../../src/shared/paths';

/** Orders read per page (only `items` / `productIds` are fetched). */
export const BACKFILL_PAGE_SIZE = 300;
/** Writes per batch (Firestore allows 500). */
export const BACKFILL_BATCH_SIZE = 400;

export interface BackfillResult {
  scanned: number;
  /** Orders that got (or, with `dryRun`, would get) `productIds`. */
  updated: number;
  /** Orders that already had it. */
  alreadySet: number;
  /** The first 20 updated order ids (for the console). */
  sample: string[];
}

/** The `productIds` of an order's lines (what placeOrder writes): distinct, in line order, catalogue ids only. */
export function productIdsOf(items: unknown): string[] {
  const ids = mapList(items)
    .map((line) => string(line.productId))
    .filter((id) => id.length > 0 && id.length <= 1500 && !id.includes('/'));
  return [...new Set(ids)];
}

export async function backfillOrderProductIds(
  db: Firestore,
  options: { dryRun?: boolean; pageSize?: number; onPage?: (scanned: number, updated: number) => void } = {},
): Promise<BackfillResult> {
  const pageSize = options.pageSize ?? BACKFILL_PAGE_SIZE;
  const result: BackfillResult = { scanned: 0, updated: 0, alreadySet: 0, sample: [] };
  const base = db.collection(FirestorePaths.orders).orderBy(FieldPath.documentId()).select('items', 'productIds').limit(pageSize);
  let last: QueryDocumentSnapshot | null = null;

  for (;;) {
    const page: QuerySnapshot = await (last === null ? base : base.startAfter(last)).get();
    if (page.empty) break;
    let batch = db.batch();
    let pending = 0;
    for (const doc of page.docs) {
      result.scanned++;
      if (Array.isArray(doc.get('productIds'))) {
        result.alreadySet++;
        continue;
      }
      result.updated++;
      if (result.sample.length < 20) result.sample.push(doc.id);
      if (options.dryRun) continue;
      batch.update(doc.ref, { productIds: productIdsOf(doc.get('items')) });
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
