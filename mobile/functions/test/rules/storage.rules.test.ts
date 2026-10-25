import { readFileSync } from 'node:fs';
import { after, before, describe, test } from 'node:test';
import {
  initializeTestEnvironment,
  type RulesTestContext,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { deleteObject, getMetadata, ref, uploadBytes, type FirebaseStorage } from 'firebase/storage';
import { PROJECT_ID, needsEnv, runId } from '../emulators';
import { allowed, denied, rulesFile } from './rulesEnv';

const STORAGE_RULES_PROJECT_ID = 'demo-goldengift-storage-rules';
const BUCKET = `gs://${STORAGE_RULES_PROJECT_ID}.appspot.com`;
/**
 * `firestore.get()` in Storage rules reads the Firestore of the project the
 * emulators run as (`--project`, GCLOUD_PROJECT), not the test env's project id,
 * so the order it looks up is seeded there with the Admin SDK (unique id, deleted after).
 */
const EMULATOR_PROJECT = process.env.GCLOUD_PROJECT ?? PROJECT_ID;
const ORDER_ID = `storage-rules-${runId()}`;
/** Phase 8: a product of store-a (seeded in Firestore like the order) and an id no product has. */
const PRODUCT_A = `storage-rules-pa-${runId()}`;
const PRODUCT_NEW = `storage-rules-new-${runId()}`;
/** Phase 10: admins need the claim AND a live admins/{uid} doc (seeded like the order). */
const ADMIN_UID = `storage-rules-admin-${runId()}`;
const REVOKED_ADMIN_UID = `storage-rules-revoked-${runId()}`;
/** Objects Phase 8 tests create (removed in after()). */
const PHASE8_CREATED = [
  'special_requests/alice/r1/1.jpg',
  'partner_applications/alice/1.jpg',
  'gift_cards/alice/req-1/1.jpg',
  'reviews/alice/p1/1.jpg',
  `products/${PRODUCT_A}/1.jpg`,
  `products/${PRODUCT_A}/options/size-big.jpg`,
  `products/${PRODUCT_NEW}/1.jpg`,
  'stores/store-a/logo.jpg',
  'stores/store-a/cover.jpg',
  'stores/store-b/logo.jpg',
  'gift_card_templates/t1.jpg',
];
/** Objects Phase 11 tests create (removed in after()). */
const PHASE11_CREATED = ['reels/r1.mp4', 'reels/r1.jpg', 'reels/r2.mp4'];
const MB = 1024 * 1024;
const mp4 = { contentType: 'video/mp4' };
const jpeg = { contentType: 'image/jpeg' };
/** Seeded objects (written with rules disabled, removed in after()). */
const SEEDED = [
  'users/alice/avatar.jpg',
  'users/bob/avatar.jpg',
  'users/alice/other.jpg',
  'products/p1/1.jpg',
  'uploads/alice/item-1/1.jpg',
  `orders/${ORDER_ID}/item-1/1.jpg`,
  'banners/b1.jpg',
  'broadcasts/x.jpg',
  'reels/seeded.mp4',
];

/** mobile/storage.production.rules (not deployed until Phase 10). */
describe('storage.production.rules', { skip: needsEnv('FIREBASE_STORAGE_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST') }, () => {
  let env: RulesTestEnvironment;
  const orderApp = initializeApp({ projectId: EMULATOR_PROJECT }, `storage-rules-orders-${ORDER_ID}`);
  const orderDb = getFirestore(orderApp);
  let alice: FirebaseStorage, bob: FirebaseStorage, admin: FirebaseStorage, anon: FirebaseStorage;
  /** The admin claim without an admins doc (revoked, token not refreshed yet). */
  let revokedAdmin: FirebaseStorage;
  /** Partners (claim `seller == storeId`). */
  let sellerA: FirebaseStorage, sellerB: FirebaseStorage;
  const storage = (ctx: RulesTestContext) => ctx.storage(BUCKET) as unknown as FirebaseStorage;
  const put = (s: FirebaseStorage, path: string, bytes = 1024, metadata: object = jpeg) =>
    uploadBytes(ref(s, path), new Uint8Array(bytes), metadata);

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: STORAGE_RULES_PROJECT_ID,
      storage: { rules: readFileSync(rulesFile('storage.production.rules'), 'utf8') },
    });
    alice = storage(env.authenticatedContext('alice'));
    bob = storage(env.authenticatedContext('bob'));
    admin = storage(env.authenticatedContext(ADMIN_UID, { admin: true }));
    revokedAdmin = storage(env.authenticatedContext(REVOKED_ADMIN_UID, { admin: true }));
    anon = storage(env.unauthenticatedContext());
    sellerA = storage(env.authenticatedContext('seller-a', { seller: 'store-a' }));
    sellerB = storage(env.authenticatedContext('seller-b', { seller: 'store-b' }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      const s = storage(ctx);
      for (const path of SEEDED) await put(s, path);
    });
    await orderDb.doc(`orders/${ORDER_ID}`).set({ userId: 'alice', total: 1 });
    await orderDb.doc(`products/${PRODUCT_A}`).set({ storeId: 'store-a', title: 'Storage rules test' });
    await orderDb.doc(`admins/${ADMIN_UID}`).set({ role: 'content', name: 'Storage rules test' });
  });

  after(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const s = storage(ctx);
      for (const path of [...SEEDED, ...PHASE8_CREATED, ...PHASE11_CREATED, 'uploads/alice/item-2/1.jpg', 'products/p1/2.jpg', 'products/p1/options/frame-oak.jpg', 'categories/c1.png', 'banners/b2.jpg', 'broadcasts/y.jpg']) {
        await deleteObject(ref(s, path)).catch(() => undefined);
      }
    });
    await orderDb.doc(`orders/${ORDER_ID}`).delete();
    await orderDb.doc(`products/${PRODUCT_A}`).delete();
    await orderDb.doc(`admins/${ADMIN_UID}`).delete();
    await deleteApp(orderApp);
    await env.cleanup();
    await restoreDevRules();
  });

  test('avatars are publicly readable', async () => {
    await allowed(getMetadata(ref(anon, 'users/alice/avatar.jpg')));
    await allowed(getMetadata(ref(bob, 'users/alice/avatar.jpg')));
  });

  test('owner uploads an image under 10 MB', async () => {
    await allowed(put(alice, 'users/alice/avatar.jpg'));
    await allowed(put(alice, 'users/alice/avatar.jpg', 2048, { contentType: 'image/png' }));
    await allowed(put(alice, 'users/alice/avatar.jpg', 10 * MB - 1));
  });

  test('owner cannot upload a non-image', async () => {
    await denied(put(alice, 'users/alice/avatar.jpg', 1024, { contentType: 'text/plain' }));
    await denied(put(alice, 'users/alice/avatar.jpg', 1024, { contentType: 'application/pdf' }));
    await denied(put(alice, 'users/alice/avatar.jpg', 1024, { contentType: 'application/octet-stream' }));
  });

  test('owner cannot upload 10 MB or more', () => denied(put(alice, 'users/alice/avatar.jpg', 10 * MB)));

  test("others cannot upload to alice's avatar", async () => {
    await denied(put(bob, 'users/alice/avatar.jpg'));
    await denied(put(anon, 'users/alice/avatar.jpg'));
    await denied(put(admin, 'users/alice/avatar.jpg'));
  });

  test('only the owner deletes the avatar', async () => {
    await denied(deleteObject(ref(bob, 'users/alice/avatar.jpg')));
    await denied(deleteObject(ref(anon, 'users/alice/avatar.jpg')));
    await allowed(deleteObject(ref(bob, 'users/bob/avatar.jpg')));
  });

  // ── customer photos (Phase 4 upload, Phase 6 rules) ──
  test('the owner uploads cart photos (images under 10 MB) and reads them back', async () => {
    await allowed(put(alice, 'uploads/alice/item-2/1.jpg'));
    await allowed(put(alice, 'uploads/alice/item-2/1.jpg', 10 * MB - 1));
    await allowed(getMetadata(ref(alice, 'uploads/alice/item-1/1.jpg')));
    await allowed(deleteObject(ref(alice, 'uploads/alice/item-2/1.jpg')));
  });
  test('cart photos: no other type, no 10 MB, nobody else uploads', async () => {
    await denied(put(alice, 'uploads/alice/item-2/1.jpg', 1024, { contentType: 'application/pdf' }));
    await denied(put(alice, 'uploads/alice/item-2/1.jpg', 10 * MB));
    await denied(put(bob, 'uploads/alice/item-2/1.jpg'));
    await denied(put(anon, 'uploads/alice/item-2/1.jpg'));
    await denied(put(admin, 'uploads/alice/item-2/1.jpg'));
  });
  test('cart photos are read by their owner and admins only', async () => {
    await allowed(getMetadata(ref(admin, 'uploads/alice/item-1/1.jpg')));
    await denied(getMetadata(ref(bob, 'uploads/alice/item-1/1.jpg')));
    await denied(getMetadata(ref(anon, 'uploads/alice/item-1/1.jpg')));
    await denied(deleteObject(ref(bob, 'uploads/alice/item-1/1.jpg')));
  });

  // ── order photos (copied by placeOrder) ──
  test("order photos: the order's customer and admins read; nobody writes", async () => {
    await allowed(getMetadata(ref(alice, `orders/${ORDER_ID}/item-1/1.jpg`)));
    await allowed(getMetadata(ref(admin, `orders/${ORDER_ID}/item-1/1.jpg`)));
    await denied(getMetadata(ref(bob, `orders/${ORDER_ID}/item-1/1.jpg`)));
    await denied(getMetadata(ref(anon, `orders/${ORDER_ID}/item-1/1.jpg`)));
    await denied(put(alice, `orders/${ORDER_ID}/item-1/2.jpg`));
    await denied(put(admin, `orders/${ORDER_ID}/item-1/2.jpg`));
    await denied(deleteObject(ref(alice, `orders/${ORDER_ID}/item-1/1.jpg`)));
  });

  // ── catalogue & broadcast images (admin dashboard) ──
  test('catalogue and broadcast images are public', async () => {
    for (const path of ['products/p1/1.jpg', 'banners/b1.jpg', 'broadcasts/x.jpg']) {
      await allowed(getMetadata(ref(anon, path)));
    }
  });
  test('admins upload catalogue and broadcast images', async () => {
    for (const path of ['products/p1/2.jpg', 'products/p1/options/frame-oak.jpg', 'banners/b2.jpg', 'broadcasts/y.jpg']) {
      await allowed(put(admin, path));
    }
    await allowed(put(admin, 'categories/c1.png', 2048, { contentType: 'image/png' }));
    await allowed(deleteObject(ref(admin, 'banners/b2.jpg')));
  });
  test('customers cannot upload or delete catalogue images; admins only images under 10 MB', async () => {
    await denied(put(alice, 'products/p1/3.jpg'));
    await denied(put(alice, 'broadcasts/z.jpg'));
    await denied(put(anon, 'categories/c2.png'));
    await denied(deleteObject(ref(alice, 'products/p1/1.jpg')));
    await denied(put(admin, 'products/p1/3.jpg', 1024, { contentType: 'text/html' }));
    await denied(put(admin, 'broadcasts/z.jpg', 10 * MB));
  });

  // ── Phase 8: customer uploads (special requests, partner applications, gift cards, reviews) ──
  for (const path of ['special_requests/alice/r1/1.jpg', 'partner_applications/alice/1.jpg', 'gift_cards/alice/req-1/1.jpg', 'reviews/alice/p1/1.jpg']) {
    test(`${path.split('/')[0]}: the owner uploads images under 10 MB; owner and admins read`, async () => {
      await allowed(put(alice, path));
      await allowed(getMetadata(ref(alice, path)));
      await allowed(getMetadata(ref(admin, path)));
      await denied(getMetadata(ref(bob, path)));
      await denied(getMetadata(ref(anon, path)));
      await denied(put(alice, path, 1024, { contentType: 'application/pdf' }));
      await denied(put(alice, path, 10 * MB));
      await denied(put(bob, path));
      await denied(put(admin, path));
      await denied(deleteObject(ref(bob, path)));
    });
  }

  // ── Phase 9: review photos at the app's path (ReviewTarget.photoFolder) ──
  test('reviews/{uid}/{orderId}_{productId}/{n}.jpg: the author uploads, replaces and deletes; nobody else', async () => {
    const path = 'reviews/alice/order-1_p1/1.jpg';
    await allowed(put(alice, path));
    await allowed(put(alice, path, 2048, { contentType: 'image/png' }));
    await denied(put(alice, 'reviews/bob/order-1_p1/1.jpg'));
    await denied(getMetadata(ref(sellerA, path)));
    await denied(deleteObject(ref(admin, path)));
    await allowed(deleteObject(ref(alice, path)));
  });

  // ── Phase 8: sellers ──
  test("a seller uploads images of its own products and of a product it is creating", async () => {
    await allowed(put(sellerA, `products/${PRODUCT_A}/1.jpg`));
    await allowed(put(sellerA, `products/${PRODUCT_A}/options/size-big.jpg`));
    await allowed(put(sellerA, `products/${PRODUCT_NEW}/1.jpg`));
    await allowed(deleteObject(ref(sellerA, `products/${PRODUCT_A}/options/size-big.jpg`)));
  });
  test("a seller cannot touch another store's product images", async () => {
    await denied(put(sellerB, `products/${PRODUCT_A}/2.jpg`));
    await denied(deleteObject(ref(sellerB, `products/${PRODUCT_A}/1.jpg`)));
    await denied(put(sellerA, `products/${PRODUCT_A}/2.jpg`, 1024, { contentType: 'text/html' }));
  });
  test("store logo / cover: admins and that store's seller; public read", async () => {
    await allowed(put(sellerA, 'stores/store-a/logo.jpg'));
    await allowed(put(sellerA, 'stores/store-a/cover.jpg'));
    await allowed(put(admin, 'stores/store-b/logo.jpg'));
    await allowed(getMetadata(ref(anon, 'stores/store-a/logo.jpg')));
    await denied(put(sellerB, 'stores/store-a/logo.jpg'));
    await denied(put(alice, 'stores/store-a/logo.jpg'));
    await denied(put(sellerA, 'stores/store-a/other.jpg'));
    await denied(put(sellerA, 'stores/store-a/logo.jpg', 10 * MB));
  });
  test('gift card template artwork: admins write, everyone reads', async () => {
    await allowed(put(admin, 'gift_card_templates/t1.jpg'));
    await allowed(getMetadata(ref(anon, 'gift_card_templates/t1.jpg')));
    await denied(put(alice, 'gift_card_templates/t2.jpg'));
    await denied(put(sellerA, 'gift_card_templates/t2.jpg'));
  });

  // ── Phase 11: reels (video + poster) ──
  test('reels: admins upload the MP4 video and its poster; everyone reads them', async () => {
    await allowed(put(admin, 'reels/r1.mp4', 2 * MB, mp4));
    await allowed(put(admin, 'reels/r1.jpg'));
    await allowed(put(admin, 'reels/r1.jpg', 2048, { contentType: 'image/png' }));
    for (const who of [anon, alice, sellerA]) {
      await allowed(getMetadata(ref(who, 'reels/r1.mp4')));
      await allowed(getMetadata(ref(who, 'reels/seeded.mp4')));
    }
  });
  test('reels: 100 MB or more, empty, other video types and non-video files are refused', async () => {
    await denied(put(admin, 'reels/r2.mp4', 100 * MB, mp4));
    await denied(put(admin, 'reels/r2.mp4', 0, mp4));
    const notMp4 = ['video/quicktime', 'video/webm', 'application/octet-stream', 'text/html', 'image/svg+xml'];
    for (const contentType of notMp4) {
      await denied(put(admin, 'reels/r2.mp4', 1024, { contentType }));
    }
    await denied(put(admin, 'reels/r2.jpg', 10 * MB)); // posters are images under 10 MB
    await allowed(put(admin, 'reels/r2.mp4', 100 * MB - 1, mp4));
  });
  test('reels: customers, sellers, signed-out visitors and revoked admins upload or delete nothing', async () => {
    for (const who of [anon, alice, sellerA, revokedAdmin]) {
      await denied(put(who, 'reels/x.mp4', 1024, mp4));
      await denied(put(who, 'reels/x.jpg'));
      await denied(deleteObject(ref(who, 'reels/seeded.mp4')));
    }
  });
  test('videos only in reels/: an MP4 anywhere else is refused, even for admins', async () => {
    for (const path of ['banners/v.jpg', 'products/p1/v.jpg', 'broadcasts/v.jpg', 'categories/v.png']) {
      await denied(put(admin, path, 1024, mp4));
    }
    await denied(put(alice, 'uploads/alice/item-2/v.jpg', 1024, mp4));
  });
  test('reels: admins delete the files (the dashboard, then onReelWrite as a backstop)', async () => {
    await allowed(put(admin, 'reels/r1.jpg'));
    await allowed(deleteObject(ref(admin, 'reels/r1.jpg')));
  });

  // ── Phase 10 ──
  test('admins: the claim alone is not enough (revoked admin, live admins doc gone)', async () => {
    await denied(put(revokedAdmin, 'banners/revoked.jpg'));
    await denied(getMetadata(ref(revokedAdmin, 'uploads/alice/item-1/1.jpg')));
    await denied(deleteObject(ref(revokedAdmin, 'banners/b1.jpg')));
    await allowed(getMetadata(ref(admin, 'uploads/alice/item-1/1.jpg')));
  });
  test('raster images only (no SVG — it can carry script), never empty, on every write path', async () => {
    const svg = { contentType: 'image/svg+xml' };
    for (const [who, path] of [
      [alice, 'users/alice/avatar.jpg'],
      [alice, 'uploads/alice/item-9/1.jpg'],
      [alice, 'special_requests/alice/r9/1.jpg'],
      [alice, 'gift_cards/alice/req-9/1.jpg'],
      [admin, 'banners/svg.jpg'],
      [admin, 'categories/svg.png'],
      [admin, 'gift_card_templates/svg.jpg'],
      [sellerA, `products/${PRODUCT_A}/9.jpg`],
    ] as Array<[FirebaseStorage, string]>) {
      await denied(put(who, path, 1024, svg));
      await denied(put(who, path, 0));
    }
    for (const contentType of ['image/png', 'image/webp', 'image/heic']) {
      await allowed(put(alice, 'uploads/alice/item-2/1.jpg', 1024, { contentType }));
    }
  });
  test('no public write anywhere: a signed-out visitor writes nothing', async () => {
    for (const path of [
      'users/alice/avatar.jpg',
      'uploads/alice/x/1.jpg',
      `orders/${ORDER_ID}/item-1/2.jpg`,
      'special_requests/alice/r1/2.jpg',
      'partner_applications/alice/2.jpg',
      'gift_cards/alice/req-1/2.jpg',
      'reviews/alice/o_p/2.jpg',
      'products/p1/9.jpg',
      'stores/store-a/logo.jpg',
      'gift_card_templates/t9.jpg',
      'categories/c9.png',
      'banners/b9.jpg',
      'broadcasts/b9.jpg',
      'reels/r9.jpg',
      'anything/else.jpg',
    ]) {
      await denied(put(anon, path));
    }
  });

  test('every other path is denied', async () => {
    await denied(put(alice, 'users/alice/other.jpg'));
    await denied(getMetadata(ref(anon, 'users/alice/other.jpg')));
    await denied(getMetadata(ref(alice, 'users/alice/other.jpg')));
    await denied(put(admin, 'users/alice/other.jpg'));
    await denied(put(alice, 'special_requests/r1/1.jpg'));
    await denied(put(admin, 'random/file.jpg'));
  });
});

/** Storage rules are emulator-wide: put the dev-mode rules back for everyone else. */
async function restoreDevRules(): Promise<void> {
  const res = await fetch(`http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/internal/setRules`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      rules: { files: [{ name: 'storage.rules', content: readFileSync(rulesFile('storage.rules'), 'utf8') }] },
    }),
  });
  if (!res.ok) throw new Error(`restoring storage.rules failed: ${res.status} ${await res.text()}`);
}
