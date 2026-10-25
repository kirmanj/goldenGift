/**
 * `onReviewWrite` (SRS §5.26, §7): every write of `products/{pid}/reviews/{id}`
 * that can change what is shown — the review appeared / disappeared, or its
 * `isApproved`, `rating` or `storeId` changed while approved — recomputes
 *  - `products/{pid}.ratingAvg` / `ratingCount` from that product's APPROVED
 *    reviews (aggregate count + average of `rating`), and
 *  - `stores/{storeId}.ratingAvg` / `ratingCount` from all approved reviews of
 *    the store (collection-group `reviews` where `storeId == X` and
 *    `isApproved == true`) — for the old and the new store when it changed.
 *
 * Recomputing from the source (instead of adding deltas) makes it idempotent:
 * a retried or replayed event writes the same numbers again, and a write is
 * skipped when the stored values already match. Pending (unapproved) reviews
 * never count.
 *
 * Writing `ratingAvg` / `ratingCount` on the product triggers onProductWrite,
 * whose derived fields do not depend on them (it writes nothing back).
 */
import {
  AggregateField,
  FieldValue,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type Query,
} from 'firebase-admin/firestore';
import { decimal, integer, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';

export interface ReviewWriteEvent {
  productId: string;
  reviewId: string;
  before: DocumentData | undefined;
  after: DocumentData | undefined;
}

export interface RatingAggregate {
  ratingAvg: number;
  ratingCount: number;
}

export type ReviewWriteResult =
  | { recomputed: false }
  | { recomputed: true; product: RatingAggregate; stores: Record<string, RatingAggregate> };

/** What one review contributes to the aggregates (null = nothing). */
function contribution(review: DocumentData | undefined): { rating: number; storeId: string | null } | null {
  if (review === undefined || review.isApproved !== true) return null;
  return { rating: integer(review.rating), storeId: stringOrNull(review.storeId) };
}

/** Whether the write can change any aggregate (pure). */
export function affectsAggregates(before: DocumentData | undefined, after: DocumentData | undefined): boolean {
  const a = contribution(before);
  const b = contribution(after);
  if (a === null && b === null) return false;
  if (a === null || b === null) return true;
  return a.rating !== b.rating || a.storeId !== b.storeId;
}

/** Average rounded to 2 decimals (what the app shows with one decimal). */
export function roundAverage(avg: number | null | undefined): number {
  if (typeof avg !== 'number' || !Number.isFinite(avg)) return 0;
  return Math.round(avg * 100) / 100;
}

async function aggregate(query: Query): Promise<RatingAggregate> {
  const snap = await query
    .aggregate({ count: AggregateField.count(), avg: AggregateField.average('rating') })
    .get();
  const count = snap.data().count;
  return { ratingCount: count, ratingAvg: count === 0 ? 0 : roundAverage(snap.data().avg) };
}

export function productRatingQuery(db: Firestore, productId: string): Query {
  return db.collection(P.products).doc(productId).collection(P.reviews).where('isApproved', '==', true);
}

export function storeRatingQuery(db: Firestore, storeId: string): Query {
  return db.collectionGroup(P.reviews).where('storeId', '==', storeId).where('isApproved', '==', true);
}

/** Writes `ratingAvg` / `ratingCount` when they differ; a missing document is left alone. */
async function store(db: Firestore, ref: DocumentReference, value: RatingAggregate): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    if (integer(snap.get('ratingCount')) === value.ratingCount && decimal(snap.get('ratingAvg')) === value.ratingAvg) {
      return false;
    }
    tx.update(ref, { ...value, updatedAt: FieldValue.serverTimestamp() });
    return true;
  });
}

export async function handleReviewWrite(db: Firestore, event: ReviewWriteEvent): Promise<ReviewWriteResult> {
  if (!affectsAggregates(event.before, event.after)) return { recomputed: false };

  const product = await aggregate(productRatingQuery(db, event.productId));
  await store(db, db.collection(P.products).doc(event.productId), product);

  const storeIds = new Set(
    [stringOrNull(event.before?.storeId), stringOrNull(event.after?.storeId)].filter(
      (id): id is string => id !== null && !id.includes('/'),
    ),
  );
  const stores: Record<string, RatingAggregate> = {};
  for (const storeId of storeIds) {
    const value = await aggregate(storeRatingQuery(db, storeId));
    await store(db, db.collection(P.stores).doc(storeId), value);
    stores[storeId] = value;
  }
  return { recomputed: true, product, stores };
}
