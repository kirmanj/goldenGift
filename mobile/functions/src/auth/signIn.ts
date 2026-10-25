/**
 * Turning a verified phone number into a Firebase session.
 *
 * The exchange is `createCustomToken`, which the app trades for a real Firebase
 * session (`signInWithCustomToken`) — one identity, one set of custom claims, every
 * rule and guard unchanged. Firebase Phone Auth is not used for delivery: it bills
 * per SMS, needs reCAPTCHA on the web and has no WhatsApp path, which in Iraq is the
 * channel people actually read. OTPIQ delivers; Firebase issues the session.
 */
import type { Auth, UserRecord } from 'firebase-admin/auth';
import type { Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { authErrorCode, findUserByPhone } from './authUsers';
import { normalizeCode, verifyOtp } from './otp';
import { maskPhone, normalizePhone } from './phone';
import { isReviewPhone, logReviewLogin, type ReviewLogin } from './reviewLogin';
import { INVALID_PHONE_MESSAGE } from './sendOtp';

export interface PhoneAuthDeps {
  db: Firestore;
  auth: Auth;
  /** Store-review demo account (reviewLogin.ts); null / absent = off. */
  review?: ReviewLogin | null;
}

export interface VerifyOtpData {
  phone: string;
  code: string;
}

export interface VerifyOtpResult {
  /** Custom token for `signInWithCustomToken`. */
  token: string;
  /** true when this call created the Auth user. */
  isNewUser: boolean;
}

export const INVALID_CODE_SHAPE_MESSAGE = 'The code is six digits.';

/** Validates `{ phone, code }` → E.164 phone and six ASCII digits. */
export function parsePhoneAndCode(data: unknown): { phone: string; code: string } {
  const input = (typeof data === 'object' && data !== null ? data : {}) as { phone?: unknown; code?: unknown };
  const phone = normalizePhone(input.phone);
  if (!phone) throw new HttpsError('invalid-argument', INVALID_PHONE_MESSAGE);
  const code = normalizeCode(input.code);
  if (!code) throw new HttpsError('invalid-argument', INVALID_CODE_SHAPE_MESSAGE);
  return { phone, code };
}

/**
 * Finds the Auth user for a number, or creates one. Register and sign in are the
 * same act: proving you hold the number is the whole authentication.
 *
 * No profile here: the app collects it afterwards and creates `users/{uid}` itself,
 * which fires `onUserCreate` (SRS AUTH-3). Creating the Auth user grants nothing.
 */
async function findOrCreate(auth: Auth, phone: string): Promise<{ user: UserRecord; isNew: boolean }> {
  const existing = await findUserByPhone(auth, phone);
  if (existing) return { user: existing, isNew: false };
  try {
    const user = await auth.createUser({ phoneNumber: phone });
    logger.info('otp: account created', { uid: user.uid });
    return { user, isNew: true };
  } catch (e) {
    // Two sign-ins for one new number raced: the other one created it.
    if (authErrorCode(e) === 'auth/phone-number-already-exists') {
      const raced = await findUserByPhone(auth, phone);
      if (raced) return { user: raced, isNew: false };
    }
    throw e;
  }
}

/**
 * `verifyOtp` callable (public). Data `{ phone, code }` → `{ token, isNewUser }`.
 *
 * Verifies and burns a `login` code, then finds or creates the Auth user.
 * Errors: `invalid-argument` (malformed phone / code), `unauthenticated` (wrong,
 * expired or missing code — one message for all), `resource-exhausted` (too many
 * wrong codes), `permission-denied` (disabled account).
 * Does NOT write `users/{uid}`.
 */
export async function verifyOtpAndSignInCore(deps: PhoneAuthDeps, data: unknown): Promise<VerifyOtpResult> {
  const { phone, code } = parsePhoneAndCode(data);

  const review = isReviewPhone(deps.review, phone, 'login') ? deps.review : null;
  await verifyOtp(deps.db, phone, code, 'login', undefined, review?.code);
  if (review !== null) logReviewLogin(phone, 'signed in');

  const { user, isNew } = await findOrCreate(deps.auth, phone);

  // A disabled account is a platform-level ban (admin dashboard / Auth console).
  if (user.disabled) {
    throw new HttpsError('permission-denied', 'This account has been disabled.');
  }

  /*
   * No developer claims in the custom token — deliberately.
   *
   * Developer claims passed to createCustomToken are attached to the SESSION, and
   * Firebase re-applies them to every ID token it mints for that session, where they
   * shadow the account's real custom claims of the same key for as long as the
   * person stays signed in. Copying e.g. `admin` here would freeze a snapshot: an
   * account granted (or stripped of) a claim one second after signing in would keep
   * the old value until it signed out, however often the token was refreshed.
   *
   * The account record is the single source of truth for what somebody may do; its
   * custom claims already propagate into every refreshed ID token on their own, and
   * every rule is written against them. Copying part of it into the session could
   * only ever make the two disagree.
   */
  const token = await deps.auth.createCustomToken(user.uid);

  logger.info('otp: signed in', { uid: user.uid, isNewUser: isNew, phone: maskPhone(phone) });
  return { token, isNewUser: isNew };
}
