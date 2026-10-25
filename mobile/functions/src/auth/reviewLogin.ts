/**
 * Store-review demo account (SRS AUTH-2, §7 `sendOtp` / `verifyOtp`).
 *
 * App Store and Play reviewers cannot receive an OTPIQ code, so ONE phone number
 * — `REVIEW_PHONE` (functions/.env, E.164; empty = off) — signs in with ONE fixed
 * code — `REVIEW_OTP_CODE` (Secret Manager; on the emulator functions/.secret.local,
 * which the emulator loads by name). Both must be set; if either is empty or
 * malformed the number goes through the normal OTPIQ flow.
 *
 * Nothing else changes for that number: `sendOtp` applies the usual rate limits and
 * stores the usual hashed 5-minute code — the configured one — but sends nothing
 * (no OTPIQ call, no `otp_debug` mirror); `verifyOtp` accepts only that code
 * (constant-time comparison, on top of the hash), with the usual attempt counter
 * and daily lockout, and logs `review login` with the number masked. Only the
 * `login` purpose is affected.
 */
import { logger } from 'firebase-functions/v2';
import { normalizeCode } from './otp';
import { maskPhone, normalizePhone } from './phone';

export interface ReviewLogin {
  /** E.164. */
  phone: string;
  /** Six ASCII digits. */
  code: string;
}

/**
 * The demo login from the raw param / secret values, or null when it is off.
 * A value that is set but malformed turns it off too (logged), never on.
 */
export function resolveReviewLogin(rawPhone: string | undefined, rawCode: string | undefined): ReviewLogin | null {
  const phoneText = (rawPhone ?? '').trim();
  const codeText = (rawCode ?? '').trim();
  if (phoneText.length === 0 || codeText.length === 0) return null;
  const phone = normalizePhone(phoneText);
  const code = /^\d{6}$/.test(codeText) ? normalizeCode(codeText) : null;
  if (phone === null || code === null) {
    logger.error('otp: review login misconfigured (REVIEW_PHONE must be a phone number, REVIEW_OTP_CODE six digits) — off');
    return null;
  }
  return { phone, code };
}

/** Whether `phone` (E.164) is the demo account's number for this purpose. */
export function isReviewPhone(review: ReviewLogin | null | undefined, phone: string, purpose: string): review is ReviewLogin {
  return review !== null && review !== undefined && purpose === 'login' && review.phone === phone;
}

export function logReviewLogin(phone: string, event: 'code issued' | 'signed in'): void {
  logger.info(`otp: review login — ${event}`, { phone: maskPhone(phone) });
}
