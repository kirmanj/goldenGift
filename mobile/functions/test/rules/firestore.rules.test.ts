import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  initializeTestEnvironment,
  type RulesTestContext,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  arrayRemove,
  arrayUnion,
  collection,
  deleteDoc,
  deleteField,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
  increment,
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
import { RULES_PROJECT_ID, allowed, denied, rulesFile } from './rulesEnv';

/**
 * mobile/firestore.production.rules (not deployed until Phase 10). Uses its own
 * project id: the Firestore emulator keeps rules and data per project, so these
 * tests never touch goldengift-iq (dev rules + seeded data).
 */
describe('firestore.production.rules', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  let env: RulesTestEnvironment;
  /** Signed-in customers alice, bob; an admin (custom claim); a signed-out visitor. */
  let alice: Firestore, bob: Firestore, admin: Firestore, anon: Firestore;
  const db = (ctx: RulesTestContext) => ctx.firestore() as unknown as Firestore;
  const as = (uid: string) => db(env.authenticatedContext(uid));

  before(async () => {
    setLogLevel('error'); // every denied write would otherwise log a PERMISSION_DENIED warning
    env = await initializeTestEnvironment({
      projectId: RULES_PROJECT_ID,
      firestore: { rules: readFileSync(rulesFile('firestore.production.rules'), 'utf8') },
    });
    alice = as('alice');
    bob = as('bob');
    admin = db(env.authenticatedContext('admin-1', { admin: true }));
    anon = db(env.unauthenticatedContext());
  });

  after(async () => {
    await env.clearFirestore();
    await env.cleanup();
  });

  /** A user doc as it looks after the app created it and onUserCreate ran. */
  const existingUser = (over: DocumentData = {}): DocumentData => ({
    name: 'Alice',
    email: 'alice@example.com',
    phone: '7501234567',
    countryCode: '+964',
    locale: 'en',
    referralCodeEntered: null,
    deviceId: 'device-a',
    photoUrl: null,
    notificationsEnabled: true,
    profileCompleted: false,
    role: 'customer',
    storeIds: [],
    referralCode: 'ALC234',
    referredBy: null,
    totalOrders: 0,
    totalSpent: 0,
    isBlocked: false,
    isDeleted: false,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...over,
  });

  /** AddressModel.toMap() (SRS §5.20). */
  const address = (over: DocumentData = {}): DocumentData => ({
    label: 'Home',
    name: 'Sara Ahmed',
    phone: '7501234567',
    city: 'erbil',
    area: 'Ankawa',
    street: '100m Rd',
    building: '12',
    floor: '3',
    notes: 'Ring twice',
    lat: null,
    lng: null,
    isDefault: true,
    ...over,
  });

  /** An order as placeOrder writes it (the fields the rules look at). */
  const order = (over: DocumentData = {}): DocumentData => ({
    orderNumber: 'GG-2610-00001',
    userId: 'alice',
    storeIds: ['s1'],
    items: [
      { id: 'i1', productId: 'p1', storeId: 's1', titleSnapshot: 'Mug', unitPrice: 15000, qty: 1, selections: [], lineTotal: 15000, preparationDays: 0, status: 'pending' },
    ],
    subtotal: 15000,
    deliveryFee: 3000,
    total: 18000,
    paymentMethod: 'cashOnDelivery',
    paymentStatus: 'pending',
    status: 'pending',
    statusNote: null,
    statusUpdatedBy: 'alice',
    statusUpdatedByRole: 'customer',
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...over,
  });

  /** FirestoreCartStore.upsert: CartItemModel.toMap() + addedAt. */
  const cartItem = (over: DocumentData = {}): DocumentData => ({
    productId: 'p1',
    storeId: 's1',
    titleSnapshot: 'Mug',
    titleSnapshotAr: 'كوب',
    imageSnapshot: 'https://img/mug.jpg',
    unitPrice: 15000,
    qty: 1,
    selections: [{ groupId: 'name', type: 'text', label: 'Name', text: 'Sara', priceDelta: 0 }],
    lineTotal: 15000,
    preparationDays: 0,
    addedAt: Timestamp.now(),
    ...over,
  });

  /** PromoAdminRepository.create: PromoCodeModel.toMap() + usageCount 0 (timestamps left out here). */
  const promoCode = (over: DocumentData = {}): DocumentData => ({
    code: 'EID10',
    title: 'Eid sale',
    titleAr: 'تخفيضات العيد',
    description: '10% off',
    type: 'percent',
    value: 10,
    maxDiscount: 5000,
    minOrder: null,
    usageLimit: 100,
    usageCount: 0,
    perUserLimit: 1,
    firstOrderOnly: false,
    categoryIds: [],
    storeIds: [],
    isPublic: true,
    isActive: true,
    expiresAt: Timestamp.fromDate(new Date('2030-01-01')),
    ...over,
  });

  /** WishlistRepository.add. */
  const wishlistItem = (over: DocumentData = {}): DocumentData => ({
    listId: 'default',
    productId: 'p1',
    title: 'Mug',
    titleAr: 'كوب',
    image: 'https://img/mug.jpg',
    price: 15000,
    addedAt: Timestamp.now(),
    ...over,
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = db(ctx);
      const seed: Array<[string, DocumentData]> = [
        ['users/alice', existingUser({ fcmTokens: ['tok-1', 'tok-2'] })],
        ['users/bob', existingUser({ name: 'Bob', referralCode: 'BOB234' })],
        ['users/gone', existingUser({ name: 'Deleted user', isDeleted: true })],
        ['users/alice/addresses/home', address()],
        ['users/alice/saved_cards/card-1', { brand: 'visa', last4: '4242' }],
        ['wallets/alice', { balance: 0, credits: 0, currency: 'IQD' }],
        ['wallets/alice/transactions/t1', { type: 'referralCredit', amount: 5000 }],
        ['wallets/alice/credit_lots/lot1', { amount: 5000, remaining: 5000, open: true, source: 'referral', expiresAt: null }],
        ['referrals/bob', { referrerUid: 'alice', referredUid: 'bob', code: 'ALC234', status: 'pending' }],
        ['referrals/carol', { referrerUid: 'dave', referredUid: 'carol', code: 'DAV234', status: 'pending' }],
        ['notifications/n-alice', { userId: 'alice', title: 'Hi', isRead: false }],
        ['notifications/n-bob', { userId: 'bob', title: 'Hi', isRead: false }],
        ['notifications/n-all', { userId: 'all', title: 'Sale', isRead: false }],
        ['products/p1', { title: 'Mug', price: 15000 }],
        ['categories/c1', { title: 'Birthday' }],
        ['categories/c1/subcategories/s1', { title: 'Kids' }],
        ['banners/b1', { placement: 'homeTop' }],
        ['gift_card_templates/g1', { title: 'Eid' }],
        ['stores/s1', { name: 'Golden Gift Home', status: 'active', ownerUid: 'owner-s1' }],
        ['app_settings/general', { maintenanceMode: false }],
        ['admins/admin-1', { role: 'super' }],
        ['admins/admin-2', { role: 'ops' }],
        ['admin_audit_log/l1', { adminUid: 'admin-1', action: 'update' }],
        ['counters/orders-2610', { next: 42 }],
        ['function_runs/onUserCreate:alice', { key: 'onUserCreate:alice' }],
        ['otp_codes/login:9647501234567', { phone: '+9647501234567', purpose: 'login', hash: 'aa:bb', attempts: 0 }],
        ['otp_codes/changePhone:9647501234567', { phone: '+9647501234567', purpose: 'changePhone', uid: 'alice' }],
        ['otp_throttle/phone:9647501234567', { hits: [Date.now()] }],
        ['otp_throttle/global:2026-10-20', { sent: 1, day: '2026-10-20' }],
        ['otp_debug/9647501234567', { code: '123456', purpose: 'login' }],
        ['orders/o1', order()],
        ['orders/o1/status_history/h1', { status: 'pending', byUid: 'alice', byRole: 'customer', note: null, at: Timestamp.now() }],
        ['orders/o-bob', order({ userId: 'bob' })],
        ['carts/alice/items/i1', cartItem()],
        ['promo_codes/EID10', promoCode()],
        ['promo_codes/VIP50', promoCode({ code: 'VIP50', isPublic: false })],
        ['promo_codes/OLD5', promoCode({ code: 'OLD5', isActive: false })],
        ['promo_codes/USED', promoCode({ code: 'USED', usageCount: 3 })],
        ['promo_codes/EID10/usages/alice', { count: 1 }],
        ['wishlists/alice/items/p1', wishlistItem()],
      ];
      for (const [path, data] of seed) await setDoc(doc(d, path), data);
    });
  });

  // ── users/{uid} ──────────────────────────────────────────────────────────
  describe('users: create', () => {
    /** Exactly what the app writes after the first sign-in (SRS AUTH-3). */
    const signUpDoc = (over: DocumentData = {}): DocumentData => ({
      name: 'Newbie',
      email: null,
      phone: '7501234567',
      countryCode: '+964',
      locale: 'ckb',
      referralCodeEntered: 'ALC234',
      deviceId: '0f8fad5b-d9cb-469f-a165-70867728950e',
      photoUrl: null,
      notificationsEnabled: true,
      profileCompleted: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...over,
    });
    const create = (fs: Firestore, data: DocumentData) => setDoc(doc(fs, 'users/newbie'), data);
    /** Signed in through verifyOtp: the ID token carries the verified phone_number. */
    const newbie = () => db(env.authenticatedContext('newbie', { phone_number: '+9647501234567' }));
    /** Signed in with Google: no phone on the account. */
    const googleNewbie = () => as('newbie');

    test('owner creates the sign-up doc', () => allowed(create(newbie(), signUpDoc())));
    test('Google account: no phone, no referral code', () =>
      allowed(create(googleNewbie(), signUpDoc({ phone: null, email: 'n@example.com', referralCodeEntered: null }))));
    test('the phone is the verified one: another number, or a number without a verified phone, is denied', async () => {
      await denied(create(newbie(), signUpDoc({ phone: '7709998877' })));
      await denied(create(newbie(), signUpDoc({ countryCode: '+44' })));
      await denied(create(googleNewbie(), signUpDoc()));
      await allowed(create(googleNewbie(), signUpDoc({ phone: '' })));
    });
    test('profile fields are bounded', async () => {
      for (const over of [
        { email: `${'x'.repeat(250)}@example.com` },
        { deviceId: 'd'.repeat(129) },
        { photoUrl: `https://x/${'p'.repeat(2048)}` },
        { locale: 'fr' },
        { notificationsEnabled: 'yes' },
        { profileCompleted: 1 },
        { countryCode: '964' },
        { countryCode: '+96412' },
      ]) {
        await denied(create(newbie(), signUpDoc(over)));
      }
    });
    test('a subset of the creation keys', () =>
      allowed(create(newbie(), { name: 'Newbie', countryCode: '+964', locale: 'en' })));
    test('name of 2 and of 50 characters', async () => {
      await allowed(create(newbie(), signUpDoc({ name: 'Al' })));
      await env.clearFirestore();
      await allowed(create(newbie(), signUpDoc({ name: 'x'.repeat(50) })));
    });

    for (const [label, over] of [
      ['role: admin', { role: 'admin' }],
      ['referralCode', { referralCode: 'MYCODE' }],
      ['referredBy', { referredBy: 'alice' }],
      ['isBlocked', { isBlocked: false }],
      ['totalSpent', { totalSpent: 0 }],
      ['storeIds', { storeIds: ['s1'] }],
      ['isDeleted', { isDeleted: false }],
      ['an unknown key', { favouriteColor: 'gold' }],
      ['birthday (update-only key)', { birthday: Timestamp.now() }],
      ['name of 1 character', { name: 'A' }],
      ['name of 51 characters', { name: 'x'.repeat(51) }],
      ['name that is not a string', { name: 42 }],
      ['referral code of 5 characters', { referralCodeEntered: 'ABCDE' }],
      ['referral code of 7 characters', { referralCodeEntered: 'ABCDEFG' }],
      ['referral code that is a number', { referralCodeEntered: 123456 }],
      ['countryCode that is a number', { countryCode: 964 }],
      ['a client-side createdAt', { createdAt: Timestamp.fromDate(new Date('2020-01-01')) }],
    ] as Array<[string, DocumentData]>) {
      test(`denied with ${label}`, () => denied(create(newbie(), signUpDoc(over))));
    }

    test('denied without a name', () => {
      const { name: _name, ...rest } = signUpDoc();
      return denied(create(newbie(), rest));
    });
    test('denied without countryCode', () => {
      const { countryCode: _cc, ...rest } = signUpDoc();
      return denied(create(newbie(), rest));
    });
    test("denied for another user's doc", () => denied(create(bob, signUpDoc())));
    test('denied signed out', () => denied(create(anon, signUpDoc())));
    test('denied for an admin (only the owner creates)', () => denied(create(admin, signUpDoc())));
    test('re-sending the sign-up doc for an existing user is denied (it is an update)', () =>
      denied(setDoc(doc(alice, 'users/alice'), signUpDoc({ name: 'Alice' }))));
  });

  describe('users: read / delete', () => {
    test('owner reads', () => allowed(getDoc(doc(alice, 'users/alice'))));
    test('admin reads', () => allowed(getDoc(doc(admin, 'users/alice'))));
    test('other user denied', () => denied(getDoc(doc(bob, 'users/alice'))));
    test('signed out denied', () => denied(getDoc(doc(anon, 'users/alice'))));
    test('listing users denied', () => denied(getDocs(collection(alice, 'users'))));
    test("admins list and search users and read their addresses (dashboard Users)", async () => {
      await allowed(getDocs(collection(admin, 'users')));
      await allowed(getDocs(query(collection(admin, 'users'), where('phone', 'in', ['7501234567', '+9647501234567']))));
      await allowed(getDocs(collection(admin, 'users/alice/addresses')));
      await allowed(getDoc(doc(admin, 'users/alice/addresses/home')));
      await denied(setDoc(doc(admin, 'users/alice/addresses/x'), address()));
      await denied(deleteDoc(doc(admin, 'users/alice/addresses/home')));
      await denied(getDocs(collection(bob, 'users/alice/addresses')));
    });
    test('owner cannot delete', () => denied(deleteDoc(doc(alice, 'users/alice'))));
    test('admin cannot delete', () => denied(deleteDoc(doc(admin, 'users/alice'))));
  });

  describe('users: update', () => {
    const update = (fs: Firestore, data: DocumentData, path = 'users/alice') => updateDoc(doc(fs, path), data);

    test('owner updates name', () => allowed(update(alice, { name: 'Alice B', updatedAt: serverTimestamp() })));
    test('owner updates every Edit Profile / Settings field', () =>
      allowed(
        update(alice, {
          name: 'Alice B',
          email: 'b@example.com',
          phone: '7501234567',
          countryCode: '+964',
          photoUrl: 'https://example.com/a.jpg',
          birthday: Timestamp.fromDate(new Date('1995-04-01')),
          gender: 'female',
          city: 'erbil',
          locale: 'ar',
          notificationsEnabled: false,
          profileCompleted: true,
          updatedAt: serverTimestamp(),
          lastSeenAt: serverTimestamp(),
        }),
      ));
    test('owner clears optional fields', () =>
      allowed(update(alice, { birthday: null, gender: null, city: null, photoUrl: null })));

    for (const [label, data] of [
      ['isBlocked', { isBlocked: true }],
      ['role', { role: 'admin' }],
      ['referralCode', { referralCode: 'NEW234' }],
      ['referredBy', { referredBy: 'bob' }],
      ['totalSpent', { totalSpent: 1 }],
      ['totalOrders', { totalOrders: 1 }],
      ['storeIds', { storeIds: ['s1'] }],
      ['isDeleted', { isDeleted: true }],
      ['deletedAt', { deletedAt: serverTimestamp() }],
      ['referralCodeEntered (sign-up only)', { referralCodeEntered: 'BOB234' }],
      ['deviceId (sign-up only)', { deviceId: 'device-b' }],
      ['createdAt', { createdAt: serverTimestamp() }],
      ['an unknown key', { favouriteColor: 'gold' }],
      ['name of 1 character', { name: 'A' }],
      ['countryCode that is a number', { countryCode: 964 }],
      ['a client-side updatedAt', { updatedAt: Timestamp.fromDate(new Date('2020-01-01')) }],
    ] as Array<[string, DocumentData]>) {
      test(`owner denied: ${label}`, () => denied(update(alice, data)));
    }

    test('other user denied', () => denied(update(bob, { name: 'Hacked' })));
    test('signed out denied', () => denied(update(anon, { name: 'Hacked' })));
    test('anonymized account cannot be edited again', () =>
      denied(update(as('gone'), { name: 'Back again' }, 'users/gone')));
    test('admins never write profiles (setUserBlocked / adjustWallet / reviewPartner / setAdminClaim do)', async () => {
      await denied(update(admin, { isBlocked: true }));
      await denied(update(admin, { role: 'seller' }));
      await denied(update(admin, { name: 'Renamed' }));
    });
    test('a new phone only when it is the verified one (changePhone writes it with the Admin SDK)', async () => {
      await denied(update(alice, { phone: '7709998877' }));
      await denied(update(alice, { countryCode: '+44' }));
      const verified = db(env.authenticatedContext('alice', { phone_number: '+9647709998877' }));
      await allowed(update(verified, { phone: '7709998877', countryCode: '+964' }));
      await denied(update(bob, { phone: '7709998877' }, 'users/bob'));
    });
    test('profile fields stay bounded on update', async () => {
      for (const data of [
        { email: 42 },
        { gender: 'g'.repeat(21) },
        { city: 'c'.repeat(65) },
        { birthday: '1995-04-01' },
        { profileCompleted: 'yes' },
        { lastSeenAt: 'now' },
      ]) {
        await denied(update(alice, data));
      }
    });

    // ── push tokens, language, notifications toggle (SRS §4.5) ──
    test('owner registers a device token (arrayUnion) and removes one on sign-out (arrayRemove)', async () => {
      await allowed(update(alice, { fcmTokens: arrayUnion('tok-3') }));
      await allowed(update(alice, { fcmTokens: arrayUnion('tok-3') })); // already there: no change
      await allowed(update(alice, { fcmTokens: arrayRemove('tok-1') }));
      await allowed(update(alice, { fcmTokens: arrayRemove('not-there') }));
    });
    test('the first token on a profile without fcmTokens', () =>
      allowed(update(as('bob'), { fcmTokens: arrayUnion('bob-device') }, 'users/bob')));
    test('at most 10 device tokens', async () => {
      // alice starts with 2.
      for (let i = 3; i <= 10; i++) await allowed(update(alice, { fcmTokens: arrayUnion(`t${i}`) }));
      await denied(update(alice, { fcmTokens: arrayUnion('t11') }));
      await allowed(update(alice, { fcmTokens: arrayRemove('t3') }));
      await allowed(update(alice, { fcmTokens: arrayUnion('t11') }));
    });
    for (const [label, data] of [
      ['a token that is not a string', { fcmTokens: arrayUnion(42) }],
      ['an empty token', { fcmTokens: arrayUnion('') }],
      ['two new tokens at once', { fcmTokens: arrayUnion('a', 'b') }],
      ['replacing the list with foreign tokens', { fcmTokens: ['someone-elses'] }],
      ['fcmTokens as a string', { fcmTokens: 'tok' }],
      ['an unsupported locale', { locale: 'fr' }],
      ['locale "ku" (the app uses ckb)', { locale: 'ku' }],
      ['notificationsEnabled as a string', { notificationsEnabled: 'no' }],
    ] as Array<[string, DocumentData]>) {
      test(`owner denied: ${label}`, () => denied(update(alice, data)));
    }
    test('owner switches language and notifications', async () => {
      for (const locale of ['ar', 'ckb', 'en']) await allowed(update(alice, { locale, updatedAt: serverTimestamp() }));
      await allowed(update(alice, { notificationsEnabled: false }));
      await allowed(update(alice, { notificationsEnabled: true }));
    });
    test("another user cannot add a token to alice's profile", () => denied(update(bob, { fcmTokens: arrayUnion('evil') })));
  });

  describe('users: subcollections', () => {
    test('owner reads and writes addresses (AddressRepository)', async () => {
      await allowed(getDocs(collection(alice, 'users/alice/addresses')));
      await allowed(setDoc(doc(alice, 'users/alice/addresses/work'), address({ label: 'Work', isDefault: false })));
      await allowed(setDoc(doc(alice, 'users/alice/addresses/pin'), address({ lat: 36.19, lng: 44.01, building: '', floor: '', notes: '' })));
      await allowed(updateDoc(doc(alice, 'users/alice/addresses/home'), { isDefault: false })); // setDefault batch
      await allowed(updateDoc(doc(alice, 'users/alice/addresses/home'), { label: 'Home 2', updatedAt: serverTimestamp() }));
      await allowed(deleteDoc(doc(alice, 'users/alice/addresses/home')));
    });
    test('the save batch (new default + old default off) is allowed', async () => {
      const batch = writeBatch(alice);
      batch.update(doc(alice, 'users/alice/addresses/home'), { isDefault: false });
      batch.set(doc(alice, 'users/alice/addresses/new'), address({ label: 'Mum' }));
      await allowed(batch.commit());
    });
    for (const [label, data] of [
      ['an unknown key', address({ gate: 'blue' })],
      ['no city', (() => { const { city: _c, ...rest } = address(); return rest; })()],
      ['an empty city', address({ city: '' })],
      ['a city that is not a string', address({ city: 7 })],
      ['a label of 101 characters', address({ label: 'x'.repeat(101) })],
      ['notes of 601 characters', address({ notes: 'x'.repeat(601) })],
      ['a phone of 33 characters', address({ phone: '1'.repeat(33) })],
      ['lat as a string', address({ lat: '36.1' })],
      ['isDefault as a string', address({ isDefault: 'yes' })],
      ['a client-side createdAt', address({ createdAt: Timestamp.fromDate(new Date('2020-01-01')) })],
    ] as Array<[string, DocumentData]>) {
      test(`address denied: ${label}`, () => denied(setDoc(doc(alice, 'users/alice/addresses/bad'), data)));
    }
    test("others cannot touch alice's addresses", async () => {
      await denied(getDoc(doc(bob, 'users/alice/addresses/home')));
      await denied(setDoc(doc(bob, 'users/alice/addresses/x'), address()));
      await denied(deleteDoc(doc(bob, 'users/alice/addresses/home')));
      await denied(getDoc(doc(anon, 'users/alice/addresses/home')));
    });
    test('owner reads and deletes saved cards', async () => {
      await allowed(getDocs(collection(alice, 'users/alice/saved_cards')));
      await allowed(deleteDoc(doc(alice, 'users/alice/saved_cards/card-1')));
    });
    test('owner cannot write saved cards (gateway function only)', async () => {
      await denied(setDoc(doc(alice, 'users/alice/saved_cards/card-2'), { last4: '1111' }));
      await denied(updateDoc(doc(alice, 'users/alice/saved_cards/card-1'), { last4: '1111' }));
    });
    test("others cannot read alice's saved cards", () =>
      denied(getDoc(doc(bob, 'users/alice/saved_cards/card-1'))));
  });

  // ── wallets ──────────────────────────────────────────────────────────────
  describe('wallets', () => {
    test('owner and admin read', async () => {
      await allowed(getDoc(doc(alice, 'wallets/alice')));
      await allowed(getDoc(doc(admin, 'wallets/alice')));
      await allowed(getDocs(collection(alice, 'wallets/alice/transactions')));
      await allowed(getDoc(doc(admin, 'wallets/alice/transactions/t1')));
    });
    test('other user and signed out denied', async () => {
      await denied(getDoc(doc(bob, 'wallets/alice')));
      await denied(getDoc(doc(anon, 'wallets/alice')));
      await denied(getDoc(doc(bob, 'wallets/alice/transactions/t1')));
    });
    test('nobody writes from a client — not even the owner or an admin', async () => {
      await denied(updateDoc(doc(alice, 'wallets/alice'), { balance: 1_000_000 }));
      await denied(setDoc(doc(alice, 'wallets/newbie'), { balance: 0, credits: 0 }));
      await denied(setDoc(doc(alice, 'wallets/alice/transactions/t2'), { amount: 5000 }));
      await denied(updateDoc(doc(admin, 'wallets/alice'), { credits: 5000 }));
      await denied(deleteDoc(doc(alice, 'wallets/alice')));
    });
    test('credit lots: owner and admin read; nobody writes', async () => {
      await allowed(getDoc(doc(alice, 'wallets/alice/credit_lots/lot1')));
      await allowed(getDocs(collection(alice, 'wallets/alice/credit_lots')));
      await allowed(getDocs(collection(admin, 'wallets/alice/credit_lots')));
      await denied(getDoc(doc(bob, 'wallets/alice/credit_lots/lot1')));
      await denied(getDocs(collection(anon, 'wallets/alice/credit_lots')));
      await denied(updateDoc(doc(alice, 'wallets/alice/credit_lots/lot1'), { remaining: 1_000_000 }));
      await denied(setDoc(doc(alice, 'wallets/alice/credit_lots/lot2'), { amount: 5000, remaining: 5000, open: true }));
      await denied(setDoc(doc(admin, 'wallets/alice/credit_lots/lot2'), { amount: 5000, remaining: 5000, open: true }));
      await denied(deleteDoc(doc(admin, 'wallets/alice/credit_lots/lot1')));
    });
  });

  // ── referrals ────────────────────────────────────────────────────────────
  describe('referrals', () => {
    test('the referrer reads (Invite & Earn); the referred friend does not', async () => {
      await allowed(getDoc(doc(alice, 'referrals/bob')));
      await denied(getDoc(doc(bob, 'referrals/bob')));
    });
    test('admin reads, lists and counts (dashboard Referrals)', async () => {
      await allowed(getDoc(doc(admin, 'referrals/carol')));
      await allowed(getDocs(collection(admin, 'referrals')));
      await allowed(getCountFromServer(collection(admin, 'referrals')));
      await allowed(getCountFromServer(query(collection(admin, 'referrals'), where('status', '==', 'pending'))));
      await allowed(getCountFromServer(query(collection(admin, 'referrals'), where('joinBonusPaid', '==', true))));
    });
    test('anyone else denied', async () => {
      await denied(getDoc(doc(alice, 'referrals/carol')));
      await denied(getDoc(doc(anon, 'referrals/bob')));
    });
    test('own referrals can be listed and counted by referrerUid only', async () => {
      await allowed(getDocs(query(collection(alice, 'referrals'), where('referrerUid', '==', 'alice'))));
      await allowed(getCountFromServer(query(collection(alice, 'referrals'), where('referrerUid', '==', 'alice'))));
      await denied(getDocs(query(collection(bob, 'referrals'), where('referredUid', '==', 'bob'))));
    });
    test('listing all or other people’s referrals denied', async () => {
      await denied(getDocs(collection(alice, 'referrals')));
      await denied(getCountFromServer(collection(alice, 'referrals')));
      await denied(getDocs(query(collection(alice, 'referrals'), where('referrerUid', '==', 'dave'))));
    });
    test('no client writes', async () => {
      await denied(setDoc(doc(bob, 'referrals/bob'), { referrerUid: 'alice', referredUid: 'bob', status: 'completed' }));
      await denied(setDoc(doc(as('erin'), 'referrals/erin'), { referrerUid: 'alice', referredUid: 'erin' }));
      await denied(updateDoc(doc(admin, 'referrals/bob'), { status: 'completed' }));
    });
  });

  // ── promo_codes ──────────────────────────────────────────────────────────
  describe('promo_codes', () => {
    const publicQuery = (fs: Firestore) =>
      query(collection(fs, 'promo_codes'), where('isPublic', '==', true), where('isActive', '==', true));

    test('a signed-in customer gets any code by id (private ones work when typed), also a missing one', async () => {
      await allowed(getDoc(doc(alice, 'promo_codes/EID10')));
      await allowed(getDoc(doc(alice, 'promo_codes/VIP50')));
      await allowed(getDoc(doc(alice, 'promo_codes/OLD5')));
      await allowed(getDoc(doc(alice, 'promo_codes/NOPE')));
    });
    test('a guest gets only public, active codes', async () => {
      await allowed(getDoc(doc(anon, 'promo_codes/EID10')));
      await denied(getDoc(doc(anon, 'promo_codes/VIP50')));
      await denied(getDoc(doc(anon, 'promo_codes/OLD5')));
    });
    test("the Promo Codes screen's list query works for everyone; any other list is denied", async () => {
      await allowed(getDocs(publicQuery(alice)));
      await allowed(getDocs(publicQuery(anon)));
      await denied(getDocs(collection(alice, 'promo_codes')));
      await denied(getDocs(query(collection(alice, 'promo_codes'), where('isPublic', '==', true))));
      await denied(getDocs(query(collection(anon, 'promo_codes'), where('isActive', '==', true))));
    });
    test('admins read and list everything', async () => {
      await allowed(getDocs(collection(admin, 'promo_codes')));
      await allowed(getDoc(doc(admin, 'promo_codes/VIP50')));
    });
    test("admin create / update / delete, the dashboard's way (change + audit entry in one batch)", async () => {
      const audit = { adminUid: 'admin-1', target: 'promo_codes/NEW1', before: null, at: serverTimestamp() };
      const create = writeBatch(admin);
      create.set(doc(admin, 'promo_codes/NEW1'), promoCode({ code: 'NEW1', usageCount: 0, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
      create.set(doc(collection(admin, 'admin_audit_log')), { ...audit, action: 'promo.create', after: { code: 'NEW1' } });
      await allowed(create.commit());
      const update = writeBatch(admin);
      update.update(doc(admin, 'promo_codes/NEW1'), { value: 15, titleKu: deleteField(), updatedAt: serverTimestamp() });
      update.set(doc(collection(admin, 'admin_audit_log')), { ...audit, action: 'promo.update', after: { value: 15 } });
      await allowed(update.commit());
      await allowed(updateDoc(doc(admin, 'promo_codes/NEW1'), { isActive: false, updatedAt: serverTimestamp() }));
      await allowed(deleteDoc(doc(admin, 'promo_codes/NEW1')));
    });
    test('usageCount is placeOrder’s: 0 on create, never changed by a client; a used code is not deleted', async () => {
      await denied(setDoc(doc(admin, 'promo_codes/NEW2'), promoCode({ code: 'NEW2', usageCount: 5 })));
      const { usageCount: _u, ...withoutCount } = promoCode({ code: 'NEW3' });
      await denied(setDoc(doc(admin, 'promo_codes/NEW3'), withoutCount));
      await denied(setDoc(doc(admin, 'promo_codes/OTHER'), promoCode({ code: 'NOT-THE-ID' })));
      await denied(updateDoc(doc(admin, 'promo_codes/EID10'), { usageCount: 0 + 1 }));
      await denied(updateDoc(doc(admin, 'promo_codes/USED'), { usageCount: 0 }));
      await denied(updateDoc(doc(admin, 'promo_codes/EID10'), { usageCount: increment(-1) }));
      await denied(updateDoc(doc(admin, 'promo_codes/EID10'), { code: 'EID11' }));
      await denied(deleteDoc(doc(admin, 'promo_codes/USED')));
    });
    test('customers and guests never write codes', async () => {
      await denied(setDoc(doc(alice, 'promo_codes/MINE'), promoCode({ code: 'MINE' })));
      await denied(updateDoc(doc(alice, 'promo_codes/EID10'), { value: 100 }));
      await denied(updateDoc(doc(alice, 'promo_codes/EID10'), { usageCount: 0 }));
      await denied(deleteDoc(doc(alice, 'promo_codes/EID10')));
      await denied(setDoc(doc(anon, 'promo_codes/MINE'), promoCode({ code: 'MINE' })));
    });
    test('usages/{uid}: the customer reads their own, admins any; nobody writes', async () => {
      await allowed(getDoc(doc(alice, 'promo_codes/EID10/usages/alice')));
      await allowed(getDoc(doc(alice, 'promo_codes/VIP50/usages/alice'))); // missing doc: count 0
      await allowed(getDoc(doc(admin, 'promo_codes/EID10/usages/alice')));
      await allowed(getDocs(collection(admin, 'promo_codes/EID10/usages')));
      await denied(getDoc(doc(bob, 'promo_codes/EID10/usages/alice')));
      await denied(getDocs(collection(alice, 'promo_codes/EID10/usages')));
      await denied(getDoc(doc(anon, 'promo_codes/EID10/usages/alice')));
      await denied(setDoc(doc(alice, 'promo_codes/EID10/usages/alice'), { count: 0 }));
      await denied(updateDoc(doc(alice, 'promo_codes/EID10/usages/alice'), { count: 0 }));
      await denied(deleteDoc(doc(alice, 'promo_codes/EID10/usages/alice')));
      await denied(setDoc(doc(admin, 'promo_codes/EID10/usages/bob'), { count: 0 }));
    });
  });

  // ── notifications ────────────────────────────────────────────────────────
  describe('notifications', () => {
    test('own and broadcast notifications are readable', async () => {
      await allowed(getDoc(doc(alice, 'notifications/n-alice')));
      await allowed(getDoc(doc(alice, 'notifications/n-all')));
    });
    test("another user's notification and signed-out reads are denied", async () => {
      await denied(getDoc(doc(alice, 'notifications/n-bob')));
      await denied(getDoc(doc(anon, 'notifications/n-all')));
      await denied(getDoc(doc(anon, 'notifications/n-alice')));
    });
    test("the app's queries are allowed", async () => {
      await allowed(getDocs(query(collection(alice, 'notifications'), where('userId', '==', 'alice'))));
      await allowed(getDocs(query(collection(alice, 'notifications'), where('userId', 'in', ['alice', 'all']))));
    });
    test('unfiltered or foreign queries are denied', async () => {
      await denied(getDocs(collection(alice, 'notifications')));
      await denied(getDocs(query(collection(alice, 'notifications'), where('userId', '==', 'bob'))));
    });
    test('owner marks as read (NotificationsRepository.markRead / markAllRead)', async () => {
      await allowed(updateDoc(doc(alice, 'notifications/n-alice'), { isRead: true }));
      await allowed(updateDoc(doc(alice, 'notifications/n-alice'), { isRead: true, updatedAt: serverTimestamp() }));
    });
    test('owner cannot mark as unread or change anything else', async () => {
      await denied(updateDoc(doc(alice, 'notifications/n-alice'), { isRead: false }));
      await denied(updateDoc(doc(alice, 'notifications/n-alice'), { title: 'Changed' }));
      await denied(updateDoc(doc(alice, 'notifications/n-alice'), { isRead: true, title: 'Changed' }));
      await denied(updateDoc(doc(alice, 'notifications/n-alice'), { userId: 'all' }));
      await denied(updateDoc(doc(alice, 'notifications/n-alice'), { isRead: 'yes' }));
      await denied(updateDoc(doc(alice, 'notifications/n-alice'), { isRead: true, updatedAt: Timestamp.fromDate(new Date('2020-01-01')) }));
    });
    test('admins read any notification and the broadcast history', async () => {
      await allowed(getDoc(doc(admin, 'notifications/n-bob')));
      await allowed(getDocs(query(collection(admin, 'notifications'), where('userId', '==', 'all'))));
    });
    test('admins cannot write notifications either (sendBroadcast does)', async () => {
      await denied(updateDoc(doc(admin, 'notifications/n-all'), { title: 'Edited' }));
      await denied(deleteDoc(doc(admin, 'notifications/n-all')));
    });
    test("cannot mark another user's or a broadcast notification", async () => {
      await denied(updateDoc(doc(bob, 'notifications/n-alice'), { isRead: true }));
      await denied(updateDoc(doc(alice, 'notifications/n-all'), { isRead: true }));
    });
    test('owner deletes own (swipe to delete); not others or broadcasts', async () => {
      await allowed(deleteDoc(doc(alice, 'notifications/n-alice')));
      await denied(deleteDoc(doc(alice, 'notifications/n-bob')));
      await denied(deleteDoc(doc(alice, 'notifications/n-all')));
    });
    test('clients never create notifications', async () => {
      await denied(setDoc(doc(alice, 'notifications/n-new'), { userId: 'alice', title: 'Fake', isRead: false }));
      await denied(setDoc(doc(admin, 'notifications/n-new'), { userId: 'all', title: 'Fake', isRead: false }));
    });
  });

  // ── orders (Phase 6) ─────────────────────────────────────────────────────
  describe('orders', () => {
    /** Exactly what AdminOrdersRepository.changeStatus writes. */
    const statusChange = (status: string, over: DocumentData = {}): DocumentData => ({
      status,
      statusNote: 'Called the customer',
      statusUpdatedBy: 'admin-1',
      statusUpdatedByRole: 'admin',
      items: (order().items as DocumentData[]).map((i) => ({ ...i, status })),
      updatedAt: serverTimestamp(),
      ...over,
    });

    test('the owner reads their order and lists their orders', async () => {
      await allowed(getDoc(doc(alice, 'orders/o1')));
      await allowed(getDocs(query(collection(alice, 'orders'), where('userId', '==', 'alice'))));
    });
    test("other customers and visitors cannot read it or list everyone's", async () => {
      await denied(getDoc(doc(bob, 'orders/o1')));
      await denied(getDoc(doc(anon, 'orders/o1')));
      await denied(getDocs(collection(alice, 'orders')));
      await denied(getDocs(query(collection(alice, 'orders'), where('userId', '==', 'bob'))));
    });
    test('admins read and list every order', async () => {
      await allowed(getDoc(doc(admin, 'orders/o-bob')));
      await allowed(getDocs(query(collection(admin, 'orders'), where('status', '==', 'pending'))));
    });
    test('nobody creates or deletes orders from a client (placeOrder only)', async () => {
      await denied(setDoc(doc(alice, 'orders/o-new'), order()));
      await denied(setDoc(doc(admin, 'orders/o-new'), order()));
      await denied(deleteDoc(doc(alice, 'orders/o1')));
      await denied(deleteDoc(doc(admin, 'orders/o1')));
    });
    test('customers never update — not even to cancel (cancelOrder does)', async () => {
      await denied(updateDoc(doc(alice, 'orders/o1'), { status: 'cancelledByBuyer', statusUpdatedBy: 'alice', statusUpdatedByRole: 'customer' }));
      await denied(updateDoc(doc(alice, 'orders/o1'), { total: 1 }));
      await denied(updateDoc(doc(alice, 'orders/o1'), { giftMessage: 'changed' }));
    });
    test("an admin changes status the dashboard's way, with its audit entry in the same batch", async () => {
      const batch = writeBatch(admin);
      batch.update(doc(admin, 'orders/o1'), statusChange('confirmed'));
      batch.set(doc(collection(admin, 'admin_audit_log')), {
        adminUid: 'admin-1',
        action: 'order.status',
        target: 'orders/o1',
        before: { status: 'pending' },
        after: { status: 'confirmed', note: 'Called the customer' },
        at: serverTimestamp(),
      });
      await allowed(batch.commit());
    });
    test('seller cancellation with a reason; a note may be null', async () => {
      await allowed(updateDoc(doc(admin, 'orders/o1'), statusChange('cancelledBySeller', { cancelReason: 'Out of stock' })));
      await allowed(updateDoc(doc(admin, 'orders/o-bob'), statusChange('confirmed', { statusNote: null, items: order().items })));
    });
    for (const [label, data] of [
      ['someone else as statusUpdatedBy', statusChange('confirmed', { statusUpdatedBy: 'admin-2' })],
      ['statusUpdatedByRole customer', statusChange('confirmed', { statusUpdatedByRole: 'customer' })],
      ['an unknown status', statusChange('lost')],
      ['a price change', { ...statusChange('confirmed'), total: 1 }],
      ['paymentStatus (functions only)', { ...statusChange('delivered'), paymentStatus: 'paid' }],
      ['a removed line', statusChange('confirmed', { items: [] })],
      ['a note of 501 characters', statusChange('confirmed', { statusNote: 'x'.repeat(501) })],
      ['a client-side updatedAt', statusChange('confirmed', { updatedAt: Timestamp.fromDate(new Date('2020-01-01')) })],
      ['userId', { ...statusChange('confirmed'), userId: 'bob' }],
    ] as Array<[string, DocumentData]>) {
      test(`admin denied: ${label}`, () => denied(updateDoc(doc(admin, 'orders/o1'), data)));
    }

    test('timeline: the owner and admins read, nobody writes', async () => {
      await allowed(getDocs(collection(alice, 'orders/o1/status_history')));
      await allowed(getDoc(doc(admin, 'orders/o1/status_history/h1')));
      await denied(getDocs(collection(bob, 'orders/o1/status_history')));
      await denied(getDocs(collection(anon, 'orders/o1/status_history')));
      const entry = { status: 'delivered', byUid: 'alice', byRole: 'customer', note: null, at: serverTimestamp() };
      await denied(setDoc(doc(alice, 'orders/o1/status_history/h2'), entry));
      await denied(setDoc(doc(admin, 'orders/o1/status_history/h2'), entry));
      await denied(updateDoc(doc(admin, 'orders/o1/status_history/h1'), { note: 'x' }));
      await denied(deleteDoc(doc(alice, 'orders/o1/status_history/h1')));
    });
  });

  // ── carts / wishlists (Phase 4 data, rules in Phase 6) ───────────────────
  describe('carts/{uid}/items', () => {
    const put = (fs: Firestore, data: DocumentData, path = 'carts/alice/items/i2') => setDoc(doc(fs, path), data);

    test('the owner reads, adds, changes the quantity and removes lines', async () => {
      await allowed(getDocs(collection(alice, 'carts/alice/items')));
      await allowed(put(alice, cartItem({ addedAt: serverTimestamp() })));
      const { titleSnapshotAr: _ar, ...withoutArabic } = cartItem({ imageSnapshot: null, selections: [] });
      await allowed(put(alice, withoutArabic));
      await allowed(updateDoc(doc(alice, 'carts/alice/items/i1'), { qty: 99, lineTotal: 99 * 15000 }));
      await allowed(deleteDoc(doc(alice, 'carts/alice/items/i1')));
    });
    test('a guest line merged on sign-in keeps its own addedAt', () =>
      allowed(put(alice, cartItem({ addedAt: Timestamp.fromDate(new Date('2026-10-01')) }))));
    for (const [label, data] of [
      ['qty 0', cartItem({ qty: 0 })],
      ['qty 100', cartItem({ qty: 100 })],
      ['qty 1.5', cartItem({ qty: 1.5 })],
      ['qty as a string', cartItem({ qty: '1' })],
      ['no productId', cartItem({ productId: undefined })],
      ['a price as a string', cartItem({ unitPrice: '15000' })],
      ['an unknown key', cartItem({ discount: 100 })],
      ['selections that are not a list', cartItem({ selections: 'none' })],
      ['31 selections', cartItem({ selections: Array.from({ length: 31 }, (_, i) => ({ groupId: `g${i}` })) })],
      ['addedAt as a string', cartItem({ addedAt: '2026-10-01' })],
    ] as Array<[string, DocumentData]>) {
      test(`denied: ${label}`, () => denied(put(alice, Object.fromEntries(Object.entries(data).filter(([, v]) => v !== undefined)))));
    }
    test("nobody else touches alice's cart — not even an admin", async () => {
      await denied(getDoc(doc(bob, 'carts/alice/items/i1')));
      await denied(put(bob, cartItem()));
      await denied(deleteDoc(doc(bob, 'carts/alice/items/i1')));
      await denied(getDocs(collection(admin, 'carts/alice/items')));
      await denied(getDoc(doc(anon, 'carts/alice/items/i1')));
    });
  });

  describe('wishlists/{uid}/items', () => {
    const put = (fs: Firestore, data: DocumentData, path = 'wishlists/alice/items/p2') => setDoc(doc(fs, path), data);

    test('the owner reads, adds and removes', async () => {
      await allowed(getDocs(collection(alice, 'wishlists/alice/items')));
      await allowed(put(alice, wishlistItem({ productId: 'p2', image: null, addedAt: serverTimestamp() })));
      await allowed(deleteDoc(doc(alice, 'wishlists/alice/items/p1')));
    });
    for (const [label, data] of [
      ['a productId that is not the doc id', wishlistItem({ productId: 'p9' })],
      ['no listId', (() => { const { listId: _l, ...rest } = wishlistItem({ productId: 'p2' }); return rest; })()],
      ['an unknown key', wishlistItem({ productId: 'p2', note: 'for mum' })],
      ['price as a string', wishlistItem({ productId: 'p2', price: 'cheap' })],
    ] as Array<[string, DocumentData]>) {
      test(`denied: ${label}`, () => denied(put(alice, data)));
    }
    test("nobody else touches alice's wishlist", async () => {
      await denied(getDoc(doc(bob, 'wishlists/alice/items/p1')));
      await denied(put(bob, wishlistItem({ productId: 'p2' })));
      await denied(getDoc(doc(anon, 'wishlists/alice/items/p1')));
    });
  });

  // ── catalogue & settings: public read, admin write ───────────────────────
  for (const path of [
    'products/p1',
    'categories/c1',
    'categories/c1/subcategories/s1',
    'banners/b1',
    'gift_card_templates/g1',
    // stores: firestore.phase8.rules.test.ts (pending stores are private, writes are field-limited)
    'app_settings/general',
  ]) {
    describe(path, () => {
      test('signed out reads', () => allowed(getDoc(doc(anon, path))));
      test('customer cannot write', async () => {
        await denied(setDoc(doc(alice, path), { hacked: true }, { merge: true }));
        await denied(deleteDoc(doc(alice, path)));
        await denied(setDoc(doc(anon, path), { hacked: true }, { merge: true }));
      });
      test('admin writes', () => allowed(setDoc(doc(admin, path), { edited: true }, { merge: true })));
    });
  }
  test('categories: only admins switch a category to "coming soon" (SRS §5.7a)', async () => {
    const soon = { comingSoon: true, comingSoonNote: 'Arriving before Eid', comingSoonSince: serverTimestamp() };
    await denied(updateDoc(doc(alice, 'categories/c1'), soon));
    await denied(updateDoc(doc(alice, 'categories/c1'), { isActive: false }));
    await denied(updateDoc(doc(anon, 'categories/c1'), { comingSoon: true }));
    await allowed(updateDoc(doc(admin, 'categories/c1'), soon));
    await allowed(getDoc(doc(anon, 'categories/c1')));
    await denied(updateDoc(doc(alice, 'categories/c1'), { comingSoon: false, comingSoonNote: deleteField() }));
  });
  test('catalogue lists are public', async () => {
    await allowed(getDocs(collection(anon, 'products')));
    await allowed(getDocs(collection(anon, 'categories')));
    await allowed(getDocs(collection(anon, 'app_settings')));
  });

  // ── admin-only ───────────────────────────────────────────────────────────
  describe('admins/{uid}', () => {
    test('owner reads own profile (the claim is not needed to read it)', () =>
      allowed(getDoc(doc(as('admin-2'), 'admins/admin-2'))));
    test('an admin reads any profile and lists them', async () => {
      await allowed(getDoc(doc(admin, 'admins/admin-2')));
      await allowed(getDocs(collection(admin, 'admins')));
    });
    test('customers and visitors cannot read or list', async () => {
      await denied(getDoc(doc(alice, 'admins/admin-1')));
      await denied(getDoc(doc(anon, 'admins/admin-1')));
      await denied(getDocs(collection(alice, 'admins')));
      await denied(getDocs(collection(as('admin-2'), 'admins'))); // own doc only, without the claim
    });
    test('no client writes — only setAdminClaim / create-admin (Admin SDK)', async () => {
      await denied(setDoc(doc(alice, 'admins/alice'), { role: 'super' }));
      await denied(setDoc(doc(admin, 'admins/alice'), { name: 'Alice', role: 'ops', permissions: [] }));
      await denied(updateDoc(doc(admin, 'admins/admin-2'), { role: 'super' }));
      await denied(updateDoc(doc(admin, 'admins/admin-1'), { role: 'super' })); // own doc, even with the claim
      await denied(updateDoc(doc(as('admin-2'), 'admins/admin-2'), { role: 'super' }));
      await denied(deleteDoc(doc(admin, 'admins/admin-2')));
      await denied(deleteDoc(doc(as('admin-2'), 'admins/admin-2')));
    });
  });

  describe('admin_audit_log/{id}', () => {
    /** Exactly what the dashboard's AuditLog.add writes. */
    const entry = (over: DocumentData = {}): DocumentData => ({
      adminUid: 'admin-1',
      action: 'product.update',
      target: 'products/p1',
      before: { price: 15000 },
      after: { price: 17000 },
      at: serverTimestamp(),
      ...over,
    });
    const create = (fs: Firestore, data: DocumentData, id = 'l-new') => setDoc(doc(fs, `admin_audit_log/${id}`), data);

    test('an admin appends an entry in their own name', () => allowed(create(admin, entry())));
    test('before / after may be null or absent', async () => {
      await allowed(create(admin, entry({ before: null, after: { title: 'New' } }), 'l-a'));
      const { before: _b, after: _a, ...minimal } = entry();
      await allowed(create(admin, minimal, 'l-b'));
    });
    test('the change and its entry in one batch (the dashboard pattern)', async () => {
      const batch = writeBatch(admin);
      batch.update(doc(admin, 'products/p1'), { price: 17000 });
      batch.set(doc(collection(admin, 'admin_audit_log')), entry());
      await allowed(batch.commit());
    });

    for (const [label, over] of [
      ["another admin's uid (forged adminUid)", { adminUid: 'admin-2' }],
      ['a client-side `at`', { at: Timestamp.now() }],
      ['an old `at`', { at: Timestamp.fromDate(new Date('2020-01-01')) }],
      ['an unknown key', { ip: '1.2.3.4' }],
      ['an action that is not a string', { action: 42 }],
      ['a target that is not a string', { target: ['products/p1'] }],
    ] as Array<[string, DocumentData]>) {
      test(`admin denied: ${label}`, () => denied(create(admin, entry(over))));
    }
    for (const field of ['adminUid', 'at', 'action', 'target']) {
      test(`admin denied without ${field}`, () => {
        const { [field]: _omitted, ...rest } = entry();
        return denied(create(admin, rest));
      });
    }
    test('a forged entry cannot ride along in a batch', async () => {
      const batch = writeBatch(admin);
      batch.update(doc(admin, 'products/p1'), { price: 1 });
      batch.set(doc(collection(admin, 'admin_audit_log')), entry({ adminUid: 'admin-2' }));
      await denied(batch.commit());
    });
    test('a non-admin cannot create an entry, even in their own name', async () => {
      await denied(create(alice, entry({ adminUid: 'alice' })));
      await denied(create(as('admin-2'), entry({ adminUid: 'admin-2' }))); // admins doc, but no claim
      await denied(create(anon, entry({ adminUid: 'anon' })));
    });
    test('nobody edits or deletes an entry — not even its author', async () => {
      await denied(updateDoc(doc(admin, 'admin_audit_log/l1'), { action: 'x' }));
      await denied(updateDoc(doc(admin, 'admin_audit_log/l1'), { at: serverTimestamp() }));
      await denied(setDoc(doc(admin, 'admin_audit_log/l1'), entry())); // overwrite = update
      await denied(deleteDoc(doc(admin, 'admin_audit_log/l1')));
      await denied(deleteDoc(doc(alice, 'admin_audit_log/l1')));
    });
    test('admins read and list; customers and visitors cannot', async () => {
      await allowed(getDoc(doc(admin, 'admin_audit_log/l1')));
      await allowed(getDocs(collection(admin, 'admin_audit_log')));
      await denied(getDoc(doc(alice, 'admin_audit_log/l1')));
      await denied(getDocs(collection(alice, 'admin_audit_log')));
      await denied(getDoc(doc(anon, 'admin_audit_log/l1')));
    });
  });

  describe('function_runs / counters: Cloud Functions only', () => {
    const clients: Array<[string, () => Firestore]> = [
      ['signed-in user', () => alice],
      ['signed-out visitor', () => anon],
      ['admin claim', () => admin],
    ];
    for (const [who, fs] of clients) {
      test(`${who}: no read, list or write`, async () => {
        for (const [name, path] of [
          ['function_runs', 'function_runs/onUserCreate:alice'],
          ['counters', 'counters/orders-2610'],
        ]) {
          await denied(getDoc(doc(fs(), path)));
          await denied(getDocs(collection(fs(), name)));
          await denied(setDoc(doc(fs(), path), { next: 1, key: 'x' }));
          await denied(updateDoc(doc(fs(), path), { next: 43 }));
          await denied(deleteDoc(doc(fs(), path)));
        }
        await denied(setDoc(doc(fs(), 'function_runs/x'), { key: 'x' }));
        await denied(setDoc(doc(fs(), 'counters/orders-2611'), { next: 1 }));
      });
    }
  });

  // ── phone OTP: Cloud Functions only ──────────────────────────────────────
  describe('otp_codes / otp_throttle / otp_debug', () => {
    const otpDocs = [
      'otp_codes/login:9647501234567',
      'otp_codes/changePhone:9647501234567',
      'otp_throttle/phone:9647501234567',
      'otp_throttle/global:2026-10-20',
      'otp_debug/9647501234567',
    ];
    // Getters: the clients are created in before(), after this describe body runs.
    const clients: Array<[string, () => Firestore]> = [
      ['signed-in user', () => alice],
      ['signed-out visitor', () => anon],
      ['admin claim', () => admin],
    ];

    for (const [who, fs] of clients) {
      test(`${who}: cannot read a single doc`, async () => {
        for (const path of otpDocs) await denied(getDoc(doc(fs(), path)));
      });
      test(`${who}: cannot list`, async () => {
        for (const name of ['otp_codes', 'otp_throttle', 'otp_debug']) await denied(getDocs(collection(fs(), name)));
        await denied(getDocs(query(collection(fs(), 'otp_codes'), where('uid', '==', 'alice'))));
      });
      test(`${who}: cannot create, update or delete`, async () => {
        for (const path of otpDocs) {
          await denied(setDoc(doc(fs(), path), { attempts: 0 }));
          await denied(updateDoc(doc(fs(), path), { attempts: 0, hits: [], sent: 0 }));
          await denied(deleteDoc(doc(fs(), path)));
        }
        await denied(setDoc(doc(fs(), 'otp_codes/login:9647709998877'), { hash: 'x:y', attempts: 0 }));
        await denied(setDoc(doc(fs(), 'otp_debug/9647709998877'), { code: '000000' }));
      });
    }
  });

  // ── default deny (later phases add these) ────────────────────────────────
  // gift_cards / special_requests / stores (Phase 8): firestore.phase8.rules.test.ts.
  test('collections without rules yet are denied', async () => {
    await denied(setDoc(doc(alice, 'gift_cards/g1'), { purchaserUid: 'alice' }));
    await denied(setDoc(doc(alice, 'special_requests/r1'), { userId: 'alice' }));
    await denied(setDoc(doc(alice, 'carts/alice'), { note: 'parent doc' }));
    await denied(getDoc(doc(anon, 'anything/x')));
  });
});
