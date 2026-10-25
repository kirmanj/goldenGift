import { FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { FirestorePaths as P } from '../shared/paths';
import { PHONE_TAKEN_MESSAGE, assertPhoneFree, authErrorCode } from './authUsers';
import { verifyOtp } from './otp';
import { maskPhone, splitPhone } from './phone';
import { parsePhoneAndCode, type PhoneAuthDeps } from './signIn';

export interface ChangePhoneData {
  phone: string;
  code: string;
}

export interface ChangePhoneResult {
  /** National number as `users/{uid}.phone` stores it, e.g. `7501234567`. */
  phone: string;
  /** e.g. `+964` */
  countryCode: string;
}

/**
 * `changePhone` callable (signed-in user). Data `{ phone, code }`.
 *
 * Verifies and burns a `changePhone` code issued to this uid (a code issued to
 * anyone else is refused exactly like a wrong one), re-checks that no other account
 * took the number meanwhile, moves the Auth user to it, then mirrors it into
 * `users/{uid}` (`phone`, `countryCode`, `updatedAt`) if that doc exists — never
 * creating it, which would fire `onUserCreate`.
 *
 * Errors: `unauthenticated` (signed out; wrong / expired / foreign code),
 * `invalid-argument`, `resource-exhausted` (too many wrong codes),
 * `already-exists` (number belongs to another account).
 */
export async function changePhoneCore(
  deps: PhoneAuthDeps,
  data: unknown,
  uid: string | undefined,
): Promise<ChangePhoneResult> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to change your phone number.');
  const { phone, code } = parsePhoneAndCode(data);

  await verifyOtp(deps.db, phone, code, 'changePhone', uid);

  await assertPhoneFree(deps.auth, phone, uid);
  try {
    await deps.auth.updateUser(uid, { phoneNumber: phone });
  } catch (e) {
    const code = authErrorCode(e);
    if (code === 'auth/phone-number-already-exists') throw new HttpsError('already-exists', PHONE_TAKEN_MESSAGE);
    if (code === 'auth/user-not-found') throw new HttpsError('unauthenticated', 'Sign in again.');
    throw e;
  }

  const split = splitPhone(phone);
  const ref = deps.db.collection(P.users).doc(uid);
  const updatedDoc = await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    tx.update(ref, { ...split, updatedAt: FieldValue.serverTimestamp() });
    return true;
  });

  logger.info('otp: phone changed', { uid, phone: maskPhone(phone), updatedDoc });
  return split;
}
