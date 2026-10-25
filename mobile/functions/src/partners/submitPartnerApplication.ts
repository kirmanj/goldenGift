/**
 * `submitPartnerApplication` (SRS §5.25 "Sell on Golden Gift"): the signed-in
 * customer applies with `PartnerApplication.toMap()` = `{ storeName, ownerName,
 * phone (E.164), city, category, instagram?, samplePhotos (≤ 5) }` → `{ storeId }`.
 *
 * One store per owner: in one transaction (which also reads the owner's stores,
 * so two concurrent submissions cannot both pass) it creates
 *  - `stores/{id}` — the public part (§6.2): `name` (+Ar/Ku = the store name),
 *    empty description, `ownerUid`, `phone`, `city`, `status: pendingApproval`,
 *    zero counters and commission, `createdAt`;
 *  - `stores/{id}/private/application` — what the partner sent, readable by the
 *    owner and admins only (`ownerUid` is on it too, so a rejected application's
 *    archive stays readable by its owner after the store doc is gone).
 * The dashboard lists pending stores (Stores / Partners) — there is no admin push.
 *
 * Sample photos must be the caller's own uploads (`partner_applications/{uid}/…`
 * download URLs of this project). At most 5 applications per account per rolling
 * day (`resource-exhausted`): a rejected applicant may apply again, but not in a loop.
 *
 * Errors: unauthenticated; invalid-argument; already-exists (the account already
 * owns or applied for a store); permission-denied (blocked / deleted account);
 * resource-exhausted.
 */
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { normalizePhone } from '../auth/phone';
import { parseCities } from '../orders/checkoutRules';
import { isDocId } from '../orders/createOrderDoc';
import { FirestorePaths as P } from '../shared/paths';
import { consumeRateLimit, type RateLimit } from '../shared/rateLimit';
import { isOwnUploadUrl } from '../shared/storageUrls';
import { graphemeLength } from '../shared/text';

export const STORE_NAME_MIN = 2;
export const STORE_NAME_MAX = 60;
export const OWNER_NAME_MIN = 2;
export const OWNER_NAME_MAX = 50;
export const CATEGORY_MAX = 100;
export const MAX_SAMPLE_PHOTOS = 5;
export const MAX_URL_LENGTH = 2048;
/** Applications per account per rolling day. */
export const APPLICATION_RATE_LIMIT: RateLimit = { limit: 5, windowMs: 24 * 60 * 60 * 1000 };

/** `stores/{id}/private/application`. */
export const APPLICATION_DOC = 'application';
export const storeApplicationPath = (storeId: string) => `${P.stores}/${storeId}/${P.storePrivate}/${APPLICATION_DOC}`;

export interface PartnerApplication {
  storeName: string;
  ownerName: string;
  phone: string;
  city: string;
  category: string;
  instagram: string | null;
  samplePhotos: string[];
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

function text(v: unknown, field: string, min: number, max: number): string {
  if (typeof v !== 'string') throw bad(`\`${field}\` is required.`);
  const value = v.trim();
  const length = graphemeLength(value);
  if (length < min || length > max) throw bad(`\`${field}\` must be ${min}–${max} characters.`);
  return value;
}

export function parsePartnerApplication(data: unknown): PartnerApplication {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw bad('Expected { storeName, ownerName, phone, city, category, instagram?, samplePhotos? }.');
  }
  const d = data as Record<string, unknown>;
  const phone = normalizePhone(d.phone);
  if (phone === null) throw bad('`phone` is not a valid phone number.');
  if (!isDocId(d.city, 64)) throw bad('`city` is missing or invalid.');

  let instagram: string | null = null;
  if (d.instagram !== undefined && d.instagram !== null && d.instagram !== '') {
    const handle = typeof d.instagram === 'string' ? d.instagram.trim().replace(/^@/, '') : '';
    if (!/^[A-Za-z0-9._]{1,30}$/.test(handle)) throw bad('`instagram` is not an Instagram handle.');
    instagram = handle;
  }

  const photos = d.samplePhotos ?? [];
  if (!Array.isArray(photos) || photos.length > MAX_SAMPLE_PHOTOS) {
    throw bad(`\`samplePhotos\` must be a list of at most ${MAX_SAMPLE_PHOTOS} URLs.`);
  }
  for (const url of photos) {
    if (typeof url !== 'string' || url.length > MAX_URL_LENGTH || !/^https?:\/\/\S+$/.test(url)) {
      throw bad('`samplePhotos` must hold http(s) URLs.');
    }
  }

  return {
    storeName: text(d.storeName, 'storeName', STORE_NAME_MIN, STORE_NAME_MAX),
    ownerName: text(d.ownerName, 'ownerName', OWNER_NAME_MIN, OWNER_NAME_MAX),
    phone,
    city: d.city,
    category: text(d.category, 'category', 1, CATEGORY_MAX),
    instagram,
    samplePhotos: photos as string[],
  };
}

export async function submitPartnerApplicationCore(
  db: Firestore,
  data: unknown,
  uid: string | undefined,
  options: { now?: () => number } = {},
): Promise<{ storeId: string }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to apply.');
  const application = parsePartnerApplication(data);
  if (!application.samplePhotos.every((url) => isOwnUploadUrl(url, `partner_applications/${uid}/`))) {
    throw bad('`samplePhotos` must be photos you uploaded in the app.');
  }
  await consumeRateLimit(
    db,
    `rl:partnerApply:${uid}`,
    APPLICATION_RATE_LIMIT,
    (options.now ?? Date.now)(),
    'Too many applications today. Please try again tomorrow.',
  );
  const stores = db.collection(P.stores);

  return db.runTransaction(async (tx) => {
    // ── Reads ──
    const [userSnap, citiesSnap] = await tx.getAll(db.collection(P.users).doc(uid), db.collection(P.appSettings).doc('cities'));
    const user = userSnap.data();
    if (user?.isDeleted === true || user?.isBlocked === true) {
      throw new HttpsError('permission-denied', 'This account cannot apply.');
    }
    const cities = parseCities(citiesSnap.data());
    if (!cities.some((c) => c.id === application.city && c.isActive)) throw bad('`city` is not a city we serve.');
    const owned = await tx.get(stores.where('ownerUid', '==', uid).limit(1));
    if (!owned.empty) throw new HttpsError('already-exists', 'You already have a store or an application.');

    // ── Writes ──
    const ref = stores.doc();
    const ts = FieldValue.serverTimestamp();
    tx.create(ref, {
      name: application.storeName,
      nameAr: application.storeName,
      nameKu: application.storeName,
      description: '',
      logoUrl: null,
      coverUrl: null,
      ownerUid: uid,
      phone: application.phone,
      city: application.city,
      status: 'pendingApproval',
      ratingAvg: 0,
      ratingCount: 0,
      productCount: 0,
      ordersCount: 0,
      commissionPercent: 0,
      createdAt: ts,
      updatedAt: ts,
    });
    tx.create(ref.collection(P.storePrivate).doc(APPLICATION_DOC), {
      ...application,
      ownerUid: uid,
      submittedAt: ts,
    });
    return { storeId: ref.id };
  });
}
