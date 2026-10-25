import assert from 'node:assert/strict';
import { after, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { syncProduct } from '../src/products/onProductWrite';
import { buildProductRecord } from '../src/search/productRecord';
import { DERIVED_PRODUCT_FIELDS, derivedProductFields } from '../src/shared/productDerived';
import { derivedReelFields } from '../src/shared/reelDerived';
import { planReindex } from '../scripts/algolia/reindex';
import { PROJECT_ID, needsEnv, runId } from './emulators';
import { FakeAlgolia } from './fakeAlgolia';

describe('syncProduct / onProductWrite (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT_ID }, 'on-product-write-test');
  const db = getFirestore(app);
  const run = runId();
  const ids: string[] = [];
  const reelIds: string[] = [];
  const extraCollections: string[] = [];
  let n = 0;

  const EDITED_AT = Timestamp.fromMillis(Date.UTC(2026, 9, 1, 12, 0, 0));
  const CREATED_AT = Timestamp.fromMillis(Date.UTC(2026, 8, 1, 9, 0, 0));

  const newId = (label: string) => {
    const id = `pow-${run}-${label}-${n++}`;
    ids.push(id);
    return id;
  };
  const ref = (id: string) => db.collection('products').doc(id);
  const read = async (id: string) => (await ref(id).get()).data();

  /** A product as the admin dashboard writes it — without derived fields. */
  const adminDoc = (over: DocumentData = {}): DocumentData => ({
    title: 'Gold Mug',
    titleAr: 'كوب ذهبي',
    titleKu: 'کوپی زێڕین',
    description: 'A mug',
    storeId: 'golden-gift-home',
    categoryIds: ['mugs', 'birthdays'],
    images: ['https://img/1.jpg', 'https://img/2.jpg', 'https://img/3.jpg'],
    price: 30000,
    compareAtPrice: 35000,
    currency: 'IQD',
    isActive: true,
    isFeatured: false,
    availability: 'sameDay',
    preparationDays: 0,
    availableCities: [],
    stock: null,
    salesCount: 3,
    viewCount: 10,
    ratingAvg: 0,
    ratingCount: 0,
    tags: ['mug'],
    giftFor: ['men', 'women'],
    optionGroups: [],
    createdAt: CREATED_AT,
    updatedAt: EDITED_AT,
    ...over,
  });

  /** Writes `data`, then runs the trigger logic with the event's before / after, like Firestore would. */
  async function write(id: string, data: DocumentData | null, algolia: FakeAlgolia | null) {
    const before = await read(id);
    if (data === null) await ref(id).delete();
    else await ref(id).set(data);
    const afterData = await read(id);
    return syncProduct(db, id, before, afterData, algolia?.index('products') ?? null);
  }

  /** Re-delivers the event a write-back produced (before = the event's after, after = now). */
  async function replayWriteBack(id: string, before: DocumentData | undefined, algolia: FakeAlgolia | null) {
    return syncProduct(db, id, before, await read(id), algolia?.index('products') ?? null);
  }

  after(async () => {
    const batch = db.batch();
    for (const id of ids) batch.delete(ref(id));
    for (const id of reelIds) batch.delete(db.collection('reels').doc(id));
    await batch.commit();
    for (const c of extraCollections) {
      const docs = await db.collection(c).listDocuments();
      const b = db.batch();
      docs.forEach((d) => b.delete(d));
      await b.commit();
    }
    await deleteApp(app);
  });

  test('derived fields are written once; the write-back run is a no-op (no loop)', async () => {
    const algolia = new FakeAlgolia();
    const id = newId('create');
    const first = await write(id, adminDoc(), algolia);
    assert.deepEqual(first, { derivedWritten: [...DERIVED_PRODUCT_FIELDS], reelsUpdated: 0, algolia: 'saved' });

    const stored = (await read(id))!;
    assert.deepEqual(
      Object.fromEntries(DERIVED_PRODUCT_FIELDS.map((f) => [f, stored[f]])),
      derivedProductFields(adminDoc()),
    );
    assert.equal(stored.hasDiscount, true);
    assert.equal(stored.priceBand, 1);
    assert.deepEqual(stored.cityKeys, ['all']);
    assert.deepEqual(stored.catCityKeys, ['mugs|all', 'birthdays|all']);
    assert.ok((stored.forKeys as string[]).includes('women|cat:mugs|city:all'));
    assert.equal((stored.forKeys as string[]).length, 12, '2 audiences × (1 + 2 categories + 1 city + 2 pairs)');
    assert.ok((stored.searchKeywords as string[]).includes('کوپی'));
    // Only the derived fields were touched: updatedAt keeps the admin's edit time.
    assert.ok((stored.updatedAt as Timestamp).isEqual(EDITED_AT));
    assert.ok((stored.createdAt as Timestamp).isEqual(CREATED_AT));
    assert.equal(stored.title, 'Gold Mug');

    // The write-back fires the trigger again: nothing to write, nothing to send.
    const updateTime = (await ref(id).get()).updateTime!;
    const second = await replayWriteBack(id, adminDoc(), algolia);
    assert.deepEqual(second, { derivedWritten: [], reelsUpdated: 0, algolia: 'unchanged' });
    assert.ok((await ref(id).get()).updateTime!.isEqual(updateTime), 'no second write');
    assert.deepEqual(algolia.callsFor(id), [{ op: 'saveObject', index: 'products', objectID: id }]);
    assert.deepEqual(algolia.record('products', id), buildProductRecord(id, stored));
  });

  test('a price edit that changes the band updates priceBand / hasDiscount exactly once and the record', async () => {
    const algolia = new FakeAlgolia();
    const id = newId('price');
    await write(id, adminDoc(), algolia);
    const before = (await read(id))!;

    const edited = { ...before, price: 60000, updatedAt: Timestamp.now() };
    const result = await write(id, edited, algolia);
    assert.deepEqual(result, { derivedWritten: ['hasDiscount', 'priceBand'], reelsUpdated: 0, algolia: 'saved' });
    const stored = (await read(id))!;
    assert.equal(stored.priceBand, 2);
    assert.equal(stored.hasDiscount, false);
    assert.equal(algolia.record('products', id)?.price, 60000);
    assert.equal(algolia.record('products', id)?.priceBand, 2);

    assert.deepEqual(await replayWriteBack(id, edited, algolia), {
      derivedWritten: [],
      reelsUpdated: 0,
      algolia: 'unchanged',
    });
    assert.equal(algolia.callsFor(id).length, 2, 'create + edit, nothing for the write-back');
  });

  test('inactive → record deleted; reactivated → saved again', async () => {
    const algolia = new FakeAlgolia();
    const id = newId('inactive');
    await write(id, adminDoc(), algolia);
    const active = (await read(id))!;

    assert.deepEqual(await write(id, { ...active, isActive: false }, algolia), {
      derivedWritten: [],
      reelsUpdated: 0,
      algolia: 'deleted',
    });
    assert.equal(algolia.record('products', id), undefined);
    assert.deepEqual(algolia.calls.at(-1), { op: 'deleteObject', index: 'products', objectID: id });

    // Editing an inactive product sends nothing (it is not in the index).
    const calls = algolia.calls.length;
    assert.equal((await write(id, { ...active, isActive: false, price: 1000 }, algolia)).algolia, 'unchanged');
    assert.equal(algolia.calls.length, calls);

    assert.equal((await write(id, { ...active, price: 1000 }, algolia)).algolia, 'saved');
    assert.equal(algolia.record('products', id)?.price, 1000);
  });

  test('deleted product → record deleted, nothing written', async () => {
    const algolia = new FakeAlgolia();
    const id = newId('delete');
    await write(id, adminDoc(), algolia);
    assert.deepEqual(await write(id, null, algolia), { derivedWritten: [], reelsUpdated: 0, algolia: 'deleted' });
    assert.equal(await read(id), undefined, 'not recreated by the derived write');
    assert.equal(algolia.record('products', id), undefined);
  });

  test('Algolia not configured → derived fields still maintained, no Algolia calls, no error', async () => {
    const id = newId('unconfigured');
    assert.deepEqual(await write(id, adminDoc({ price: 250000 }), null), {
      derivedWritten: [...DERIVED_PRODUCT_FIELDS],
      reelsUpdated: 0,
      algolia: 'notConfigured',
    });
    assert.equal((await read(id))!.priceBand, 4);
    assert.deepEqual(await replayWriteBack(id, adminDoc({ price: 250000 }), null), {
      derivedWritten: [],
      reelsUpdated: 0,
      algolia: 'notConfigured',
    });
    assert.deepEqual(await write(id, null, null), { derivedWritten: [], reelsUpdated: 0, algolia: 'notConfigured' });
  });

  test('a viewCount bump writes nothing and sends nothing', async () => {
    const algolia = new FakeAlgolia();
    const id = newId('views');
    await write(id, adminDoc(), algolia);
    const current = (await read(id))!;
    const calls = algolia.calls.length;
    await ref(id).update({ viewCount: 11 });
    const updateTime = (await ref(id).get()).updateTime!;
    assert.deepEqual(await replayWriteBack(id, current, algolia), {
      derivedWritten: [],
      reelsUpdated: 0,
      algolia: 'unchanged',
    });
    assert.ok((await ref(id).get()).updateTime!.isEqual(updateTime));
    assert.equal(algolia.calls.length, calls);
  });

  test('a late / out-of-order event never writes old values back', async () => {
    const algolia = new FakeAlgolia();
    const id = newId('late');
    await write(id, adminDoc(), algolia);
    const v1 = (await read(id))!;
    await write(id, { ...v1, price: 120000 }, algolia); // the newer edit, already processed
    const updateTime = (await ref(id).get()).updateTime!;

    // The older event (price 30000 → 45000 without derived fields) arrives last.
    const stale = adminDoc({ price: 45000 });
    const result = await syncProduct(db, id, v1, stale, algolia.index('products'));
    assert.deepEqual(result, { derivedWritten: [], reelsUpdated: 0, algolia: 'saved' });
    const stored = (await read(id))!;
    assert.equal(stored.priceBand, 3, 'band of the current price, untouched');
    assert.ok((await ref(id).get()).updateTime!.isEqual(updateTime));
    assert.equal(algolia.record('products', id)?.price, 120000, 'record of the current document');
  });

  test('an Algolia outage fails the run (so the trigger retries); the retry converges', async () => {
    const algolia = new FakeAlgolia();
    const id = newId('outage');
    algolia.failWith = new Error('Algolia unreachable');
    const doc = adminDoc();
    await ref(id).set(doc);
    await assert.rejects(syncProduct(db, id, undefined, doc, algolia.index('products')), /Algolia unreachable/);
    assert.equal((await read(id))!.priceBand, 1, 'derived fields were written before the failure');

    algolia.failWith = null;
    // The retry delivers the same event again.
    assert.deepEqual(await syncProduct(db, id, undefined, doc, algolia.index('products')), {
      derivedWritten: [],
      reelsUpdated: 0,
      algolia: 'saved',
    });
    assert.ok(algolia.record('products', id));
  });

  test('event for a document deleted since → no derived write, record deleted', async () => {
    const algolia = new FakeAlgolia();
    const id = newId('gone');
    assert.deepEqual(await syncProduct(db, id, undefined, adminDoc(), algolia.index('products')), {
      derivedWritten: [],
      reelsUpdated: 0,
      algolia: 'deleted',
    });
    assert.equal(await read(id), undefined);
  });

  // ── Reels of the product (SRS §6.4a, Phase 11) ──

  /** A reel as the dashboard saves it: its derived fields as of `product`. */
  async function addReel(label: string, productId: string, product: DocumentData | null, over: DocumentData = {}) {
    const id = `pow-${run}-reel-${label}-${n++}`;
    reelIds.push(id);
    const reel = {
      productId,
      videoUrl: `https://video/${id}.mp4`,
      isActive: true,
      createdAt: CREATED_AT,
      updatedAt: EDITED_AT,
      ...over,
    };
    await db.collection('reels').doc(id).set({ ...reel, ...derivedReelFields(reel, product) });
    return id;
  }
  const readReel = async (id: string) => (await db.collection('reels').doc(id).get()).data()!;

  test('reels follow what they show (price, title, gift types); the write-back and view bumps query nothing', async () => {
    const id = newId('reels');
    await write(id, adminDoc(), null);
    const v1 = (await read(id))!;
    const shown = await addReel('shown', id, v1);
    const hidden = await addReel('hidden', id, v1, { isActive: false });
    const other = await addReel('other', `${id}-other`, null);
    const otherBefore = (await db.collection('reels').doc(other).get()).updateTime!;

    const v2 = { ...v1, price: 120000, title: 'Grand Mug', giftFor: ['companies'] };
    const result = await write(id, v2, null);
    assert.equal(result.reelsUpdated, 2, 'both reels of the product, active or not');
    const r = await readReel(shown);
    assert.deepEqual(r.product, {
      title: 'Grand Mug',
      titleAr: 'كوب ذهبي',
      titleKu: 'کوپی زێڕین',
      image: 'https://img/1.jpg',
      price: 120000,
      compareAtPrice: 35000,
      isActive: true,
    });
    assert.equal(r.priceBand, 3);
    assert.deepEqual(r.giftFor, ['companies']);
    assert.deepEqual(r.filterKeys, [
      'cat:mugs',
      'cat:birthdays',
      'for:companies',
      'cat:mugs|for:companies',
      'cat:birthdays|for:companies',
    ]);
    assert.equal(r.visible, true);
    assert.ok((r.updatedAt as Timestamp).isEqual(EDITED_AT), "updatedAt keeps the editor's time");
    assert.equal((await readReel(hidden)).visible, false, 'an inactive reel stays hidden');
    const otherAfter = (await db.collection('reels').doc(other).get()).updateTime!;
    assert.ok(otherAfter.isEqual(otherBefore), "another product's reel is untouched");

    // The product's own write-back (forKeys) and a view bump change nothing a reel shows.
    const reelTime = (await db.collection('reels').doc(shown).get()).updateTime!;
    assert.equal((await replayWriteBack(id, v2, null)).reelsUpdated, 0);
    const current = (await read(id))!;
    await ref(id).update({ viewCount: 99 });
    assert.equal((await replayWriteBack(id, current, null)).reelsUpdated, 0);
    assert.ok((await db.collection('reels').doc(shown).get()).updateTime!.isEqual(reelTime));
  });

  test('a deactivated product hides its reels; reactivating shows them again; deleting hides them for good', async () => {
    const id = newId('reels-status');
    await write(id, adminDoc(), null);
    const v1 = (await read(id))!;
    const reel = await addReel('status', id, v1);

    assert.equal((await write(id, { ...v1, isActive: false }, null)).reelsUpdated, 1);
    assert.equal((await readReel(reel)).visible, false);
    assert.equal(((await readReel(reel)).product as DocumentData).isActive, false);

    assert.equal((await write(id, { ...v1, isActive: true }, null)).reelsUpdated, 1);
    assert.equal((await readReel(reel)).visible, true);

    assert.equal((await write(id, null, null)).reelsUpdated, 1);
    const gone = await readReel(reel);
    assert.equal(gone.visible, false);
    assert.equal(gone.product, null);
    assert.deepEqual(gone.filterKeys, []);
    assert.equal(gone.productId, id, 'the reel itself is kept (the dashboard shows "Product unavailable")');
  });

  test('a product edit only rewrites the reels that are stale (reels already up to date are not counted)', async () => {
    const id = newId('reels-partial');
    await write(id, adminDoc(), null);
    const v1 = (await read(id))!;
    const v2 = { ...v1, compareAtPrice: 40000 };
    await addReel('old', id, v1);
    await addReel('fresh', id, v2); // saved by a dashboard that already saw v2
    assert.equal((await write(id, v2, null)).reelsUpdated, 1);
  });

  test('planReindex reads every page of the collection', async () => {
    const name = `reindex_test_${run}`;
    extraCollections.push(name);
    const batch = db.batch();
    for (let i = 0; i < 7; i++) {
      batch.set(db.collection(name).doc(`p${i}`), adminDoc({ isActive: i !== 4, price: 1000 * (i + 1) }));
    }
    await batch.commit();
    const plan = await planReindex(db.collection(name), 3);
    assert.equal(plan.total, 7);
    assert.deepEqual(plan.records.map((r) => r.objectID), ['p0', 'p1', 'p2', 'p3', 'p5', 'p6']);
    assert.deepEqual(plan.inactiveIds, ['p4']);
    assert.equal(plan.records[0].createdAt, CREATED_AT.seconds);
  });
});
