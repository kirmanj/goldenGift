/**
 * `onReelWrite` (SRS §5.27, §6.4a, §7) and the reel sync of `onProductWrite`:
 * keep the fields a reel copies from its product (`storeId`, `product`,
 * `categoryIds`, `giftFor`, `priceBand`, `filterKeys`, `visible`) in step.
 *
 *  - An existing reel: re-reads the CURRENT reel and its product in a
 *    transaction and updates only the derived fields that differ — never
 *    `updatedAt`, so the editor's time stays meaningful. That write fires the
 *    trigger again; the second run finds nothing stale and writes nothing, so
 *    there is no loop. Reading the current documents (not the event's snapshot)
 *    means a late or retried event never writes old values back.
 *  - A deleted reel: its Storage files `reels/{id}.mp4` / `reels/{id}.jpg` are
 *    deleted (already gone, or no default bucket: not an error).
 *  - A product change that a reel shows or filters on (`syncReelsOfProduct`):
 *    every reel with that `productId` gets its stale derived fields, in
 *    transactions of at most `REEL_SYNC_PAGE_SIZE` reels — a deleted or
 *    deactivated product hides its reels (`visible: false`).
 *
 * Idempotent: any run can repeat (retries) and converges to the same state.
 * Throws when Firestore or Storage fails, so the trigger is retried.
 */
import { FieldPath, type DocumentData, type Firestore, type QueryDocumentSnapshot } from 'firebase-admin/firestore';
import type { Storage } from 'firebase-admin/storage';
import { stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { derivedReelFields, staleReelFields } from '../shared/reelDerived';

type Bucket = ReturnType<Storage['bucket']>;

export interface ReelSyncDeps {
  db: Firestore;
  /** The default Storage bucket. May throw when the project has none configured. */
  bucket: () => Bucket;
}

export interface ReelSyncResult {
  /** Derived fields written back to the reel (empty when up to date, or the reel is gone). */
  derivedWritten: string[];
  /** Storage objects removed after the reel was deleted; null when there is no bucket. */
  filesDeleted: string[] | null;
}

/** Reels re-derived per transaction by `syncReelsOfProduct` (a transaction allows 500 writes). */
export const REEL_SYNC_PAGE_SIZE = 400;

/** `reels/{id}.mp4` and `reels/{id}.jpg` (SRS §6.16). */
export function reelStoragePaths(reelId: string): string[] {
  return [`${P.reels}/${reelId}.mp4`, `${P.reels}/${reelId}.jpg`];
}

/** `onReelWrite`: `after` undefined = the reel was deleted. */
export async function syncReel(
  deps: ReelSyncDeps,
  reelId: string,
  after: DocumentData | undefined,
): Promise<ReelSyncResult> {
  if (after === undefined) return { derivedWritten: [], filesDeleted: await deleteReelFiles(deps.bucket, reelId) };

  const { db } = deps;
  const ref = db.collection(P.reels).doc(reelId);
  const derivedWritten = await db.runTransaction(async (tx) => {
    const reel = (await tx.get(ref)).data();
    if (reel === undefined) return []; // deleted since: its delete event cleans up
    const productId = reelProductId(reel);
    const product =
      productId === null ? null : ((await tx.get(db.collection(P.products).doc(productId))).data() ?? null);
    const stale = staleReelFields(reel, derivedReelFields(reel, product));
    const written = Object.keys(stale);
    if (written.length > 0) tx.update(ref, stale);
    return written;
  });
  return { derivedWritten, filesDeleted: [] };
}

/**
 * Whether a product write changes anything a reel of it shows or filters on:
 * titles, first image, price, compare-at price, categories, gift types,
 * `isActive`, `storeId` — or the product appeared / was deleted. Pure.
 */
export function reelSourceChanged(before: DocumentData | undefined, after: DocumentData | undefined): boolean {
  return reelSourceKey(before) !== reelSourceKey(after);
}

function reelSourceKey(product: DocumentData | undefined): string | null {
  // The reel's own `isActive` does not depend on the product: any constant works.
  return product === undefined ? null : JSON.stringify(derivedReelFields({ isActive: true }, product));
}

/**
 * Re-derives every reel of `products/{productId}` from the CURRENT product
 * (missing = deleted → hidden); writes only stale fields. Returns how many reels
 * were written. Each page is one transaction that reads the product and the
 * reels, so a concurrent product edit retries it instead of being overwritten.
 */
export async function syncReelsOfProduct(
  db: Firestore,
  productId: string,
  pageSize = REEL_SYNC_PAGE_SIZE,
): Promise<number> {
  const productRef = db.collection(P.products).doc(productId);
  const reels = db
    .collection(P.reels)
    .where('productId', '==', productId)
    .orderBy(FieldPath.documentId())
    .limit(pageSize);
  let updated = 0;
  let last: QueryDocumentSnapshot | null = null;
  for (;;) {
    const page = await db.runTransaction(async (tx) => {
      const product = (await tx.get(productRef)).data() ?? null;
      const snap = await tx.get(last === null ? reels : reels.startAfter(last));
      let written = 0;
      for (const doc of snap.docs) {
        const stale = staleReelFields(doc.data(), derivedReelFields(doc.data(), product));
        if (Object.keys(stale).length === 0) continue;
        tx.update(doc.ref, stale);
        written++;
      }
      return { docs: snap.docs, written };
    });
    updated += page.written;
    if (page.docs.length < pageSize) return updated;
    last = page.docs[page.docs.length - 1];
  }
}

/** The reel's `productId` when it can name a document; null otherwise (shown as "product unavailable"). */
function reelProductId(reel: DocumentData): string | null {
  const id = stringOrNull(reel.productId);
  return id !== null && id.length <= 1500 && !id.includes('/') && id !== '.' && id !== '..' ? id : null;
}

/**
 * Deletes the reel's video and poster from the default bucket. Files that are
 * already gone, or a project without a bucket, are not errors.
 */
async function deleteReelFiles(bucket: () => Bucket, reelId: string): Promise<string[] | null> {
  try {
    const b = bucket();
    const paths = reelStoragePaths(reelId);
    await Promise.all(paths.map((path) => b.file(path).delete({ ignoreNotFound: true })));
    return paths;
  } catch (e) {
    if (isMissingBucket(e)) return null;
    throw e;
  }
}

function isMissingBucket(e: unknown): boolean {
  const code = typeof e === 'object' && e !== null && 'code' in e ? (e as { code: unknown }).code : undefined;
  if (code === 404 || code === '404' || code === 'storage/invalid-argument') return true;
  const message = e instanceof Error ? e.message : String(e);
  return /bucket (name not specified|does not exist|not found)|no such bucket/i.test(message);
}
