/**
 * onReelWrite (SRS §5.27, §6.4a, §7): derived reel fields from the product,
 * written once (no loop), and a deleted reel's Storage files. Pure change
 * detection, then the Firestore emulator (own demo- project) and the Storage
 * emulator (skipped without them).
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import {
  REEL_SYNC_PAGE_SIZE,
  reelSourceChanged,
  reelStoragePaths,
  syncReel,
  syncReelsOfProduct,
} from '../src/reels/onReelWrite';
import { REEL_DERIVED_FIELDS, derivedReelFields } from '../src/shared/reelDerived';
import { PROJECT_ID, clearEmulatorFirestore, needsEnv, runId } from './emulators';

const product = (over: DocumentData = {}): DocumentData => ({
  title: 'Gold Mug',
  titleAr: 'كوب ذهبي',
  titleKu: 'کوپی زێڕین',
  description: 'Not on the reel',
  storeId: 'golden-gift-home',
  categoryIds: ['mugs', 'love'],
  images: ['https://img/1.jpg', 'https://img/2.jpg'],
  price: 30000,
  compareAtPrice: 35000,
  isActive: true,
  availableCities: [],
  giftFor: ['men', 'women'],
  salesCount: 3,
  viewCount: 10,
  ...over,
});

describe('reelSourceChanged (pure)', () => {
  test('what a reel shows or filters on', () => {
    const p = product();
    for (const over of [
      { title: 'New' },
      { titleAr: 'جديد' },
      { titleKu: '' },
      { images: ['https://img/9.jpg', 'https://img/1.jpg'] },
      { price: 60000 },
      { compareAtPrice: null },
      { categoryIds: ['mugs'] },
      { giftFor: ['companies'] },
      { isActive: false },
      { storeId: 'other' },
    ]) {
      assert.equal(reelSourceChanged(p, { ...p, ...over }), true, JSON.stringify(over));
    }
    assert.equal(reelSourceChanged(undefined, p), true, 'created');
    assert.equal(reelSourceChanged(p, undefined), true, 'deleted');
  });

  test('everything else is not (no reels query)', () => {
    const p = product();
    for (const over of [
      { viewCount: 11 },
      { salesCount: 4, ratingAvg: 4.5, ratingCount: 2 },
      { description: 'New copy' },
      { images: ['https://img/1.jpg', 'https://img/9.jpg'] }, // only the first image is shown
      { availableCities: ['erbil'] },
      { forKeys: ['men'], priceBand: 1, searchKeywords: ['mug'] }, // onProductWrite's own write-back
      { categoryIds: ['mugs', 'love', 'mugs'], giftFor: ['men', 'women', 'nobody'] }, // same after normalizing
    ]) {
      assert.equal(reelSourceChanged(p, { ...p, ...over }), false, JSON.stringify(over));
    }
    assert.equal(reelSourceChanged(undefined, undefined), false);
  });

  test('storage paths: the video and its poster', () => {
    assert.deepEqual(reelStoragePaths('r1'), ['reels/r1.mp4', 'reels/r1.jpg']);
  });
});

const PROJECT = 'demo-goldengift-reels';
/** Storage objects live in the emulator bucket of the project the emulators run as. */
const BUCKET = `${PROJECT_ID}.appspot.com`;
const storageSkip = needsEnv('FIREBASE_STORAGE_EMULATOR_HOST');

describe('onReelWrite (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const run = runId();
  const app = initializeApp({ projectId: PROJECT, storageBucket: BUCKET }, `reels-${run}`);
  // Like goldengift-iq today: no Storage bucket configured.
  const appWithoutBucket = initializeApp({ projectId: PROJECT }, `reels-no-bucket-${run}`);
  const db = getFirestore(app);
  const deps = { db, bucket: () => getStorage(app).bucket() };
  const EDITED_AT = Timestamp.fromMillis(Date.UTC(2026, 9, 24, 12, 0, 0));

  const reelRef = (id: string) => db.collection('reels').doc(id);
  const read = async (id: string) => (await reelRef(id).get()).data();
  /** A reel as the dashboard writes it, without derived fields. */
  const editable = (over: DocumentData = {}): DocumentData => ({
    productId: 'p1',
    videoUrl: 'https://video/r.mp4',
    posterUrl: 'https://video/r.jpg',
    durationMs: 12000,
    aspectRatio: 0.5625,
    caption: 'Our best seller',
    isActive: true,
    createdBy: 'admin-1',
    createdAt: EDITED_AT,
    updatedAt: EDITED_AT,
    ...over,
  });

  /** Writes the reel, then runs the trigger with its after-data like Firestore would. */
  async function write(id: string, data: DocumentData | null) {
    if (data === null) await reelRef(id).delete();
    else await reelRef(id).set(data);
    return syncReel(deps, id, data ?? undefined);
  }

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    await db.doc('products/p1').set(product());
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await Promise.all([deleteApp(app), deleteApp(appWithoutBucket)]);
  });

  test('a reel without derived fields gets all of them once; the write-back run writes nothing (no loop)', async () => {
    const first = await write('r1', editable());
    assert.deepEqual(first, { derivedWritten: [...REEL_DERIVED_FIELDS], filesDeleted: [] });
    const stored = (await read('r1'))!;
    assert.deepEqual(stored.product, {
      title: 'Gold Mug',
      titleAr: 'كوب ذهبي',
      titleKu: 'کوپی زێڕین',
      image: 'https://img/1.jpg',
      price: 30000,
      compareAtPrice: 35000,
      isActive: true,
    });
    assert.equal(stored.storeId, 'golden-gift-home');
    assert.deepEqual(stored.categoryIds, ['mugs', 'love']);
    assert.deepEqual(stored.giftFor, ['men', 'women']);
    assert.equal(stored.priceBand, 1);
    assert.equal(stored.visible, true);
    assert.ok((stored.filterKeys as string[]).includes('cat:love|for:women'));
    // Only the derived fields were touched.
    assert.ok((stored.updatedAt as Timestamp).isEqual(EDITED_AT));
    assert.equal(stored.caption, 'Our best seller');

    // The write-back fires the trigger again: nothing to write.
    const updateTime = (await reelRef('r1').get()).updateTime!;
    assert.deepEqual(await syncReel(deps, 'r1', stored), { derivedWritten: [], filesDeleted: [] });
    assert.ok((await reelRef('r1').get()).updateTime!.isEqual(updateTime), 'no second write');
  });

  test('a reel the dashboard saved with its derived fields (Dart ReelDerived) is not rewritten', async () => {
    const reel = editable();
    await reelRef('r2').set({ ...reel, ...derivedReelFields(reel, product()) });
    const updateTime = (await reelRef('r2').get()).updateTime!;
    assert.deepEqual((await syncReel(deps, 'r2', (await read('r2'))!)).derivedWritten, []);
    assert.ok((await reelRef('r2').get()).updateTime!.isEqual(updateTime));
  });

  test('hidden reel, inactive product, missing or malformed product → visible false', async () => {
    await write('hidden', editable({ isActive: false }));
    assert.equal((await read('hidden'))!.visible, false);
    assert.equal(((await read('hidden'))!.product as DocumentData).isActive, true);

    await db.doc('products/p2').set(product({ isActive: false }));
    await write('inactive', editable({ productId: 'p2' }));
    assert.equal((await read('inactive'))!.visible, false);

    for (const productId of ['missing', 'a/b', '', 42]) {
      const id = `bad-${String(productId).replace('/', '-') || 'empty'}`;
      await write(id, editable({ productId }));
      const r = (await read(id))!;
      assert.equal(r.visible, false, String(productId));
      assert.equal(r.product, null);
      assert.equal(r.storeId, '');
      assert.deepEqual(r.filterKeys, []);
    }
  });

  test('a stale reel gets only the fields that changed (the reel is re-read, not the event data)', async () => {
    await write('r3', editable());
    await db.doc('products/p1').update({ price: 250000 });
    // A late event carrying an old copy of the reel: the current reel decides.
    const result = await syncReel(deps, 'r3', editable({ caption: 'old' }));
    assert.deepEqual(result.derivedWritten, ['product', 'priceBand']);
    const r = (await read('r3'))!;
    assert.equal(r.priceBand, 4);
    assert.equal((r.product as DocumentData).price, 250000);
    assert.equal(r.caption, 'Our best seller');
  });

  test('an event for a reel deleted since writes nothing (and does not recreate it)', async () => {
    assert.deepEqual(await syncReel(deps, 'gone', editable()), { derivedWritten: [], filesDeleted: [] });
    assert.equal(await read('gone'), undefined);
  });

  test('syncReelsOfProduct: every reel of the product, paged; a second run writes nothing', async () => {
    for (let i = 0; i < 5; i++) await reelRef(`p1-${i}`).set(editable());
    await reelRef('p9-0').set(editable({ productId: 'p9' }));
    assert.equal(await syncReelsOfProduct(db, 'p1', 2), 5);
    for (let i = 0; i < 5; i++) assert.equal((await read(`p1-${i}`))!.visible, true);
    assert.equal((await read('p9-0'))!.visible, undefined, 'reels of other products untouched');
    assert.equal(await syncReelsOfProduct(db, 'p1', 2), 0);
    assert.ok(REEL_SYNC_PAGE_SIZE <= 500, 'one transaction per page (500 writes at most)');

    await db.doc('products/p1').delete();
    assert.equal(await syncReelsOfProduct(db, 'p1'), 5);
    assert.equal((await read('p1-3'))!.visible, false);
    assert.equal((await read('p1-3'))!.product, null);
    assert.equal(await syncReelsOfProduct(db, 'nothing-here'), 0);
  });

  test('deleted reel without a Storage bucket → nothing to delete, no error', async () => {
    const noBucket = { db, bucket: () => getStorage(appWithoutBucket).bucket() };
    assert.deepEqual(await syncReel(noBucket, 'r-no-bucket', undefined), { derivedWritten: [], filesDeleted: null });
  });

  test('deleted reel → its video and poster leave Storage; missing files are fine', { skip: storageSkip }, async () => {
    const bucket = getStorage(app).bucket();
    const id = `reel-test-${run}`;
    const [video, poster] = reelStoragePaths(id);
    const neighbour = `reels/${id}-other.mp4`;
    await bucket.file(video).save(Buffer.from('mp4'), { contentType: 'video/mp4', resumable: false });
    await bucket.file(poster).save(Buffer.from('jpeg'), { contentType: 'image/jpeg', resumable: false });
    await bucket.file(neighbour).save(Buffer.from('mp4'), { contentType: 'video/mp4', resumable: false });

    await reelRef(id).set(editable());
    assert.deepEqual(await write(id, null), { derivedWritten: [], filesDeleted: [video, poster] });
    for (const path of [video, poster]) assert.equal((await bucket.file(path).exists())[0], false, path);
    assert.equal((await bucket.file(neighbour).exists())[0], true, "only the reel's own files");
    await bucket.file(neighbour).delete();

    // A retry, or a reel that never had a poster: nothing left to delete is not an error.
    assert.deepEqual(await syncReel(deps, id, undefined), { derivedWritten: [], filesDeleted: [video, poster] });
  });
});
