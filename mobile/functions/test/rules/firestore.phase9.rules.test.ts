import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  initializeTestEnvironment,
  type RulesTestContext,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
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
import { needsEnv } from '../emulators';
import { allowed, denied, rulesFile } from './rulesEnv';

/**
 * Phase 9 parts of mobile/firestore.production.rules: products/{id}/reviews (+ the
 * collection-group read), secret_santa_groups (+ members, assignments),
 * ai_searches, payment_sessions. Own project id (rules and data are per project in
 * the Firestore emulator), so it runs in parallel with the other rules suites.
 */
const PROJECT_ID = 'demo-goldengift-rules-phase9';

describe('firestore.production.rules — Phase 9', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  let env: RulesTestEnvironment;
  let alice: Firestore, bob: Firestore, cara: Firestore, admin: Firestore, anon: Firestore;
  const db = (ctx: RulesTestContext) => ctx.firestore() as unknown as Firestore;

  before(async () => {
    setLogLevel('error');
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules: readFileSync(rulesFile('firestore.production.rules'), 'utf8') },
    });
    alice = db(env.authenticatedContext('alice'));
    bob = db(env.authenticatedContext('bob'));
    cara = db(env.authenticatedContext('cara'));
    admin = db(env.authenticatedContext('admin-1', { admin: true }));
    anon = db(env.unauthenticatedContext());
  });

  after(async () => {
    await env.clearFirestore();
    await env.cleanup();
  });

  /** Seeds `docs` — and admin-1's live admins doc (Phase 10: the claim alone is not admin). */
  async function seed(docs: Record<string, DocumentData>): Promise<void> {
    await env.withSecurityRulesDisabled(async (ctx) => {
      for (const [path, data] of Object.entries({ 'admins/admin-1': { role: 'super', name: 'Admin' }, ...docs })) {
        await setDoc(doc(db(ctx), path), data);
      }
    });
  }

  // ── reviews ──────────────────────────────────────────────────────────────
  describe('products/{id}/reviews', () => {
    /** Exactly what ReviewsRepository.submit writes. */
    const review = (over: DocumentData = {}): DocumentData => ({
      productId: 'p1',
      userId: 'alice',
      userName: 'Alice',
      storeId: 'store-a',
      rating: 5,
      text: 'Beautiful, arrived on time.',
      images: ['https://firebasestorage.googleapis.com/v0/b/x/o/reviews%2Falice%2Fo-del_p1%2F1.jpg?alt=media&token=t'],
      orderId: 'o-del',
      isApproved: false,
      createdAt: serverTimestamp(),
      ...over,
    });
    const at = (f: Firestore, id: string, productId = 'p1') => doc(f, `products/${productId}/reviews/${id}`);
    const stored = (over: DocumentData = {}) => ({ ...review(over), createdAt: Timestamp.now() });

    beforeEach(async () => {
      await env.clearFirestore();
      await seed({
        'products/p1': { title: 'Mug', storeId: 'store-a', isActive: true },
        'products/p2': { title: 'Frame', storeId: 'store-a', isActive: true },
        'orders/o-del': { userId: 'alice', status: 'delivered', productIds: ['p1'], storeIds: ['store-a'] },
        'orders/o-pend': { userId: 'alice', status: 'outForDelivery', productIds: ['p1'], storeIds: ['store-a'] },
        'orders/o-bob': { userId: 'bob', status: 'delivered', productIds: ['p1'], storeIds: ['store-a'] },
        'orders/o-old': { userId: 'alice', status: 'delivered', storeIds: ['store-a'] },
      });
    });

    test('the customer reviews a product of their delivered order', () => allowed(setDoc(at(alice, 'o-del_alice'), review())));

    test('the minimal review (no text, no photos) is fine too', () =>
      allowed(setDoc(at(alice, 'o-del_alice'), review({ text: '', images: [] }))));

    test('refused: wrong doc id, not delivered, not theirs, product not in the order, old order', async () => {
      await denied(setDoc(at(alice, 'o-del_bob'), review()));
      await denied(setDoc(at(alice, 'x_alice'), review()));
      await denied(setDoc(at(alice, 'o-pend_alice'), review({ orderId: 'o-pend' })));
      await denied(setDoc(at(alice, 'o-bob_alice'), review({ orderId: 'o-bob' })));
      await denied(setDoc(at(alice, 'o-del_alice', 'p2'), review({ productId: 'p2' })));
      await denied(setDoc(at(alice, 'o-old_alice'), review({ orderId: 'o-old' })));
      await denied(setDoc(at(alice, 'missing_alice'), review({ orderId: 'missing' })));
      await denied(setDoc(at(anon, 'o-del_alice'), review()));
      await denied(setDoc(at(bob, 'o-del_bob'), review({ userId: 'bob' })));
    });

    test('refused: approved by its author, bad rating, other store, extra keys, too much text or photos', async () => {
      await denied(setDoc(at(alice, 'o-del_alice'), review({ isApproved: true })));
      for (const rating of [0, 6, 4.5, '5']) await denied(setDoc(at(alice, 'o-del_alice'), review({ rating })));
      await denied(setDoc(at(alice, 'o-del_alice'), review({ storeId: 'store-b' })));
      await denied(setDoc(at(alice, 'o-del_alice'), review({ ratingAvg: 5 })));
      await denied(setDoc(at(alice, 'o-del_alice'), review({ moderatedBy: 'alice' })));
      await denied(setDoc(at(alice, 'o-del_alice'), review({ text: 'x'.repeat(1001) })));
      await denied(setDoc(at(alice, 'o-del_alice'), review({ images: ['a', 'b', 'c', 'd'] })));
      await denied(setDoc(at(alice, 'o-del_alice'), review({ createdAt: Timestamp.fromMillis(0) })));
      const noStore = review();
      delete noStore.storeId;
      await denied(setDoc(at(alice, 'o-del_alice'), noStore));
    });

    test('editing sends it back to moderation; only the author edits', async () => {
      await seed({ 'products/p1/reviews/o-del_alice': stored({ isApproved: true, moderatedBy: 'admin-1', moderatedAt: Timestamp.now() }) });
      await allowed(setDoc(at(alice, 'o-del_alice'), review({ rating: 3, text: 'Changed my mind' })));
      await denied(setDoc(at(alice, 'o-del_alice'), review({ rating: 3, isApproved: true })));
      await denied(updateDoc(at(alice, 'o-del_alice'), { isApproved: true }));
      await denied(setDoc(at(bob, 'o-del_alice'), review({ userId: 'bob' })));
      await denied(deleteDoc(at(alice, 'o-del_alice')));
      await denied(deleteDoc(at(admin, 'o-del_alice')));
    });

    test('admins approve / hide: isApproved + moderatedBy (own uid) + moderatedAt only', async () => {
      await seed({ 'products/p1/reviews/o-del_alice': stored() });
      await allowed(updateDoc(at(admin, 'o-del_alice'), { isApproved: true, moderatedBy: 'admin-1', moderatedAt: serverTimestamp() }));
      await allowed(updateDoc(at(admin, 'o-del_alice'), { isApproved: false, moderatedBy: 'admin-1', moderatedAt: serverTimestamp() }));
      await denied(updateDoc(at(admin, 'o-del_alice'), { isApproved: true, moderatedBy: 'someone-else', moderatedAt: serverTimestamp() }));
      await denied(updateDoc(at(admin, 'o-del_alice'), { isApproved: true, moderatedBy: 'admin-1', moderatedAt: Timestamp.fromMillis(0) }));
      await denied(updateDoc(at(admin, 'o-del_alice'), { isApproved: 'yes', moderatedBy: 'admin-1', moderatedAt: serverTimestamp() }));
      await denied(updateDoc(at(admin, 'o-del_alice'), { rating: 1, moderatedBy: 'admin-1', moderatedAt: serverTimestamp() }));
      await denied(updateDoc(at(bob, 'o-del_alice'), { isApproved: true, moderatedBy: 'bob', moderatedAt: serverTimestamp() }));
    });

    test('reads: approved for everyone (filtered queries), pending for the author and admins', async () => {
      await seed({
        'products/p1/reviews/o-del_alice': stored({ isApproved: true }),
        'products/p1/reviews/o-bob_bob': stored({ userId: 'bob', orderId: 'o-bob', isApproved: false }),
      });
      await allowed(getDoc(at(anon, 'o-del_alice')));
      await denied(getDoc(at(anon, 'o-bob_bob')));
      await denied(getDoc(at(alice, 'o-bob_bob')));
      await allowed(getDoc(at(bob, 'o-bob_bob')));
      await allowed(getDoc(at(admin, 'o-bob_bob')));
      // "My review" lookup of a review that does not exist yet.
      await allowed(getDoc(at(alice, 'o-pend_alice')));
      // ReviewsRepository.watchApproved.
      await allowed(getDocs(query(collection(anon, 'products/p1/reviews'), where('isApproved', '==', true), orderBy('createdAt', 'desc'))));
      await denied(getDocs(collection(anon, 'products/p1/reviews')));
      await denied(getDocs(query(collection(alice, 'products/p1/reviews'), where('isApproved', '==', false))));
    });

    test('collection group: admins see the whole queue; others only approved reviews', async () => {
      await seed({
        'products/p1/reviews/o-del_alice': stored({ isApproved: true }),
        'products/p1/reviews/o-bob_bob': stored({ userId: 'bob', orderId: 'o-bob' }),
      });
      await allowed(getDocs(query(collectionGroup(admin, 'reviews'), orderBy('createdAt', 'desc'))));
      await allowed(getDocs(query(collectionGroup(admin, 'reviews'), where('isApproved', '==', false), orderBy('createdAt', 'desc'))));
      await allowed(getCountFromServer(query(collectionGroup(admin, 'reviews'), where('storeId', '==', 'store-a'))));
      await allowed(getDocs(query(collectionGroup(anon, 'reviews'), where('isApproved', '==', true))));
      await denied(getDocs(collectionGroup(alice, 'reviews')));
      await denied(getDocs(query(collectionGroup(alice, 'reviews'), where('isApproved', '==', false))));
    });
  });

  // ── Secret Santa ─────────────────────────────────────────────────────────
  describe('secret_santa_groups', () => {
    /** Exactly what SecretSantaRepository.create writes. */
    const group = (over: DocumentData = {}): DocumentData => ({
      name: 'Family 2026',
      type: 'family',
      budget: 25000,
      exchangeDate: Timestamp.fromMillis(Date.UTC(2026, 11, 24)),
      organiserUid: 'alice',
      status: 'open',
      inviteCode: 'ABCD2345',
      memberUids: ['alice'],
      createdAt: serverTimestamp(),
      ...over,
    });
    const organiserMember = (over: DocumentData = {}) => ({ name: 'Alice', phone: '7501234567', joinedAt: serverTimestamp(), ...over });

    async function create(f: Firestore, id: string, g: DocumentData, member: DocumentData | null, memberUid = 'alice') {
      const batch = writeBatch(f);
      batch.set(doc(f, `secret_santa_groups/${id}`), g);
      if (member !== null) batch.set(doc(f, `secret_santa_groups/${id}/members/${memberUid}`), member);
      return batch.commit();
    }

    /** g1: alice organises, bob is a member; cara is not. */
    beforeEach(async () => {
      await env.clearFirestore();
      await seed({
        'secret_santa_groups/g1': { ...group({ memberUids: ['alice', 'bob'] }), createdAt: Timestamp.now() },
        'secret_santa_groups/g1/members/alice': { name: 'Alice', phone: null, joinedAt: Timestamp.now() },
        'secret_santa_groups/g1/members/bob': { name: 'Bob', phone: null, joinedAt: Timestamp.now(), wishlistNote: null },
        'secret_santa_groups/drawn': { ...group({ status: 'drawn', memberUids: ['alice', 'bob', 'cara'] }), createdAt: Timestamp.now() },
        'secret_santa_groups/drawn/members/bob': { name: 'Bob', phone: null, joinedAt: Timestamp.now() },
        'secret_santa_groups/drawn/assignments/alice': { assigneeUid: 'bob', assigneeName: 'Bob', assigneeWishlistNote: null, drawnAt: Timestamp.now() },
        'secret_santa_groups/drawn/assignments/bob': { assigneeUid: 'cara', assigneeName: 'Cara', assigneeWishlistNote: null, drawnAt: Timestamp.now() },
      });
    });

    test('the organiser creates the group and their member doc in one batch', () => allowed(create(alice, 'new', group(), organiserMember())));

    test('create refused: other members, other organiser, not open, bad code / type / budget, extra keys, alone', async () => {
      await denied(create(alice, 'n1', group({ memberUids: ['alice', 'bob'] }), organiserMember()));
      await denied(create(alice, 'n2', group({ organiserUid: 'bob' }), organiserMember()));
      await denied(create(alice, 'n3', group({ status: 'drawn' }), organiserMember()));
      await denied(create(alice, 'n4', group({ inviteCode: 'ABCD234O' }), organiserMember()));
      await denied(create(alice, 'n5', group({ inviteCode: 'ABCD234' }), organiserMember()));
      await denied(create(alice, 'n6', group({ type: 'school' }), organiserMember()));
      await denied(create(alice, 'n7', group({ budget: -1 }), organiserMember()));
      await denied(create(alice, 'n8', group({ drawnAt: null }), organiserMember()));
      await denied(create(alice, 'n9', group(), organiserMember({ exclusions: [] })));
      await denied(create(anon, 'n10', group(), null));
      // The member doc without its group, or someone adding themselves to an existing group.
      await denied(setDoc(doc(alice, 'secret_santa_groups/n11/members/alice'), organiserMember()));
      await denied(setDoc(doc(cara, 'secret_santa_groups/g1/members/cara'), organiserMember({ name: 'Cara' })));
      await denied(updateDoc(doc(cara, 'secret_santa_groups/g1'), { memberUids: ['alice', 'bob', 'cara'] }));
    });

    test('members read the group and the member list; others do not', async () => {
      await allowed(getDoc(doc(alice, 'secret_santa_groups/g1')));
      await allowed(getDoc(doc(bob, 'secret_santa_groups/g1')));
      await allowed(getDocs(collection(bob, 'secret_santa_groups/g1/members')));
      await allowed(getDocs(query(collection(bob, 'secret_santa_groups'), where('memberUids', 'array-contains', 'bob'))));
      await denied(getDoc(doc(cara, 'secret_santa_groups/g1')));
      await denied(getDocs(collection(cara, 'secret_santa_groups/g1/members')));
      await denied(getDocs(collection(cara, 'secret_santa_groups')));
      await denied(getDoc(doc(anon, 'secret_santa_groups/g1')));
      await denied(getDocs(query(collection(cara, 'secret_santa_groups'), where('inviteCode', '==', 'ABCD2345'))));
    });

    test('assignments: each giver reads only their own; nobody writes', async () => {
      await allowed(getDoc(doc(alice, 'secret_santa_groups/drawn/assignments/alice')));
      await allowed(getDoc(doc(cara, 'secret_santa_groups/drawn/assignments/cara'))); // not written (yet): still only their own
      await denied(getDoc(doc(alice, 'secret_santa_groups/drawn/assignments/bob')));
      await denied(getDocs(collection(alice, 'secret_santa_groups/drawn/assignments')));
      await denied(setDoc(doc(alice, 'secret_santa_groups/drawn/assignments/alice'), { assigneeUid: 'cara' }));
      await denied(setDoc(doc(admin, 'secret_santa_groups/drawn/assignments/alice'), { assigneeUid: 'cara' }));
      await denied(deleteDoc(doc(alice, 'secret_santa_groups/drawn/assignments/alice')));
    });

    test('admins read groups, members and assignments (lists and counts)', async () => {
      await allowed(getDocs(query(collection(admin, 'secret_santa_groups'), where('status', '==', 'drawn'), orderBy('createdAt', 'desc'))));
      await allowed(getDocs(collection(admin, 'secret_santa_groups/g1/members')));
      await allowed(getCountFromServer(collection(admin, 'secret_santa_groups/drawn/assignments')));
      await allowed(getDocs(collection(admin, 'secret_santa_groups/drawn/assignments')));
      await denied(updateDoc(doc(admin, 'secret_santa_groups/g1'), { status: 'closed' }));
    });

    test('members edit their own wish note; the organiser edits the group and exclusions while open', async () => {
      await allowed(updateDoc(doc(bob, 'secret_santa_groups/g1/members/bob'), { wishlistNote: 'Books, please' }));
      await allowed(updateDoc(doc(bob, 'secret_santa_groups/g1/members/bob'), { wishlistNote: null }));
      await denied(updateDoc(doc(bob, 'secret_santa_groups/g1/members/bob'), { name: 'Robert' }));
      await denied(updateDoc(doc(bob, 'secret_santa_groups/g1/members/bob'), { wishlistNote: 'x'.repeat(601) }));
      await denied(updateDoc(doc(alice, 'secret_santa_groups/g1/members/bob'), { wishlistNote: 'Socks' }));

      await allowed(updateDoc(doc(alice, 'secret_santa_groups/g1/members/bob'), { exclusions: ['alice'] }));
      await denied(updateDoc(doc(bob, 'secret_santa_groups/g1/members/alice'), { exclusions: ['bob'] }));
      await allowed(updateDoc(doc(alice, 'secret_santa_groups/g1'), { name: 'Family Xmas', budget: 30000, updatedAt: serverTimestamp() }));
      await denied(updateDoc(doc(alice, 'secret_santa_groups/g1'), { status: 'drawn' }));
      await denied(updateDoc(doc(alice, 'secret_santa_groups/g1'), { memberUids: ['alice'] }));
      await denied(updateDoc(doc(alice, 'secret_santa_groups/g1'), { inviteCode: 'ZZZZ2345' }));
      await denied(updateDoc(doc(bob, 'secret_santa_groups/g1'), { name: 'Mine now' }));
      // After the draw.
      await denied(updateDoc(doc(alice, 'secret_santa_groups/drawn'), { budget: 1 }));
      await denied(updateDoc(doc(alice, 'secret_santa_groups/drawn/members/bob'), { exclusions: [] }));
      await denied(deleteDoc(doc(alice, 'secret_santa_groups/g1')));
    });
  });

  // ── ai_searches, payment_sessions ───────────────────────────────────────
  describe('ai_searches / payment_sessions', () => {
    beforeEach(async () => {
      await env.clearFirestore();
      await seed({
        'ai_searches/s1': { userId: 'alice', query: 'gift for mum', locale: 'en', resultProductIds: [], latencyMs: 900, at: Timestamp.now(), model: 'vertex:x' },
        'payment_sessions/ps1': { uid: 'alice', purpose: 'order', orderId: 'o1', amount: 25000, gateway: 'zainCash', status: 'pending', gatewayTxnId: 't1', createdAt: Timestamp.now(), updatedAt: Timestamp.now() },
      });
    });

    test('ai_searches: admins read (count of today); customers never', async () => {
      await allowed(getCountFromServer(query(collection(admin, 'ai_searches'), where('at', '>=', Timestamp.fromMillis(0)))));
      await allowed(getDoc(doc(admin, 'ai_searches/s1')));
      await denied(getDoc(doc(alice, 'ai_searches/s1')));
      await denied(getDocs(query(collection(alice, 'ai_searches'), where('userId', '==', 'alice'))));
      await denied(setDoc(doc(alice, 'ai_searches/s2'), { userId: 'alice', query: 'x' }));
      await denied(setDoc(doc(admin, 'ai_searches/s2'), { query: 'x' }));
    });

    test('payment_sessions: the owner (and admins) read; nobody writes', async () => {
      await allowed(getDoc(doc(alice, 'payment_sessions/ps1')));
      await allowed(getDocs(query(collection(alice, 'payment_sessions'), where('uid', '==', 'alice'))));
      await allowed(getDoc(doc(admin, 'payment_sessions/ps1')));
      await denied(getDoc(doc(bob, 'payment_sessions/ps1')));
      await denied(getDocs(collection(bob, 'payment_sessions')));
      await denied(updateDoc(doc(alice, 'payment_sessions/ps1'), { status: 'paid' }));
      await denied(setDoc(doc(alice, 'payment_sessions/ps2'), { uid: 'alice', status: 'paid', amount: 1 }));
      await denied(updateDoc(doc(admin, 'payment_sessions/ps1'), { status: 'paid' }));
    });
  });
});
