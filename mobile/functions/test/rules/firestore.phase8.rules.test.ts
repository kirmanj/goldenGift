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
  deleteDoc,
  deleteField,
  doc,
  documentId,
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
 * Phase 8 parts of mobile/firestore.production.rules: gift_cards, special_requests
 * (+ messages), stores (+ private), sellers on products / orders / audit log.
 * Own project id (rules and data are per project in the Firestore emulator), so it
 * runs in parallel with firestore.rules.test.ts without either clearing the other.
 */
const PROJECT_ID = 'demo-goldengift-rules-phase8';

describe('firestore.production.rules — Phase 8', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  let env: RulesTestEnvironment;
  let alice: Firestore, bob: Firestore, admin: Firestore, anon: Firestore;
  /** Partners: claim `seller == storeId` (never `admin`). */
  let sellerA: Firestore, sellerS: Firestore, ownerP: Firestore;
  const db = (ctx: RulesTestContext) => ctx.firestore() as unknown as Firestore;

  before(async () => {
    setLogLevel('error');
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules: readFileSync(rulesFile('firestore.production.rules'), 'utf8') },
    });
    alice = db(env.authenticatedContext('alice'));
    bob = db(env.authenticatedContext('bob'));
    admin = db(env.authenticatedContext('admin-1', { admin: true }));
    anon = db(env.unauthenticatedContext());
    sellerA = db(env.authenticatedContext('seller-a', { seller: 'store-a' }));
    sellerS = db(env.authenticatedContext('seller-s', { seller: 'store-s' }));
    ownerP = db(env.authenticatedContext('owner-p'));
  });

  after(async () => {
    await env.clearFirestore();
    await env.cleanup();
  });

  const store = (over: DocumentData = {}): DocumentData => ({
    name: 'Store A',
    nameAr: 'متجر',
    description: 'Gifts',
    logoUrl: null,
    coverUrl: null,
    ownerUid: 'seller-a',
    phone: '+9647501234567',
    city: 'erbil',
    status: 'active',
    ratingAvg: 0,
    ratingCount: 0,
    productCount: 0,
    ordersCount: 0,
    commissionPercent: 15,
    createdAt: Timestamp.now(),
    ...over,
  });

  const product = (over: DocumentData = {}): DocumentData => ({
    title: 'Mug',
    storeId: 'store-a',
    categoryIds: ['mugs'],
    images: [],
    price: 15000,
    isActive: true,
    isFeatured: false,
    salesCount: 0,
    viewCount: 0,
    ratingAvg: 0,
    ratingCount: 0,
    ...over,
  });

  const line = (storeId: string, status = 'pending') => ({
    id: `l-${storeId}`,
    productId: `p-${storeId}`,
    storeId,
    titleSnapshot: 'Item',
    unitPrice: 1000,
    qty: 1,
    selections: [],
    lineTotal: 1000,
    status,
  });

  const order = (over: DocumentData = {}): DocumentData => ({
    orderNumber: 'GG-2610-00001',
    userId: 'alice',
    storeIds: ['store-a', 'store-b'],
    items: [line('store-a'), line('store-b')],
    status: 'pending',
    total: 2000,
    createdAt: Timestamp.now(),
    ...over,
  });

  const giftCard = (over: DocumentData = {}): DocumentData => ({
    code: 'ABCDEFGHJKLM',
    templateId: 't1',
    amount: 25000,
    balance: 25000,
    purchaserUid: 'alice',
    recipientName: 'Bob',
    recipientPhone: '+9647701234567',
    recipientUid: 'bob',
    status: 'sent',
    orderId: 'o1',
    expiresAt: Timestamp.fromMillis(Date.now() + 86_400_000),
    createdAt: Timestamp.now(),
    ...over,
  });

  const specialRequest = (over: DocumentData = {}): DocumentData => ({
    userId: 'alice',
    type: 'gift',
    text: 'A wooden box with our names',
    images: [],
    status: 'submitted',
    customerName: 'Alice',
    customerPhone: '+9647501234567',
    lastMessageAt: Timestamp.now(),
    lastMessageBy: 'customer',
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...over,
  });

  const audit = (adminUid: string, action: string, target: string): DocumentData => ({
    adminUid,
    action,
    target,
    before: null,
    after: { x: 1 },
    at: serverTimestamp(),
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = db(ctx);
      const seed: Array<[string, DocumentData]> = [
        ['stores/store-a', store()],
        ['stores/store-a/private/payout', { ownerUid: 'seller-a', iban: 'IQ00' }],
        ['stores/store-b', store({ name: 'Store B', ownerUid: 'seller-b' })],
        ['stores/store-s', store({ name: 'Suspended', ownerUid: 'seller-s', status: 'suspended' })],
        ['stores/store-p', store({ name: 'Pending', ownerUid: 'owner-p', status: 'pendingApproval', commissionPercent: 0 })],
        ['stores/store-p/private/application', { ownerUid: 'owner-p', ownerName: 'Pat', phone: '+9647501112233' }],
        ['stores/store-x/private/application', { ownerUid: 'owner-x', rejectedAt: Timestamp.now(), rejectReason: 'No photos' }],
        ['products/pa', product({ salesCount: 3, ratingAvg: 4.5, ratingCount: 2 })],
        ['products/pb', product({ storeId: 'store-b' })],
        ['products/ps', product({ storeId: 'store-s' })],
        ['orders/o-ab', order()],
        ['orders/o-ab/status_history/h1', { status: 'pending', byUid: 'alice', byRole: 'customer', note: null, at: Timestamp.now() }],
        ['orders/o-b', order({ userId: 'bob', storeIds: ['store-b'], items: [line('store-b')] })],
        ['orders/o-b/status_history/h1', { status: 'pending', byUid: 'bob', byRole: 'customer', note: null, at: Timestamp.now() }],
        ['admins/seller-a', { role: 'seller', storeId: 'store-a', name: 'Seller A' }],
        ['admins/admin-1', { role: 'super', name: 'Admin' }],
        ['gift_card_templates/t1', { name: 'Eid', presetAmounts: [25000] }],
        ['gift_cards/gc1', giftCard()],
        ['gift_cards/gc2', giftCard({ purchaserUid: 'carol', recipientUid: null, code: 'ZZZZZZZZZZZZ' })],
        ['gift_cards/gc-redeemed', giftCard({ status: 'redeemed', balance: 0 })],
        ['special_requests/sr1', specialRequest()],
        ['special_requests/sr1/messages/m1', { senderUid: 'alice', role: 'customer', text: 'Hi', images: [], at: Timestamp.now() }],
        ['special_requests/sr-bob', specialRequest({ userId: 'bob' })],
      ];
      for (const [path, data] of seed) await setDoc(doc(d, path), data);
    });
  });

  // ── gift_cards ───────────────────────────────────────────────────────────
  describe('gift_cards', () => {
    test('the purchaser and the recipient read the card and list theirs', async () => {
      await allowed(getDoc(doc(alice, 'gift_cards/gc1')));
      await allowed(getDoc(doc(bob, 'gift_cards/gc1')));
      await allowed(getDocs(query(collection(alice, 'gift_cards'), where('purchaserUid', '==', 'alice'))));
      await allowed(getDocs(query(collection(bob, 'gift_cards'), where('recipientUid', '==', 'bob'))));
    });
    test('nobody else reads; no unfiltered or foreign lists', async () => {
      await denied(getDoc(doc(alice, 'gift_cards/gc2')));
      await denied(getDoc(doc(anon, 'gift_cards/gc1')));
      await denied(getDoc(doc(sellerA, 'gift_cards/gc1')));
      await denied(getDocs(collection(alice, 'gift_cards')));
      await denied(getDocs(query(collection(alice, 'gift_cards'), where('recipientUid', '==', 'bob'))));
      await denied(getDocs(query(collection(alice, 'gift_cards'), where('code', '==', 'ZZZZZZZZZZZZ'))));
    });
    test('admins read and list every card', async () => {
      await allowed(getDoc(doc(admin, 'gift_cards/gc2')));
      await allowed(getDocs(query(collection(admin, 'gift_cards'), where('status', '==', 'sent'), orderBy('createdAt', 'desc'))));
    });
    test('no client creates or deletes cards', async () => {
      await denied(setDoc(doc(alice, 'gift_cards/new'), giftCard()));
      await denied(setDoc(doc(admin, 'gift_cards/new'), giftCard()));
      await denied(deleteDoc(doc(admin, 'gift_cards/gc1')));
      await denied(deleteDoc(doc(alice, 'gift_cards/gc1')));
    });

    /** Exactly what GiftCardsAdminRepository.disableCard writes. */
    const disable = (over: DocumentData = {}): DocumentData => ({
      status: 'disabled',
      disabledReason: 'Lost card',
      disabledBy: 'admin-1',
      disabledAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...over,
    });
    test("an admin disables a sent card the dashboard's way, with its audit entry", async () => {
      const batch = writeBatch(admin);
      batch.update(doc(admin, 'gift_cards/gc1'), disable());
      batch.set(doc(collection(admin, 'admin_audit_log')), audit('admin-1', 'giftCard.disable', 'gift_cards/gc1'));
      await allowed(batch.commit());
    });
    for (const [label, path, data] of [
      ['a redeemed card', 'gift_cards/gc-redeemed', disable()],
      ['another admin as disabledBy', 'gift_cards/gc1', disable({ disabledBy: 'admin-2' })],
      ['a reason under 3 characters', 'gift_cards/gc1', disable({ disabledReason: 'no' })],
      ['a balance change', 'gift_cards/gc1', disable({ balance: 0 })],
      ['a status other than disabled', 'gift_cards/gc1', disable({ status: 'redeemed' })],
      ['a client-side disabledAt', 'gift_cards/gc1', disable({ disabledAt: Timestamp.now() })],
      ['a new recipient', 'gift_cards/gc1', { recipientUid: 'alice', updatedAt: serverTimestamp() }],
    ] as Array<[string, string, DocumentData]>) {
      test(`admin denied: ${label}`, () => denied(updateDoc(doc(admin, path), data)));
    }
    test('customers never update a card', async () => {
      await denied(updateDoc(doc(alice, 'gift_cards/gc1'), disable({ disabledBy: 'alice' })));
      await denied(updateDoc(doc(bob, 'gift_cards/gc1'), { status: 'redeemed', balance: 0 }));
    });
  });

  // ── special_requests ─────────────────────────────────────────────────────
  describe('special_requests', () => {
    /** Exactly what SpecialRequestsRepository.create writes. */
    const created = (over: DocumentData = {}): DocumentData => ({
      userId: 'alice',
      type: 'gift',
      text: 'A wooden box with our names',
      images: ['https://storage/special_requests/alice/r/1.jpg'],
      status: 'submitted',
      customerName: 'Alice',
      customerPhone: '+9647501234567',
      lastMessageAt: serverTimestamp(),
      lastMessageBy: 'customer',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...over,
    });
    test('the owner creates a request exactly as the app writes it', async () => {
      await allowed(setDoc(doc(alice, 'special_requests/new-1'), created()));
      await allowed(setDoc(doc(alice, 'special_requests/new-2'), created({ type: 'support', images: [], customerName: null, customerPhone: null })));
    });
    for (const [label, data] of [
      ['another userId', created({ userId: 'bob' })],
      ['status quoted', created({ status: 'quoted' })],
      ['a quote', created({ quoteAmount: 1000 })],
      ['an orderId', created({ orderId: 'o1' })],
      ['lastMessageBy admin', created({ lastMessageBy: 'admin' })],
      ['an unknown type', created({ type: 'complaint' })],
      ['empty text', created({ text: '' })],
      ['a 4001-character text', created({ text: 'x'.repeat(4001) })],
      ['6 images', created({ images: ['a', 'b', 'c', 'd', 'e', 'f'] })],
      ['a client-side createdAt', created({ createdAt: Timestamp.now() })],
    ] as Array<[string, DocumentData]>) {
      test(`create denied: ${label}`, () => denied(setDoc(doc(alice, 'special_requests/new-x'), data)));
    }
    test('signed out cannot create', () => denied(setDoc(doc(anon, 'special_requests/new-x'), created({ userId: null }))));

    test('the owner reads and lists their own; nobody else', async () => {
      await allowed(getDoc(doc(alice, 'special_requests/sr1')));
      await allowed(getDocs(query(collection(alice, 'special_requests'), where('userId', '==', 'alice'), orderBy('createdAt', 'desc'))));
      await denied(getDoc(doc(bob, 'special_requests/sr1')));
      await denied(getDoc(doc(anon, 'special_requests/sr1')));
      await denied(getDocs(collection(alice, 'special_requests')));
      await denied(getDocs(query(collection(alice, 'special_requests'), where('userId', '==', 'bob'))));
    });
    test('admins read and list the inbox', async () => {
      await allowed(getDoc(doc(admin, 'special_requests/sr-bob')));
      await allowed(getDocs(query(collection(admin, 'special_requests'), where('status', '==', 'submitted'), orderBy('lastMessageAt', 'desc'))));
    });

    /** SpecialRequestsRepository.sendMessage: message + markers in one batch. */
    const customerMessage = (fs: Firestore, requestId: string, over: DocumentData = {}, markers: DocumentData = {}) => {
      const batch = writeBatch(fs);
      batch.set(doc(collection(fs, `special_requests/${requestId}/messages`)), {
        senderUid: 'alice',
        role: 'customer',
        text: 'Any news?',
        images: [],
        at: serverTimestamp(),
        ...over,
      });
      batch.update(doc(fs, `special_requests/${requestId}`), {
        lastMessageAt: serverTimestamp(),
        lastMessageBy: 'customer',
        updatedAt: serverTimestamp(),
        ...markers,
      });
      return batch.commit();
    };
    test('the owner posts a message and bumps the markers', () => allowed(customerMessage(alice, 'sr1')));
    test('customer messages: own role and uid, own request only', async () => {
      await denied(customerMessage(alice, 'sr1', { role: 'admin' }));
      await denied(customerMessage(alice, 'sr1', { senderUid: 'bob' }));
      await denied(customerMessage(alice, 'sr1', { text: '' }));
      await denied(customerMessage(alice, 'sr1', { at: Timestamp.now() }));
      await denied(customerMessage(alice, 'sr1', {}, { lastMessageBy: 'admin' }));
      await denied(customerMessage(alice, 'sr-bob'));
    });
    test('the owner never changes status, quote or order', async () => {
      await denied(updateDoc(doc(alice, 'special_requests/sr1'), { status: 'accepted', updatedAt: serverTimestamp() }));
      await denied(updateDoc(doc(alice, 'special_requests/sr1'), { quoteAmount: 1 }));
      await denied(updateDoc(doc(alice, 'special_requests/sr1'), { orderId: 'o1' }));
      await denied(updateDoc(doc(alice, 'special_requests/sr1'), { text: 'changed' }));
      await denied(deleteDoc(doc(alice, 'special_requests/sr1')));
    });

    const adminMessage = (over: DocumentData = {}) => ({
      senderUid: 'admin-1',
      role: 'admin',
      text: 'We are on it',
      images: [],
      at: serverTimestamp(),
      ...over,
    });
    test('an admin replies (message + markers + inReview + audit in one batch)', async () => {
      const batch = writeBatch(admin);
      batch.set(doc(collection(admin, 'special_requests/sr1/messages')), adminMessage());
      batch.update(doc(admin, 'special_requests/sr1'), {
        lastMessageAt: serverTimestamp(),
        lastMessageBy: 'admin',
        updatedAt: serverTimestamp(),
        status: 'inReview',
      });
      batch.set(doc(collection(admin, 'admin_audit_log')), audit('admin-1', 'specialRequest.reply', 'special_requests/sr1'));
      await allowed(batch.commit());
    });
    test('an admin sends a quote, then withdraws it', async () => {
      const quote = writeBatch(admin);
      quote.set(doc(collection(admin, 'special_requests/sr1/messages')), adminMessage({ text: 'Quote: 30,000 IQD' }));
      quote.update(doc(admin, 'special_requests/sr1'), {
        lastMessageAt: serverTimestamp(),
        lastMessageBy: 'admin',
        updatedAt: serverTimestamp(),
        status: 'quoted',
        quoteAmount: 30000,
        quoteNote: null,
        quotedBy: 'admin-1',
        quotedAt: serverTimestamp(),
      });
      await allowed(quote.commit());
      await allowed(
        updateDoc(doc(admin, 'special_requests/sr1'), {
          status: 'inReview',
          quoteAmount: deleteField(),
          quoteNote: deleteField(),
          lastMessageAt: serverTimestamp(),
          lastMessageBy: 'admin',
          updatedAt: serverTimestamp(),
        }),
      );
      await allowed(updateDoc(doc(admin, 'special_requests/sr1'), { assignedAdminUid: 'admin-1', updatedAt: serverTimestamp() }));
      await allowed(updateDoc(doc(admin, 'special_requests/sr1'), { status: 'rejected', rejectReason: 'Not possible', updatedAt: serverTimestamp() }));
    });
    for (const [label, data] of [
      ['status accepted (acceptQuote only)', { status: 'accepted', updatedAt: serverTimestamp() }],
      ['an orderId', { orderId: 'o1' }],
      ['a new text', { text: 'x' }],
      ['an unknown status', { status: 'lost' }],
      ['quotedBy someone else', { status: 'quoted', quoteAmount: 1000, quotedBy: 'admin-2', quotedAt: serverTimestamp() }],
      ['a fractional quote', { status: 'quoted', quoteAmount: 10.5 }],
      ['lastMessageBy other than admin', { lastMessageBy: 'system' }],
    ] as Array<[string, DocumentData]>) {
      test(`admin update denied: ${label}`, () => denied(updateDoc(doc(admin, 'special_requests/sr1'), data)));
    }
    test('admin messages: role admin in their own name only', async () => {
      await allowed(setDoc(doc(admin, 'special_requests/sr1/messages/a1'), adminMessage()));
      await denied(setDoc(doc(admin, 'special_requests/sr1/messages/a2'), adminMessage({ role: 'customer' })));
      await denied(setDoc(doc(admin, 'special_requests/sr1/messages/a3'), adminMessage({ senderUid: 'admin-2' })));
      await denied(setDoc(doc(admin, 'special_requests/sr1/messages/a4'), adminMessage({ system: true })));
    });
    test('messages: owner and admins read; nobody edits or deletes', async () => {
      await allowed(getDocs(query(collection(alice, 'special_requests/sr1/messages'), orderBy('at'))));
      await allowed(getDocs(collection(admin, 'special_requests/sr1/messages')));
      await denied(getDocs(collection(bob, 'special_requests/sr1/messages')));
      await denied(getDocs(collection(anon, 'special_requests/sr1/messages')));
      await denied(updateDoc(doc(alice, 'special_requests/sr1/messages/m1'), { text: 'edited' }));
      await denied(updateDoc(doc(admin, 'special_requests/sr1/messages/m1'), { text: 'edited' }));
      await denied(deleteDoc(doc(admin, 'special_requests/sr1/messages/m1')));
    });
  });

  // ── stores ───────────────────────────────────────────────────────────────
  describe('stores', () => {
    test('live stores (active, suspended) are public', async () => {
      await allowed(getDoc(doc(anon, 'stores/store-a')));
      await allowed(getDoc(doc(anon, 'stores/store-s')));
      await allowed(getDocs(query(collection(anon, 'stores'), where('status', '==', 'active'))));
      await allowed(getDocs(query(collection(anon, 'stores'), where('status', 'in', ['active', 'suspended']))));
    });
    test('a pending application is private to its owner and admins', async () => {
      await denied(getDoc(doc(anon, 'stores/store-p')));
      await denied(getDoc(doc(bob, 'stores/store-p')));
      await denied(getDoc(doc(sellerA, 'stores/store-p')));
      await denied(getDocs(query(collection(anon, 'stores'), where('status', '==', 'pendingApproval'))));
      await denied(getDocs(collection(anon, 'stores')));
      await allowed(getDoc(doc(ownerP, 'stores/store-p')));
      // PartnerRepository.watchMine
      await allowed(getDocs(query(collection(ownerP, 'stores'), where('ownerUid', '==', 'owner-p'))));
      await allowed(getDoc(doc(admin, 'stores/store-p')));
      await allowed(getDocs(query(collection(admin, 'stores'), where('status', '==', 'pendingApproval'))));
      await allowed(getDocs(collection(admin, 'stores')));
    });
    test('a seller reads its own store whatever the status', () => allowed(getDoc(doc(sellerS, 'stores/store-s'))));
    // The cart reads its lines' stores with `documentId in […]`, which the rules
    // check per document: fine for live (and missing) stores, refused when one of
    // them is a pending application — which has no orderable products.
    test('documentId-in lookups (the cart): live and missing stores', async () => {
      await allowed(getDocs(query(collection(anon, 'stores'), where(documentId(), 'in', ['store-a', 'store-s']))));
      await allowed(getDocs(query(collection(alice, 'stores'), where(documentId(), 'in', ['store-a', 'gone']))));
      await denied(getDocs(query(collection(anon, 'stores'), where(documentId(), 'in', ['store-a', 'store-p']))));
    });
    test('a missing store reads as missing, not denied', () => allowed(getDoc(doc(anon, 'stores/gone'))));

    /** StoresAdminRepository.updateProfile: profile changes + store.update audit, one batch. */
    const profileBatch = (fs: Firestore, actor: string, storeId: string, over: DocumentData = {}) => {
      const batch = writeBatch(fs);
      batch.update(doc(fs, `stores/${storeId}`), {
        name: 'Store A+',
        nameAr: deleteField(),
        nameKu: deleteField(),
        description: 'Handmade gifts',
        descriptionAr: deleteField(),
        descriptionKu: deleteField(),
        logoUrl: 'https://storage/stores/x/logo.jpg',
        coverUrl: null,
        phone: '+9647501234567',
        city: 'erbil',
        updatedAt: serverTimestamp(),
        ...over,
      });
      batch.set(doc(collection(fs, 'admin_audit_log')), audit(actor, 'store.update', `stores/${storeId}`));
      return batch.commit();
    };
    test("the seller edits its own store's profile the dashboard's way", () => allowed(profileBatch(sellerA, 'seller-a', 'store-a')));
    test('admins edit the profile and the commission', async () => {
      await allowed(profileBatch(admin, 'admin-1', 'store-b', { commissionPercent: 12.5 }));
      await denied(profileBatch(admin, 'admin-1', 'store-b', { commissionPercent: 51 }));
    });
    for (const [label, fs, actor, storeId, over] of [
      ['seller: commission', () => sellerA, 'seller-a', 'store-a', { commissionPercent: 0 }],
      ['seller: status', () => sellerA, 'seller-a', 'store-a', { status: 'suspended' }],
      ['seller: owner', () => sellerA, 'seller-a', 'store-a', { ownerUid: 'bob' }],
      ['seller: rating', () => sellerA, 'seller-a', 'store-a', { ratingAvg: 5 }],
      ['seller: another store', () => sellerA, 'seller-a', 'store-b', {}],
      ['seller: a suspended store', () => sellerS, 'seller-s', 'store-s', {}],
      ['seller: a 61-character name', () => sellerA, 'seller-a', 'store-a', { name: 'x'.repeat(61) }],
      ['admin: status (setStoreStatus only)', () => admin, 'admin-1', 'store-b', { status: 'suspended' }],
      ['admin: approval (reviewPartner only)', () => admin, 'admin-1', 'store-p', { status: 'active' }],
      ['customer', () => alice, 'alice', 'store-a', {}],
    ] as Array<[string, () => Firestore, string, string, DocumentData]>) {
      test(`store update denied — ${label}`, () => denied(profileBatch(fs(), actor, storeId, over)));
    }
    test('stores are never created or deleted from a client', async () => {
      await denied(setDoc(doc(alice, 'stores/mine'), store({ ownerUid: 'alice', status: 'pendingApproval' })));
      await denied(setDoc(doc(admin, 'stores/new'), store()));
      await denied(deleteDoc(doc(admin, 'stores/store-p')));
      await denied(deleteDoc(doc(sellerA, 'stores/store-a')));
    });

    test('private: owner, seller and admins read; nobody writes', async () => {
      await allowed(getDoc(doc(ownerP, 'stores/store-p/private/application')));
      await allowed(getDoc(doc(sellerA, 'stores/store-a/private/payout')));
      await allowed(getDoc(doc(admin, 'stores/store-p/private/application')));
      await denied(getDoc(doc(bob, 'stores/store-p/private/application')));
      await denied(getDoc(doc(anon, 'stores/store-a/private/payout')));
      await denied(getDoc(doc(sellerA, 'stores/store-p/private/application')));
      await denied(setDoc(doc(admin, 'stores/store-p/private/application'), { approved: true }, { merge: true }));
      await denied(setDoc(doc(sellerA, 'stores/store-a/private/payout'), { iban: 'IQ11' }));
      await denied(setDoc(doc(ownerP, 'stores/store-p/private/application'), { ownerName: 'X' }, { merge: true }));
    });
    test("a rejected application's archive stays readable by its owner and admins", async () => {
      await allowed(getDoc(doc(db(env.authenticatedContext('owner-x')), 'stores/store-x/private/application')));
      await allowed(getDoc(doc(admin, 'stores/store-x/private/application')));
      await denied(getDoc(doc(bob, 'stores/store-x/private/application')));
    });
  });

  // ── sellers on products ──────────────────────────────────────────────────
  describe('products: sellers', () => {
    /** ProductsAdminRepository.save (create): product + derived fields, audit entry. */
    const createBatch = (fs: Firestore, uid: string, id: string, over: DocumentData = {}) => {
      const batch = writeBatch(fs);
      batch.set(doc(fs, `products/${id}`), { ...product(over), createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
      batch.set(doc(collection(fs, 'admin_audit_log')), audit(uid, 'product.create', `products/${id}`));
      return batch.commit();
    };
    const updateBatch = (fs: Firestore, uid: string, id: string, changes: DocumentData) => {
      const batch = writeBatch(fs);
      batch.update(doc(fs, `products/${id}`), { ...changes, updatedAt: serverTimestamp() });
      batch.set(doc(collection(fs, 'admin_audit_log')), audit(uid, 'product.update', `products/${id}`));
      return batch.commit();
    };
    test('a seller creates a product of its own store', () => allowed(createBatch(sellerA, 'seller-a', 'new-a')));
    test('a seller edits its own product (counters untouched)', () =>
      allowed(updateBatch(sellerA, 'seller-a', 'pa', { title: 'Big mug', price: 17000, isActive: false })));
    for (const [label, op] of [
      ['create for another store', () => createBatch(sellerA, 'seller-a', 'new-b', { storeId: 'store-b' })],
      ['create featured', () => createBatch(sellerA, 'seller-a', 'new-f', { isFeatured: true })],
      ['create with sales', () => createBatch(sellerA, 'seller-a', 'new-s', { salesCount: 5 })],
      ['create with a rating', () => createBatch(sellerA, 'seller-a', 'new-r', { ratingAvg: 5, ratingCount: 1 })],
      ['create while suspended', () => createBatch(sellerS, 'seller-s', 'new-x', { storeId: 'store-s' })],
      ['move to another store', () => updateBatch(sellerA, 'seller-a', 'pa', { storeId: 'store-b' })],
      ['feature it', () => updateBatch(sellerA, 'seller-a', 'pa', { isFeatured: true })],
      ['change salesCount', () => updateBatch(sellerA, 'seller-a', 'pa', { salesCount: 99 })],
      ['change viewCount', () => updateBatch(sellerA, 'seller-a', 'pa', { viewCount: 99 })],
      ['change the rating', () => updateBatch(sellerA, 'seller-a', 'pa', { ratingAvg: 5 })],
      ["edit another store's product", () => updateBatch(sellerA, 'seller-a', 'pb', { price: 1 })],
      ['edit while suspended', () => updateBatch(sellerS, 'seller-s', 'ps', { price: 1 })],
      ['delete its product', () => deleteDoc(doc(sellerA, 'products/pa'))],
    ] as Array<[string, () => Promise<unknown>]>) {
      test(`seller denied: ${label}`, () => denied(op()));
    }
    test('customers still cannot write; admins still can', async () => {
      await denied(createBatch(alice, 'alice', 'new-c'));
      await allowed(createBatch(admin, 'admin-1', 'new-adm', { storeId: 'store-b', isFeatured: true }));
      await allowed(updateBatch(admin, 'admin-1', 'pa', { isFeatured: true, storeId: 'store-b' }));
      await allowed(deleteDoc(doc(admin, 'products/pb')));
    });
  });

  // ── sellers on orders ────────────────────────────────────────────────────
  describe('orders: sellers', () => {
    test('a seller reads and lists the orders with its store (and their timelines)', async () => {
      await allowed(getDoc(doc(sellerA, 'orders/o-ab')));
      await allowed(getDocs(query(collection(sellerA, 'orders'), where('storeIds', 'array-contains', 'store-a'))));
      await allowed(
        getDocs(query(collection(sellerA, 'orders'), where('storeIds', 'array-contains', 'store-a'), orderBy('createdAt', 'desc'))),
      );
      await allowed(
        getDocs(query(collection(sellerA, 'orders'), where('storeIds', 'array-contains', 'store-a'), where('status', '==', 'pending'))),
      );
      await allowed(getDocs(collection(sellerA, 'orders/o-ab/status_history')));
    });
    test('but no other order', async () => {
      await denied(getDoc(doc(sellerA, 'orders/o-b')));
      await denied(getDocs(query(collection(sellerA, 'orders'), where('storeIds', 'array-contains', 'store-b'))));
      await denied(getDocs(collection(sellerA, 'orders')));
      await denied(getDocs(collection(sellerA, 'orders/o-b/status_history')));
    });
    test('sellers never write orders (updateOrderItems does)', async () => {
      await denied(
        updateDoc(doc(sellerA, 'orders/o-ab'), {
          status: 'confirmed',
          statusUpdatedBy: 'seller-a',
          statusUpdatedByRole: 'seller',
          items: [line('store-a', 'confirmed'), line('store-b')],
          updatedAt: serverTimestamp(),
        }),
      );
      await denied(setDoc(doc(sellerA, 'orders/o-new'), order()));
      await denied(setDoc(doc(sellerA, 'orders/o-ab/status_history/h2'), { status: 'confirmed' }));
    });
  });

  // ── sellers: admins doc and audit log ────────────────────────────────────
  describe('sellers: admins doc and audit log', () => {
    test('a seller reads its own admins doc only', async () => {
      await allowed(getDoc(doc(sellerA, 'admins/seller-a')));
      await denied(getDoc(doc(sellerA, 'admins/admin-1')));
      await denied(getDocs(collection(sellerA, 'admins')));
    });
    test('a seller appends audit entries for its products and store, in its own name', async () => {
      await allowed(setDoc(doc(sellerA, 'admin_audit_log/s1'), audit('seller-a', 'product.update', 'products/pa')));
      await allowed(setDoc(doc(sellerA, 'admin_audit_log/s2'), audit('seller-a', 'store.update', 'stores/store-a')));
      await denied(setDoc(doc(sellerA, 'admin_audit_log/s3'), audit('seller-a', 'store.update', 'stores/store-b')));
      await denied(setDoc(doc(sellerA, 'admin_audit_log/s4'), audit('seller-a', 'user.block', 'users/bob')));
      await denied(setDoc(doc(sellerA, 'admin_audit_log/s5'), audit('admin-1', 'product.update', 'products/pa')));
      await denied(setDoc(doc(sellerA, 'admin_audit_log/s6'), { ...audit('seller-a', 'product.update', 'products/pa'), at: Timestamp.now() }));
    });
    test('sellers do not read the audit log', () => denied(getDocs(collection(sellerA, 'admin_audit_log'))));
  });
});
