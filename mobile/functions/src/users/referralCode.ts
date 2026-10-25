import { randomInt } from 'node:crypto';

/**
 * Referral codes (SRS AUTH-3, §5.19): 6 characters from 32 unambiguous symbols —
 * upper-case letters and digits without I, O, 0 and 1 — so a code read aloud or
 * copied from a screenshot is typed correctly. 32^6 ≈ 1.07 billion codes.
 */
export const REFERRAL_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const REFERRAL_CODE_LENGTH = 6;

const CODE_PATTERN = new RegExp(`^[${REFERRAL_CODE_ALPHABET}]{${REFERRAL_CODE_LENGTH}}$`);

/** A new random code, e.g. `K7QX2M` (crypto randomness, uniform over the alphabet). */
export function generateReferralCode(): string {
  let code = '';
  for (let i = 0; i < REFERRAL_CODE_LENGTH; i++) {
    code += REFERRAL_CODE_ALPHABET[randomInt(REFERRAL_CODE_ALPHABET.length)];
  }
  return code;
}

/** True when `value` has the shape of a code this module could have generated. */
export function isReferralCode(value: unknown): value is string {
  return typeof value === 'string' && CODE_PATTERN.test(value);
}

/**
 * `users.referralCodeEntered` → trimmed upper-case string, or null when the user
 * entered nothing. Anything else (wrong length, letters outside the alphabet,
 * not a string) is returned as-is or stringified, and fails `isReferralCode`.
 */
export function normalizeEnteredCode(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const code = (typeof value === 'string' ? value : String(value)).trim().toUpperCase();
  return code.length === 0 ? null : code;
}
