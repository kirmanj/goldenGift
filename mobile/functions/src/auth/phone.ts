/**
 * Phone numbers, normalised to one shape before anything else touches them.
 *
 * A number typed by a customer in Erbil arrives in half a dozen forms —
 * `0750 123 4567`, `+964 750 123 4567`, `00964750-1234567`, and the same again in
 * Arabic-Indic digits because that is what the keyboard offered. All of them are one
 * number, and if they are stored as written the same person gets several accounts
 * and the rate limiter counts each spelling separately, which defeats it.
 *
 * So every entry point runs through `normalizePhone` and works in E.164 only.
 * `libphonenumber-js` does the validation rather than a regex: a regex that accepts
 * every valid number in every country does not exist, and the one we would write
 * would eventually reject somebody's real number.
 */
import { parsePhoneNumberFromString } from 'libphonenumber-js';

/** Where our customers are. Bare local numbers are read as Iraqi. */
export const DEFAULT_REGION = 'IQ' as const;

/**
 * Arabic-Indic (٠١٢٣) and Persian (۰۱۲۳) digits to ASCII.
 *
 * Both keyboards are in daily use in Iraq / Kurdistan and both produce digits that
 * look identical to the reader and are entirely different code points to a comparison.
 */
export function normalizeDigits(input: string): string {
  return input.replace(/[٠-٩۰-۹]/g, (d) => {
    const code = d.charCodeAt(0);
    const base = code >= 0x06f0 ? 0x06f0 : 0x0660;
    return String(code - base);
  });
}

/**
 * → `+9647501234567`, or null if it is not a valid phone number.
 *
 * Returns null rather than throwing so each caller chooses its own refusal.
 */
export function normalizePhone(input: unknown): string | null {
  if (typeof input !== 'string' || !input) return null;

  let text = normalizeDigits(input).trim();
  if (!text) return null;

  // `00` is how much of the world writes `+`, and the parser wants `+`.
  if (text.startsWith('00')) text = `+${text.slice(2)}`;

  const parsed = parsePhoneNumberFromString(text, DEFAULT_REGION);
  if (!parsed || !parsed.isValid()) return null;

  return parsed.number;
}

/** True when the text looks like a phone rather than an email — for a combined field. */
export function looksLikePhone(input: string): boolean {
  const text = normalizeDigits(input).trim();
  if (text.includes('@')) return false;
  return /^[+\d][\d\s()\-.]{5,}$/.test(text);
}

/**
 * A safe document id: the E.164 digits without the `+`.
 *
 * `+` is legal in a Firestore id but reads badly in the console and in a URL.
 */
export const phoneKey = (e164: string): string => e164.replace(/\D/g, '');

/** `+964 750 ••• 4567` — enough to recognise your own number, not enough to leak it. */
export function maskPhone(e164: string): string {
  const parsed = parsePhoneNumberFromString(e164);
  const national = parsed?.nationalNumber ?? e164.replace(/\D/g, '');
  if (national.length < 6) return '•••';
  return `+${parsed?.countryCallingCode ?? ''} ${national.slice(0, 3)} ••• ${national.slice(-4)}`;
}

/**
 * E.164 → the two fields `users/{uid}` stores (SRS §6.1):
 * `+9647501234567` → `{ phone: '7501234567', countryCode: '+964' }`.
 */
export function splitPhone(e164: string): { phone: string; countryCode: string } {
  const parsed = parsePhoneNumberFromString(e164);
  if (!parsed) throw new Error('splitPhone: not an E.164 number');
  return { phone: parsed.nationalNumber, countryCode: `+${parsed.countryCallingCode}` };
}
