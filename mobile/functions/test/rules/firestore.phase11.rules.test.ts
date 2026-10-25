/**
 * mobile/firestore.production.rules — Phase 11 (SRS §5.8a, §5.27, §6.17): reels
 * (read while visible or by admins, written by admins only; feed queries must
 * filter `visible == true`) and products' `giftFor` (+ derived `forKeys`) as the
 * dashboard writes them for admins and sellers. Own demo- project, cleared
 * before every test.
 */
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import { initializeTestEnvironment, type RulesTestContext, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  setLogLevel,
  updateDoc,
  where,
  writeBatch,
  type DocumentData,
  type Firestore,
} from 'firebase/firestore';
import { derivedProductFields } from '../../src/shared/productDerived';
import { derivedReelFields } from '../../src/shared/reelDerived';
import { needsEnv } from '../emulators';
import { allowed, denied, rulesFile } from './rulesEnv';

const PROJECT_ID = 'demo-goldengift-rules-phase11';

const PRODUCT: DocumentData = {
  title: 'Mug',
  storeId: 'store-a',
  categoryIds: ['mugs'],
  images: ['https://img/1.jpg'],
  price: 30000,
  isActive: true,
  isFeatured: false,
  availableCities: [],
  giftFor: ['men', 'women'],
  salesCount: 0,
  viewCount: 0,
  ratingAvg: 0,
  ratingCount: 0,
};

/** A reel as the dashboard saves it: editable fields + the derived ones. */
const reel = (over: DocumentData = {}, product: DocumentData | null = PRODUCT): DocumentData => {
  const editable = {
    productId: 'pa',
    videoUrl: 'https://video/r.mp4',
    posterUrl: 'https://video/r.jpg',
    durationMs: 12000,
    aspectRatio: 0.5625,
    caption: 'Best seller',
    isActive: true,
    createdBy: 'admin-1',
    createdAt: Timestamp.fromMillis(Date.UTC(2026, 9, 24)),
    updatedAt: Timestamp.fromMillis(Date.UTC(2026, 9, 24)),
    ...over,
  };
  return { ...editable, ...derivedReelFields(editable, product) };
};

describe('firestore.production.rules — Phase 11', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  let env: RulesTestEnvironment;
  let alice: Firestore, anon: Firestore, admin: Firestore, sellerA: Firestore;
  /** The admin claim, but the admins doc is gone (revoked). */
  let revoked: Firestore;
  const db = (ctx: RulesTestContext) => ctx.firestore() as unknown as Firestore;

  before(async () => {
    setLogLevel('error');
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules: readFileSync(rulesFile('firestore.production.rules'), 'utf8') },
    });
    alice = db(env.authenticatedContext('alice'));
    anon = db(env.unauthenticatedContext());
    admin = db(env.authenticatedContext('admin-1', { admin: true }));
    revoked = db(env.authenticatedContext('admin-gone', { admin: true }));
    sellerA = db(env.authenticatedContext('seller-a', { seller: 'store-a' }));
  });

  after(async () => {
    await env.clearFirestore();
    await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = db(ctx);
      const seed: Record<string, DocumentData> = {
        'admins/admin-1': { role: 'content', name: 'Admin' },
        'admins/seller-a': { role: 'seller', storeId: 'store-a', name: 'Seller A' },
        'stores/store-a': { name: 'Store A', status: 'active', ownerUid: 'seller-a', commissionPercent: 10 },
        'products/pa': { ...PRODUCT, ...derivedProductFields(PRODUCT) },
        'products/legacy': { ...PRODUCT, giftFor: ['men', 'kids'] }, // written before the rules checked giftFor
        'reels/shown': reel(),
        'reels/hidden': reel({ isActive: false }),
        'reels/orphan': reel({ productId: 'gone' }, null),
        'reels/old': { productId: 'pa', videoUrl: 'https://video/old.mp4', isActive: true }, // no derived fields yet
      };
      for (const [path, data] of Object.entries(seed)) await setDoc(doc(d, path), data);
    });
  });

  describe('reels: read while visible, or by admins', () => {
    test('everyone reads a visible reel', async () => {
      for (const fs of [anon, alice, sellerA, admin]) await allowed(getDoc(doc(fs, 'reels/shown')));
    });
    test('hidden, orphaned and not-yet-derived reels: admins only', async () => {
      for (const path of ['reels/hidden', 'reels/orphan', 'reels/old']) {
        for (const fs of [anon, alice, sellerA, revoked]) await denied(getDoc(doc(fs, path)));
        await allowed(getDoc(doc(admin, path)));
      }
    });
    test("the app's feed queries (visible == true [+ filterKeys] [+ priceBand in], newest first) are allowed", async () => {
      const feed = (fs: Firestore, ...filters: Array<ReturnType<typeof where>>) =>
        getDocs(
          query(collection(fs, 'reels'), where('visible', '==', true), ...filters, orderBy('createdAt', 'desc'), limit(8)),
        );
      for (const fs of [anon, alice]) {
        await allowed(feed(fs));
        await allowed(feed(fs, where('filterKeys', 'array-contains', 'cat:mugs|for:women')));
        await allowed(feed(fs, where('priceBand', 'in', [1, 2])));
        await allowed(feed(fs, where('filterKeys', 'array-contains', 'for:men'), where('priceBand', 'in', [0, 1])));
      }
    });
    test('query safety: a list without visible == true (or asking for hidden ones) is denied for non-admins', async () => {
      for (const fs of [anon, alice, sellerA, revoked]) {
        await denied(getDocs(collection(fs, 'reels')));
        await denied(getDocs(query(collection(fs, 'reels'), orderBy('createdAt', 'desc'), limit(8))));
        await denied(getDocs(query(collection(fs, 'reels'), where('filterKeys', 'array-contains', 'cat:mugs'))));
        await denied(getDocs(query(collection(fs, 'reels'), where('visible', '==', false))));
        await denied(getDocs(query(collection(fs, 'reels'), where('isActive', '==', true))));
      }
    });
    test('admins list every reel (the dashboard grid: newest first, All / Active / Hidden chips on the page)', async () => {
      await allowed(getDocs(query(collection(admin, 'reels'), orderBy('createdAt', 'desc'), limit(60))));
      await allowed(getDocs(query(collection(admin, 'reels'), where('isActive', '==', false))));
    });
  });

  describe('reels: written by admins only', () => {
    test('an admin creates, edits, hides and deletes a reel (with the audit entry in the batch)', async () => {
      const batch = writeBatch(admin);
      batch.set(doc(admin, 'reels/new'), { ...reel(), createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
      batch.set(doc(collection(admin, 'admin_audit_log')), {
        adminUid: 'admin-1',
        action: 'reel.create',
        target: 'reels/new',
        before: null,
        after: null,
        at: serverTimestamp(),
      });
      await allowed(batch.commit());
      await allowed(updateDoc(doc(admin, 'reels/new'), { caption: 'New caption', updatedAt: serverTimestamp() }));
      await allowed(updateDoc(doc(admin, 'reels/shown'), { isActive: false, visible: false }));
      await allowed(deleteDoc(doc(admin, 'reels/new')));
    });
    test('signed-out visitors, customers, sellers and revoked admins write nothing', async () => {
      for (const fs of [anon, alice, sellerA, revoked]) {
        await denied(setDoc(doc(fs, 'reels/x'), reel()));
        await denied(updateDoc(doc(fs, 'reels/shown'), { caption: 'Hacked' }));
        await denied(updateDoc(doc(fs, 'reels/hidden'), { visible: true }));
        await denied(deleteDoc(doc(fs, 'reels/shown')));
      }
    });
  });

  describe('products: giftFor (+ derived forKeys) as the dashboard writes them', () => {
    const newProduct = (giftFor: unknown): DocumentData => {
      const data = { ...PRODUCT, giftFor };
      return { ...data, ...derivedProductFields(data), createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
    };
    test('admins and the store seller save products with giftFor and forKeys', async () => {
      await allowed(setDoc(doc(admin, 'products/n1'), newProduct(['companies'])));
      await allowed(setDoc(doc(sellerA, 'products/n2'), newProduct(['men', 'women', 'companies'])));
      // The dashboard requires one; the rules tolerate none (older clients).
      await allowed(setDoc(doc(sellerA, 'products/n3'), newProduct([])));
      // An older dashboard that writes neither field.
      const older = newProduct(['men']);
      delete older.giftFor;
      delete older.forKeys;
      await allowed(setDoc(doc(sellerA, 'products/n4'), older));
      const forHer = { giftFor: ['women'], forKeys: ['women', 'women|cat:mugs'] };
      await allowed(updateDoc(doc(sellerA, 'products/pa'), forHer));
      await allowed(updateDoc(doc(admin, 'products/pa'), { giftFor: ['companies', 'men'] }));
    });
    test('unknown gift types, more than three, or not a list are refused (admins too)', async () => {
      for (const giftFor of [['kids'], ['men', 'women', 'companies', 'men'], 'men', [1]]) {
        await denied(setDoc(doc(admin, 'products/bad'), newProduct(giftFor)));
        await denied(setDoc(doc(sellerA, 'products/bad'), newProduct(giftFor)));
        await denied(updateDoc(doc(sellerA, 'products/pa'), { giftFor }));
        await denied(updateDoc(doc(admin, 'products/pa'), { giftFor }));
      }
    });
    test("an edit that doesn't touch giftFor still saves a product whose stored giftFor is off", async () => {
      await allowed(updateDoc(doc(sellerA, 'products/legacy'), { price: 32000, updatedAt: serverTimestamp() }));
      await allowed(updateDoc(doc(admin, 'products/legacy'), { searchKeywords: ['mug'] }));
    });
    test('customers still write no product', async () => {
      await denied(setDoc(doc(alice, 'products/n9'), newProduct(['men'])));
      await denied(updateDoc(doc(alice, 'products/pa'), { giftFor: ['women'] }));
    });
  });
});
