/**
 * scripts/backfill-order-product-ids.ts core: orders placed before Phase 9 get
 * `productIds` (what placeOrder writes), once; nothing else changes. Pure part
 * always; the Firestore part against the emulator (own demo- project).
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { backfillOrderProductIds, productIdsOf } from '../scripts/maintenance/backfillOrderProductIds';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';

describe('productIdsOf', () => {
  test('distinct catalogue ids in line order; synthetic and malformed lines skipped', () => {
    assert.deepEqual(
      productIdsOf([
        { productId: 'p2' },
        { productId: 'p1' },
        { productId: 'p2' },
        { productId: '' },
        { productId: 'a/b' },
        { productId: 7 },
        null,
        'x',
      ]),
      ['p2', 'p1'],
    );
    assert.deepEqual(productIdsOf(undefined), []);
  });
});

describe('backfillOrderProductIds (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const PROJECT = 'demo-goldengift-backfill';
  const app = initializeApp({ projectId: PROJECT }, `backfill-${runId()}`);
  const db = getFirestore(app);
  const updatedAt = Timestamp.fromMillis(Date.UTC(2026, 9, 1));

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    const batch = db.batch();
    for (let i = 0; i < 7; i++) {
      batch.set(db.doc(`orders/old-${i}`), { status: 'delivered', items: [{ productId: `p${i}` }, { productId: 'mug' }], updatedAt });
    }
    batch.set(db.doc('orders/new'), { status: 'pending', items: [{ productId: 'mug' }], productIds: ['mug'], updatedAt });
    batch.set(db.doc('orders/gift'), { status: 'delivered', orderType: 'giftCard', items: [{ productId: '' }], updatedAt });
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  test('dry run counts and writes nothing', async () => {
    const result = await backfillOrderProductIds(db, { dryRun: true, pageSize: 3 });
    assert.deepEqual([result.scanned, result.updated, result.alreadySet], [9, 8, 1]);
    assert.equal((await db.doc('orders/old-0').get()).get('productIds'), undefined);
  });

  test('sets productIds once (paged), touching nothing else; a second run does nothing', async () => {
    const pages: number[] = [];
    const result = await backfillOrderProductIds(db, { pageSize: 3, onPage: (scanned) => pages.push(scanned) });
    assert.deepEqual([result.scanned, result.updated, result.alreadySet], [9, 8, 1]);
    assert.deepEqual(pages, [3, 6, 9]);
    const old = (await db.doc('orders/old-3').get()).data()!;
    assert.deepEqual(old.productIds, ['p3', 'mug']);
    assert.equal(old.status, 'delivered');
    assert.ok((old.updatedAt as Timestamp).isEqual(updatedAt), 'updatedAt untouched');
    assert.deepEqual((await db.doc('orders/gift').get()).get('productIds'), []);
    assert.deepEqual((await db.doc('orders/new').get()).get('productIds'), ['mug']);

    const again = await backfillOrderProductIds(db, { pageSize: 3 });
    assert.deepEqual([again.updated, again.alreadySet], [0, 9]);
  });
});
