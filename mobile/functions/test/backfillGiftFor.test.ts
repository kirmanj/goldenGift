/**
 * scripts/backfill-gift-for.ts core: products saved before Phase 11 get `giftFor`
 * (seed products their own, others men + women) and their derived `forKeys`,
 * once; nothing else changes. Pure part always; the Firestore part against the
 * emulator (own demo- project).
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { DEFAULT_GIFT_FOR, backfillGiftFor, backfillGiftForOf } from '../scripts/maintenance/backfillGiftFor';
import { PRODUCTS } from '../scripts/seed-data/products';
import { derivedProductFields, staleDerivedFields } from '../src/shared/productDerived';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';

const necklace = PRODUCTS.find((p) => p.id === 'gold-name-necklace')!;

describe('backfillGiftForOf', () => {
  test('missing / empty / only unknown values → the seed gift types, else men + women', () => {
    assert.deepEqual(DEFAULT_GIFT_FOR, ['men', 'women']);
    for (const giftFor of [undefined, null, [], ['kids'], 'women', [7]]) {
      assert.deepEqual(backfillGiftForOf('someone-elses-product', giftFor), ['men', 'women'], JSON.stringify(giftFor));
      assert.deepEqual(backfillGiftForOf(necklace.id, giftFor), necklace.giftFor);
    }
    assert.deepEqual(backfillGiftForOf('engraved-metal-pen', undefined), ['men', 'companies']);
  });
  test('a known gift type → nothing to do (even next to junk)', () => {
    assert.equal(backfillGiftForOf('p', ['companies']), null);
    assert.equal(backfillGiftForOf('p', ['kids', 'women']), null);
    assert.equal(backfillGiftForOf(necklace.id, ['men']), null, 'an edited seed product keeps its edit');
  });
});

describe('backfillGiftFor (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const PROJECT = 'demo-goldengift-backfill-gift-for';
  const app = initializeApp({ projectId: PROJECT }, `backfill-gift-for-${runId()}`);
  const db = getFirestore(app);
  const updatedAt = Timestamp.fromMillis(Date.UTC(2026, 9, 1));

  /** A product saved before Phase 11: Phase 10 derived fields, no giftFor / forKeys. */
  const legacy = (over: DocumentData = {}): DocumentData => {
    const base = { title: 'Mug', price: 30000, categoryIds: ['mugs'], availableCities: ['erbil'], tags: ['mug'], ...over };
    const derived: DocumentData = { ...derivedProductFields(base) };
    delete derived.forKeys; // Phase 10 had no gift types
    return { ...base, ...derived, description: 'Kept', isActive: true, updatedAt };
  };

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    const batch = db.batch();
    for (let i = 0; i < 5; i++) batch.set(db.doc(`products/old-${i}`), legacy({ price: 10000 * (i + 1) }));
    batch.set(db.doc(`products/${necklace.id}`), legacy({ title: 'Necklace', categoryIds: necklace.categoryIds }));
    batch.set(db.doc('products/junk'), legacy({ giftFor: ['kids'] }));
    const modern = { ...legacy(), giftFor: ['companies'] };
    batch.set(db.doc('products/new'), { ...modern, ...derivedProductFields(modern) });
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  test('dry run counts and writes nothing', async () => {
    const result = await backfillGiftFor(db, { dryRun: true, pageSize: 3 });
    assert.deepEqual([result.scanned, result.updated, result.fromSeed, result.alreadySet], [8, 7, 1, 1]);
    assert.equal((await db.doc('products/old-0').get()).get('giftFor'), undefined);
  });

  test('sets giftFor + the derived fields once (paged), touching nothing else; a second run does nothing', async () => {
    const pages: number[] = [];
    const result = await backfillGiftFor(db, { pageSize: 3, onPage: (scanned) => pages.push(scanned) });
    assert.deepEqual([result.scanned, result.updated, result.fromSeed, result.alreadySet], [8, 7, 1, 1]);
    assert.deepEqual(pages, [3, 6, 8]);

    const old = (await db.doc('products/old-2').get()).data()!;
    assert.deepEqual(old.giftFor, ['men', 'women']);
    assert.deepEqual(old.forKeys, derivedProductFields(old).forKeys);
    assert.ok((old.forKeys as string[]).includes('women|cat:mugs|city:erbil'));
    assert.deepEqual(staleDerivedFields(old), {}, 'onProductWrite will find nothing to rewrite');
    assert.equal(old.description, 'Kept');
    assert.ok((old.updatedAt as Timestamp).isEqual(updatedAt), 'updatedAt untouched');

    assert.deepEqual((await db.doc(`products/${necklace.id}`).get()).get('giftFor'), necklace.giftFor);
    assert.deepEqual((await db.doc('products/junk').get()).get('giftFor'), ['men', 'women']);
    assert.deepEqual((await db.doc('products/new').get()).get('giftFor'), ['companies']);

    const again = await backfillGiftFor(db, { pageSize: 3 });
    assert.deepEqual([again.updated, again.alreadySet], [0, 8]);
  });
});
