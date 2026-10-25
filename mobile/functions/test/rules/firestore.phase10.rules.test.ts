/**
 * mobile/firestore.production.rules — Phase 10 hardening (SRS §6.17): admins need
 * the live admins doc, sellers the live store, the catch-all, and a negative
 * matrix (signed-out visitor / signed-in stranger) over every collection with
 * personal or server-owned data, plus query safety (unfiltered lists denied).
 * Own demo- project, cleared before every test.
 */
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import { initializeTestEnvironment, type RulesTestContext, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
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
import { needsEnv } from '../emulators';
import { allowed, denied, rulesFile } from './rulesEnv';

const PROJECT_ID = 'demo-goldengift-rules-phase10';

describe('firestore.production.rules — Phase 10', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  let env: RulesTestEnvironment;
  let alice: Firestore, bob: Firestore, anon: Firestore, admin: Firestore;
  /** The admin claim, but the admins doc is gone (revoked; the token keeps the claim for up to an hour). */
  let revoked: Firestore;
  /** The admin claim with an admins doc of role `seller` — not staff. */
  let claimSeller: Firestore;
  /** Claim `seller: store-a`, but store-a belongs to someone else now. */
  let staleSeller: Firestore;
  let sellerA: Firestore;
  const db = (ctx: RulesTestContext) => ctx.firestore() as unknown as Firestore;

  before(async () => {
    setLogLevel('error');
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules: readFileSync(rulesFile('firestore.production.rules'), 'utf8') },
    });
    alice = db(env.authenticatedContext('alice'));
    bob = db(env.authenticatedContext('bob'));
    anon = db(env.unauthenticatedContext());
    admin = db(env.authenticatedContext('admin-1', { admin: true }));
    revoked = db(env.authenticatedContext('admin-gone', { admin: true }));
    claimSeller = db(env.authenticatedContext('admin-odd', { admin: true }));
    staleSeller = db(env.authenticatedContext('seller-old', { seller: 'store-a' }));
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
        'admins/admin-1': { role: 'super', name: 'Admin' },
        'admins/admin-odd': { role: 'seller', storeId: 'store-a', name: 'Odd' },
        'admins/seller-a': { role: 'seller', storeId: 'store-a', name: 'Seller A' },
        'stores/store-a': { name: 'Store A', status: 'active', ownerUid: 'seller-a', commissionPercent: 10 },
        'stores/store-p': { name: 'Pending', status: 'pendingApproval', ownerUid: 'carol' },
        'products/pa': { title: 'Mug', storeId: 'store-a', price: 1000, isActive: true, salesCount: 0, viewCount: 0, ratingAvg: 0, ratingCount: 0 },
        'products/pb': { title: 'Frame', storeId: 'store-b', price: 1000, isActive: true },
        'users/alice': { name: 'Alice', phone: '7501234567', countryCode: '+964', locale: 'en', role: 'customer', isBlocked: false, isDeleted: false },
        'users/alice/addresses/home': { city: 'erbil', label: 'Home' },
        'users/alice/saved_cards/c1': { brand: 'visa', last4: '4242' },
        'wallets/alice': { balance: 1000, credits: 0, currency: 'IQD' },
        'wallets/alice/transactions/t1': { type: 'refund', amount: 1000 },
        'wallets/alice/credit_lots/l1': { amount: 1, remaining: 1, open: true },
        'referrals/bob': { referrerUid: 'alice', referredUid: 'bob', status: 'pending' },
        'orders/o1': { userId: 'alice', storeIds: ['store-a'], items: [{ id: 'l1', storeId: 'store-a', status: 'pending' }], status: 'pending', total: 1000 },
        'orders/o1/status_history/h1': { status: 'pending', byUid: 'alice', byRole: 'customer', at: Timestamp.now() },
        'carts/alice/items/i1': { productId: 'pa', qty: 1, unitPrice: 1000 },
        'wishlists/alice/items/pa': { listId: 'default', productId: 'pa' },
        'gift_cards/g1': { code: 'ABCDEFGHJKLM', purchaserUid: 'alice', recipientUid: null, status: 'sent', balance: 1000 },
        'special_requests/r1': { userId: 'alice', type: 'gift', text: 'x', images: [], status: 'submitted' },
        'special_requests/r1/messages/m1': { senderUid: 'alice', role: 'customer', text: 'x', images: [], at: Timestamp.now() },
        'secret_santa_groups/s1': { name: 'Fam', organiserUid: 'alice', status: 'drawn', memberUids: ['alice', 'dave', 'erin'] },
        'secret_santa_groups/s1/members/alice': { name: 'Alice' },
        'secret_santa_groups/s1/assignments/alice': { assigneeUid: 'dave', assigneeName: 'Dave' },
        'notifications/n1': { userId: 'alice', title: 'Hi', isRead: false },
        'payment_sessions/ps1': { uid: 'alice', purpose: 'order', amount: 1000, status: 'pending' },
        'ai_searches/a1': { userId: 'alice', query: 'gift for mum' },
        'promo_codes/EID10': { code: 'EID10', isPublic: true, isActive: true, usageCount: 0 },
        'promo_codes/EID10/usages/alice': { count: 1 },
        'products/pa/reviews/o1_alice': { productId: 'pa', userId: 'alice', storeId: 'store-a', rating: 5, orderId: 'o1', isApproved: false },
        'stores/store-a/private/application': { ownerUid: 'seller-a', phone: '+9647501234567' },
        'admin_audit_log/x1': { adminUid: 'admin-1', action: 'x', target: 'y', at: Timestamp.now() },
        'counters/orders-2610': { next: 3 },
        'function_runs/k1': { key: 'k1' },
      };
      for (const [path, data] of Object.entries(seed)) await setDoc(doc(d, path), data);
    });
  });

  describe('admins: the claim AND the live admins doc', () => {
    /** Run one after the other (each rule evaluation reads the admins doc). */
    const adminOps = (fs: Firestore): Array<() => Promise<unknown>> => [
      () => getDoc(doc(fs, 'users/alice')),
      () => getDocs(collection(fs, 'orders')),
      () => getDoc(doc(fs, 'wallets/alice')),
      () => getDocs(collection(fs, 'admin_audit_log')),
      () => getDoc(doc(fs, 'ai_searches/a1')),
      () => setDoc(doc(fs, 'banners/b9'), { placement: 'homeTop' }),
      () => setDoc(doc(fs, 'app_settings/general'), { maintenanceMode: true }),
      () => setDoc(doc(fs, 'categories/c9'), { title: 'X' }),
      () => updateDoc(doc(fs, 'products/pb'), { isFeatured: true }),
    ];
    test('a staff admin (admins doc role super / ops / content / finance) passes', async () => {
      for (const op of adminOps(admin)) await allowed(op());
    });
    test('a revoked admin (claim still in the token, admins doc deleted) is a stranger at once', async () => {
      for (const op of adminOps(revoked)) await denied(op());
    });
    test('an admins doc with a non-staff role (seller) is not admin, even with the claim', async () => {
      for (const op of adminOps(claimSeller)) await denied(op());
    });
  });

  describe('sellers: the claim AND the live store (active, owned by the caller)', () => {
    const productBatch = (fs: Firestore, uid: string, id: string) => {
      const batch = writeBatch(fs);
      batch.set(doc(fs, `products/${id}`), { title: 'New', storeId: 'store-a', price: 1000, isFeatured: false, createdAt: serverTimestamp() });
      batch.set(doc(collection(fs, 'admin_audit_log')), { adminUid: uid, action: 'product.create', target: `products/${id}`, before: null, after: null, at: serverTimestamp() });
      return batch.commit();
    };
    test('the store owner still works', async () => {
      await allowed(productBatch(sellerA, 'seller-a', 'new-1'));
      await allowed(updateDoc(doc(sellerA, 'stores/store-a'), { description: 'Hand-made', updatedAt: serverTimestamp() }));
    });
    test('a claim for a store the caller no longer owns writes nothing', async () => {
      await denied(productBatch(staleSeller, 'seller-old', 'new-2'));
      await denied(updateDoc(doc(staleSeller, 'products/pa'), { price: 1 }));
      await denied(updateDoc(doc(staleSeller, 'stores/store-a'), { description: 'Hijacked' }));
    });
    test("audit entries only for the seller's own products", async () => {
      const entry = (target: string) => ({ adminUid: 'seller-a', action: 'product.update', target, before: null, after: null, at: serverTimestamp() });
      await allowed(setDoc(doc(sellerA, 'admin_audit_log/e1'), entry('products/pa')));
      await denied(setDoc(doc(sellerA, 'admin_audit_log/e2'), entry('products/pb')));
      await denied(setDoc(doc(sellerA, 'admin_audit_log/e3'), entry('products/does-not-exist')));
    });
  });

  describe('catch-all: anything without its own match is denied — for everyone', () => {
    for (const path of ['secrets/x', 'payouts/p1', 'orders/o1/notes/n1', 'users/alice/private/x', 'wallets/alice/other/x', 'products/pa/stats/s']) {
      test(path, async () => {
        for (const fs of [alice, bob, anon, admin]) {
          await denied(getDoc(doc(fs, path)));
          await denied(setDoc(doc(fs, path), { x: 1 }));
        }
      });
    }
  });

  describe('personal and server-owned data: a signed-out visitor and a signed-in stranger', () => {
    const personal = [
      'users/alice',
      'users/alice/addresses/home',
      'users/alice/saved_cards/c1',
      'wallets/alice',
      'wallets/alice/transactions/t1',
      'wallets/alice/credit_lots/l1',
      'referrals/bob',
      'orders/o1',
      'orders/o1/status_history/h1',
      'carts/alice/items/i1',
      'wishlists/alice/items/pa',
      'gift_cards/g1',
      'special_requests/r1',
      'special_requests/r1/messages/m1',
      'secret_santa_groups/s1',
      'secret_santa_groups/s1/members/alice',
      'secret_santa_groups/s1/assignments/alice',
      'notifications/n1',
      'payment_sessions/ps1',
      'ai_searches/a1',
      'promo_codes/EID10/usages/alice',
      'stores/store-a/private/application',
      'admin_audit_log/x1',
      'counters/orders-2610',
      'function_runs/k1',
    ];
    for (const path of personal) {
      test(`${path}: no read, update or delete`, async () => {
        for (const fs of [anon, bob]) {
          await denied(getDoc(doc(fs, path)));
          await denied(updateDoc(doc(fs, path), { tampered: true }));
          await denied(deleteDoc(doc(fs, path)));
        }
      });
    }
    test('nobody creates server-owned documents', async () => {
      for (const path of [
        'wallets/bob',
        'wallets/bob/transactions/t',
        'wallets/bob/credit_lots/l',
        'referrals/zed',
        'orders/o9',
        'orders/o1/status_history/h9',
        'gift_cards/g9',
        'payment_sessions/ps9',
        'ai_searches/a9',
        'counters/orders-2611',
        'function_runs/k9',
        'promo_codes/EID10/usages/bob',
        'notifications/n9',
        'stores/store-z',
        'secret_santa_groups/s1/assignments/bob',
        'admins/bob',
      ]) {
        for (const fs of [anon, bob, alice]) await denied(setDoc(doc(fs, path), { userId: 'bob', uid: 'bob', amount: 1 }));
      }
    });
    test('the owner never writes the server-owned parts either', async () => {
      await denied(updateDoc(doc(alice, 'wallets/alice'), { balance: 1_000_000 }));
      await denied(updateDoc(doc(alice, 'orders/o1'), { total: 0 }));
      await denied(updateDoc(doc(alice, 'gift_cards/g1'), { balance: 1_000_000 }));
      await denied(updateDoc(doc(alice, 'payment_sessions/ps1'), { status: 'paid' }));
      await denied(updateDoc(doc(alice, 'promo_codes/EID10'), { usageCount: 0 }));
      await denied(updateDoc(doc(alice, 'users/alice'), { role: 'admin', isBlocked: false }));
      await denied(updateDoc(doc(alice, 'users/alice'), { totalOrders: 0 }));
      await denied(updateDoc(doc(alice, 'secret_santa_groups/s1/assignments/alice'), { assigneeUid: 'erin' }));
    });
  });

  describe('query safety: lists must carry the filter the rules check', () => {
    test('unfiltered lists are denied for customers', async () => {
      for (const name of ['users', 'orders', 'wallets', 'referrals', 'gift_cards', 'special_requests', 'notifications', 'payment_sessions', 'secret_santa_groups', 'ai_searches', 'stores', 'admin_audit_log', 'admins']) {
        await denied(getDocs(collection(alice, name)));
      }
      await denied(getDocs(collectionGroup(alice, 'reviews')));
      await denied(getDocs(collectionGroup(alice, 'transactions')));
      await denied(getDocs(collectionGroup(alice, 'assignments')));
    });
    test("the app's own filtered queries are allowed", async () => {
      await allowed(getDocs(query(collection(alice, 'orders'), where('userId', '==', 'alice'))));
      await allowed(getDocs(query(collection(alice, 'payment_sessions'), where('uid', '==', 'alice'))));
      await allowed(getDocs(query(collection(alice, 'gift_cards'), where('purchaserUid', '==', 'alice'))));
      await allowed(getDocs(query(collection(alice, 'special_requests'), where('userId', '==', 'alice'))));
      await allowed(getDocs(query(collection(alice, 'referrals'), where('referrerUid', '==', 'alice'))));
      await allowed(getDocs(query(collection(alice, 'secret_santa_groups'), where('memberUids', 'array-contains', 'alice'))));
      await allowed(getDocs(query(collection(anon, 'stores'), where('status', '==', 'active'))));
      await allowed(getDocs(query(collectionGroup(anon, 'reviews'), where('isApproved', '==', true))));
    });
    test("filters naming someone else are denied", async () => {
      await denied(getDocs(query(collection(bob, 'orders'), where('userId', '==', 'alice'))));
      await denied(getDocs(query(collection(bob, 'payment_sessions'), where('uid', '==', 'alice'))));
      await denied(getDocs(query(collection(bob, 'gift_cards'), where('purchaserUid', '==', 'alice'))));
      await denied(getDocs(query(collection(anon, 'stores'), where('status', '==', 'pendingApproval'))));
    });
  });
});
