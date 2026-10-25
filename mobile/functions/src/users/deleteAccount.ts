import type { Auth } from 'firebase-admin/auth';
import { FieldValue, type CollectionReference, type Firestore } from 'firebase-admin/firestore';
import type { Storage } from 'firebase-admin/storage';
import { FirestorePaths as P } from '../shared/paths';

type Bucket = ReturnType<Storage['bucket']>;

export interface DeleteAccountDeps {
  db: Firestore;
  auth: Auth;
  /** The default Storage bucket. May throw when the project has none configured. */
  bucket: () => Bucket;
}

export interface DeleteAccountResult {
  /** false when there was no `users/{uid}` doc to anonymize. */
  anonymized: boolean;
  deletedDocs: number;
  /** Files removed under `users/{uid}/`; null when there is no bucket. */
  deletedFiles: number | null;
  /** false when the Auth user was already gone (repeat call). */
  deletedAuthUser: boolean;
}

/** Writes per batch (Firestore allows 500). */
const BATCH_SIZE = 400;

/** What the user doc keeps after deletion: no personal data (SRS AUTH-7). */
const ANONYMIZED = {
  name: 'Deleted user',
  email: null,
  phone: null,
  photoUrl: null,
  birthday: null,
  gender: null,
  city: null,
  referralCodeEntered: null,
  fcmTokens: [],
  notificationsEnabled: false,
  isDeleted: true,
} as const;

/**
 * Account deletion (SRS AUTH-7, §7 `deleteAccount`), in this order:
 *  1. anonymize `users/{uid}` — the doc stays because orders reference it;
 *  2. delete addresses, saved cards, cart and wishlist;
 *  3. delete Storage files under `users/{uid}/` (avatar);
 *  4. delete the Auth user — last, so a failed step can be retried by calling
 *     again while the user is still signed in.
 *
 * Idempotent: every step tolerates having run before (`deletedAt` keeps the
 * first deletion time). Orders, wallets and referrals are kept for accounting.
 */
export async function deleteUserAccount(deps: DeleteAccountDeps, uid: string): Promise<DeleteAccountResult> {
  const { db, auth } = deps;

  const anonymized = await anonymizeUser(db, uid);

  let deletedDocs = 0;
  for (const items of [
    db.collection(P.users).doc(uid).collection(P.addresses),
    db.collection(P.users).doc(uid).collection(P.savedCards),
    db.collection(P.carts).doc(uid).collection(P.items),
    db.collection(P.wishlists).doc(uid).collection(P.items),
  ]) {
    deletedDocs += await deleteAll(db, items);
  }
  // The cart / wishlist parent docs, if the app ever wrote one.
  const parents = db.batch();
  parents.delete(db.collection(P.carts).doc(uid));
  parents.delete(db.collection(P.wishlists).doc(uid));
  await parents.commit();

  const deletedFiles = await deleteUserFiles(deps.bucket, uid);

  let deletedAuthUser = true;
  try {
    await auth.deleteUser(uid);
  } catch (e) {
    if (errorCode(e) !== 'auth/user-not-found') throw e;
    deletedAuthUser = false;
  }

  return { anonymized, deletedDocs, deletedFiles, deletedAuthUser };
}

/** Never creates the doc: a new `users` doc would fire `onUserCreate`. */
async function anonymizeUser(db: Firestore, uid: string): Promise<boolean> {
  const ref = db.collection(P.users).doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    tx.update(ref, {
      ...ANONYMIZED,
      ...(snap.get('deletedAt') == null && { deletedAt: FieldValue.serverTimestamp() }),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/** Deletes every document of `collection` in batches; returns how many. */
async function deleteAll(db: Firestore, collection: CollectionReference): Promise<number> {
  let deleted = 0;
  for (;;) {
    const page = await collection.select().limit(BATCH_SIZE).get();
    if (page.empty) return deleted;
    const batch = db.batch();
    for (const doc of page.docs) batch.delete(doc.ref);
    await batch.commit();
    deleted += page.size;
  }
}

/**
 * Deletes `users/{uid}/…` from the default bucket. A project without a bucket
 * (goldengift-iq has none yet) or files that are already gone are not errors.
 */
async function deleteUserFiles(bucket: () => Bucket, uid: string): Promise<number | null> {
  try {
    const b = bucket();
    const [files] = await b.getFiles({ prefix: `users/${uid}/` });
    await Promise.all(files.map((f) => f.delete({ ignoreNotFound: true })));
    return files.length;
  } catch (e) {
    if (isMissingStorage(e)) return null;
    throw e;
  }
}

function isMissingStorage(e: unknown): boolean {
  const code = errorCode(e);
  if (code === 404 || code === '404' || code === 'storage/invalid-argument') return true;
  const message = e instanceof Error ? e.message : String(e);
  return /bucket (name not specified|does not exist|not found)|no such (bucket|object)|not found/i.test(message);
}

function errorCode(e: unknown): unknown {
  return typeof e === 'object' && e !== null && 'code' in e ? (e as { code: unknown }).code : undefined;
}
