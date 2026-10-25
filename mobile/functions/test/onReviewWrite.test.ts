/**
 * onReviewWrite (SRS §5.26): product and store rating aggregates from APPROVED
 * reviews only. Pure change detection, then the aggregation against the Firestore
 * emulator (own demo- project; skipped without it).
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { affectsAggregates, handleReviewWrite, roundAverage } from '../src/reviews/onReviewWrite';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';

const review = (over: DocumentData = {}): DocumentData => ({
  productId: 'p1',
  userId: 'alice',
  userName: 'Alice',
  storeId: 'store-a',
  rating: 4,
  text: 'Lovely',
  images: [],
  orderId: 'o1',
  isApproved: false,
  createdAt: Timestamp.now(),
  ...over,
});

describe('affectsAggregates (pure)', () => {
  test('only approved reviews matter', () => {
    assert.equal(affectsAggregates(undefined, review()), false); // new pending review
    assert.equal(affectsAggregates(review(), review({ text: 'Edited' })), false);
    assert.equal(affectsAggregates(review(), review({ isApproved: true })), true); // approved
    assert.equal(affectsAggregates(review({ isApproved: true }), review()), true); // hidden
    assert.equal(affectsAggregates(review({ isApproved: true }), undefined), true); // approved one deleted
    assert.equal(affectsAggregates(undefined, review({ isApproved: true })), true); // created approved (admin SDK)
    assert.equal(affectsAggregates(review({ isApproved: true }), review({ isApproved: true, rating: 2 })), true);
    assert.equal(affectsAggregates(review({ isApproved: true }), review({ isApproved: true, storeId: 'store-b' })), true);
    assert.equal(affectsAggregates(review({ isApproved: true }), review({ isApproved: true, moderatedBy: 'admin' })), false);
  });
  test('averages are rounded to 2 decimals', () => {
    assert.equal(roundAverage(13 / 3), 4.33);
    assert.equal(roundAverage(null), 0);
    assert.equal(roundAverage(Number.NaN), 0);
  });
});

const PROJECT = 'demo-goldengift-reviews';

describe('onReviewWrite (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `reviews-${runId()}`);
  const db = getFirestore(app);
  const read = async (path: string) => (await db.doc(path).get()).data();

  /** Writes the review, then runs the trigger with before / after like Firestore would. */
  async function write(productId: string, id: string, data: DocumentData | null) {
    const ref = db.doc(`products/${productId}/reviews/${id}`);
    const before = (await ref.get()).data();
    if (data === null) await ref.delete();
    else await ref.set(data);
    return handleReviewWrite(db, { productId, reviewId: id, before, after: data ?? undefined });
  }

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    const batch = db.batch();
    batch.set(db.doc('products/p1'), { title: 'Mug', storeId: 'store-a', ratingAvg: 0, ratingCount: 0 });
    batch.set(db.doc('products/p2'), { title: 'Frame', storeId: 'store-a', ratingAvg: 0, ratingCount: 0 });
    batch.set(db.doc('products/p3'), { title: 'Cake', storeId: 'store-b', ratingAvg: 0, ratingCount: 0 });
    batch.set(db.doc('stores/store-a'), { name: 'A', status: 'active', ratingAvg: 0, ratingCount: 0 });
    batch.set(db.doc('stores/store-b'), { name: 'B', status: 'active', ratingAvg: 0, ratingCount: 0 });
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  test('pending reviews never count; approval, hiding, rating edits and deletes recompute', async () => {
    assert.deepEqual(await write('p1', 'o1_alice', review({ rating: 5 })), { recomputed: false });
    assert.equal((await read('products/p1'))?.ratingCount, 0);

    await write('p1', 'o1_alice', review({ rating: 5, isApproved: true }));
    await write('p1', 'o2_bob', review({ userId: 'bob', orderId: 'o2', rating: 4, isApproved: true }));
    await write('p1', 'o3_cara', review({ userId: 'cara', orderId: 'o3', rating: 1 })); // pending
    let p1 = await read('products/p1');
    assert.deepEqual([p1?.ratingAvg, p1?.ratingCount], [4.5, 2]);
    assert.ok(p1?.updatedAt instanceof Timestamp);

    await write('p1', 'o2_bob', review({ userId: 'bob', orderId: 'o2', rating: 2, isApproved: true }));
    p1 = await read('products/p1');
    assert.deepEqual([p1?.ratingAvg, p1?.ratingCount], [3.5, 2]);

    await write('p1', 'o1_alice', review({ rating: 5, isApproved: false })); // hidden
    p1 = await read('products/p1');
    assert.deepEqual([p1?.ratingAvg, p1?.ratingCount], [2, 1]);

    await write('p1', 'o2_bob', null); // deleted
    p1 = await read('products/p1');
    assert.deepEqual([p1?.ratingAvg, p1?.ratingCount], [0, 0]);
  });

  test("the store aggregate covers all of its products' approved reviews (collection group)", async () => {
    await write('p1', 'o1_alice', review({ rating: 5, isApproved: true }));
    await write('p2', 'o1_alice', review({ productId: 'p2', rating: 2, isApproved: true }));
    await write('p2', 'o4_bob', review({ productId: 'p2', userId: 'bob', orderId: 'o4', rating: 3 })); // pending
    const result = await write('p3', 'o5_bob', review({ productId: 'p3', storeId: 'store-b', userId: 'bob', orderId: 'o5', rating: 3, isApproved: true }));
    assert.deepEqual(result, { recomputed: true, product: { ratingAvg: 3, ratingCount: 1 }, stores: { 'store-b': { ratingAvg: 3, ratingCount: 1 } } });

    const a = await read('stores/store-a');
    assert.deepEqual([a?.ratingAvg, a?.ratingCount], [3.5, 2]);
    const b = await read('stores/store-b');
    assert.deepEqual([b?.ratingAvg, b?.ratingCount], [3, 1]);
  });

  test('a store change recomputes both stores; replays write the same numbers', async () => {
    await write('p1', 'o1_alice', review({ rating: 4, isApproved: true }));
    const moved = review({ rating: 4, isApproved: true, storeId: 'store-b' });
    const before = review({ rating: 4, isApproved: true });
    await db.doc('products/p1/reviews/o1_alice').set(moved);
    const event = { productId: 'p1', reviewId: 'o1_alice', before, after: moved };
    const first = await handleReviewWrite(db, event);
    assert.deepEqual(first.recomputed && first.stores, {
      'store-a': { ratingAvg: 0, ratingCount: 0 },
      'store-b': { ratingAvg: 4, ratingCount: 1 },
    });
    const updatedAt = (await read('stores/store-b'))?.updatedAt as Timestamp;
    // Replay: same numbers, nothing rewritten.
    assert.deepEqual(await handleReviewWrite(db, event), first);
    assert.ok(((await read('stores/store-b'))?.updatedAt as Timestamp).isEqual(updatedAt));
  });

  test('a review of a deleted product or store writes nothing', async () => {
    await db.doc('products/p1').delete();
    await db.doc('stores/store-a').delete();
    const result = await write('p1', 'o1_alice', review({ rating: 5, isApproved: true }));
    assert.equal(result.recomputed, true);
    assert.equal(await read('products/p1'), undefined);
    assert.equal(await read('stores/store-a'), undefined);
  });
});
