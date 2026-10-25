import type { Auth, UserRecord } from 'firebase-admin/auth';
import { HttpsError } from 'firebase-functions/v2/https';

/** `auth/user-not-found` etc. from a firebase-admin Auth error, if any. */
export function authErrorCode(e: unknown): string | undefined {
  const code = typeof e === 'object' && e !== null && 'code' in e ? (e as { code: unknown }).code : undefined;
  return typeof code === 'string' ? code : undefined;
}

/** The Auth user holding this E.164 number, or null. */
export async function findUserByPhone(auth: Auth, phone: string): Promise<UserRecord | null> {
  try {
    return await auth.getUserByPhoneNumber(phone);
  } catch (e) {
    if (authErrorCode(e) === 'auth/user-not-found') return null;
    throw e;
  }
}

export const PHONE_TAKEN_MESSAGE = 'This number is already used by another account.';

/** `already-exists` when an Auth user other than `uid` holds `phone`. */
export async function assertPhoneFree(auth: Auth, phone: string, uid: string): Promise<void> {
  const owner = await findUserByPhone(auth, phone);
  if (owner && owner.uid !== uid) throw new HttpsError('already-exists', PHONE_TAKEN_MESSAGE);
}
