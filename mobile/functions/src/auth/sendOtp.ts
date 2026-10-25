import type { Auth } from 'firebase-admin/auth';
import type { Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { assertPhoneFree } from './authUsers';
import {
  MessagingError,
  mirrorCodeToDebug,
  selectDriver,
  sendVerificationCode,
  type MessagingEnv,
} from './messaging';
import { generateOtp, hashIp, isOtpPurpose, type OtpPurpose } from './otp';
import { maskPhone, normalizePhone } from './phone';
import { isReviewPhone, logReviewLogin, type ReviewLogin } from './reviewLogin';

export interface SendOtpDeps {
  db: Firestore;
  auth: Auth;
  /** `OTPIQ_API_KEY.value()`; empty / absent → the `log` driver. */
  apiKey: string | undefined;
  /** Defaults to `process.env` (see `selectDriver`). */
  env?: MessagingEnv;
  /** Defaults to the global `fetch`; tests stub it. */
  fetch?: typeof fetch;
  /** Store-review demo account (reviewLogin.ts); null / absent = off. */
  review?: ReviewLogin | null;
}

export interface SendOtpCaller {
  /** `request.auth?.uid` */
  uid?: string;
  /** `request.rawRequest.ip` — hashed before it is stored. */
  ip?: string;
}

export interface SendOtpData {
  phone: string;
  purpose?: OtpPurpose;
}

export interface SendOtpResult {
  expiresInSeconds: number;
  /** Masked, e.g. `+964 750 ••• 4567`. */
  phone: string;
}

export const INVALID_PHONE_MESSAGE = 'Enter a valid phone number, for example 0750 123 4567.';

/**
 * `sendOtp` callable (public). Data `{ phone, purpose? = 'login' }`.
 *
 * Normalises the number, applies the rate limits, mints a code (replacing any
 * outstanding one for this phone + purpose) and delivers it. For `changePhone` the
 * caller must be signed in, the code is bound to their uid, and a number owned by
 * another account is refused before anything is sent.
 *
 * Errors: `invalid-argument` (bad phone / purpose), `unauthenticated` (changePhone
 * signed out), `already-exists` (changePhone to another account's number),
 * `resource-exhausted` (rate limits), `unavailable` (delivery failed / no messaging key).
 * The code is never returned. The store-review demo number (`deps.review`) gets
 * the configured code without any message (reviewLogin.ts).
 */
export async function sendOtpCore(deps: SendOtpDeps, data: unknown, caller: SendOtpCaller): Promise<SendOtpResult> {
  const input = (typeof data === 'object' && data !== null ? data : {}) as { phone?: unknown; purpose?: unknown };

  const purpose = input.purpose ?? 'login';
  if (!isOtpPurpose(purpose)) throw new HttpsError('invalid-argument', 'Unknown purpose.');
  const uid = caller.uid;
  if (purpose === 'changePhone' && !uid) {
    throw new HttpsError('unauthenticated', 'Sign in to change your phone number.');
  }

  const phone = normalizePhone(input.phone);
  if (!phone) throw new HttpsError('invalid-argument', INVALID_PHONE_MESSAGE);

  // Store-review demo account: the usual limits and a stored (hashed) code — the
  // configured one — but nothing is sent and nothing mirrored.
  if (isReviewPhone(deps.review, phone, purpose)) {
    const { expiresInSeconds } = await generateOtp(deps.db, phone, purpose, {
      ipHash: hashIp(caller.ip),
      fixedCode: deps.review.code,
    });
    logReviewLogin(phone, 'code issued');
    return { expiresInSeconds, phone: maskPhone(phone) };
  }

  const choice = selectDriver(deps.apiKey, deps.env);
  // A deploy without the OTPIQ key mints nothing (no code that nobody receives,
  // no limit charged) and never logs one.
  if (choice.driver === 'none') {
    throw new HttpsError('unavailable', 'Sign-in codes are temporarily unavailable. Please try again later.');
  }

  const { code, expiresInSeconds } = await generateOtp(deps.db, phone, purpose, {
    ipHash: hashIp(caller.ip),
    ...(purpose === 'changePhone' && {
      uid,
      // After the rate limits (so it is no free "who owns this number" oracle),
      // before the global ceiling is charged and anything is sent.
      beforeIssue: () => assertPhoneFree(deps.auth, phone, uid!),
    }),
  });

  try {
    // The key only reaches the driver that needs it.
    await sendVerificationCode(
      choice.driver,
      choice.driver === 'otpiq' ? deps.apiKey : undefined,
      phone,
      code,
      deps.fetch,
    );
  } catch (error) {
    if (error instanceof MessagingError) {
      // The usual cause is a number that WhatsApp and SMS both refuse — the person
      // needs to check the number, not retry the same one.
      throw new HttpsError('unavailable', 'We could not send the code to that number. Check it and try again.');
    }
    throw error;
  }
  await mirrorCodeToDebug(deps.db, choice, phone, code, purpose);

  logger.info('otp: sent', { phone: maskPhone(phone), purpose, driver: choice.driver });
  // Never the code itself: a "debug mode" that returns it is a flag somebody
  // eventually ships enabled.
  return { expiresInSeconds, phone: maskPhone(phone) };
}
