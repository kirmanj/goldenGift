/**
 * Getting the code to the person.
 *
 * Three drivers behind one function:
 *  - `log` writes the code to the function log and sends nothing — the emulator and
 *    the automated tests use it (a test that sends real WhatsApp messages is a test
 *    nobody runs twice, and every message costs money). The code itself is only
 *    printed when the process really runs on the Functions emulator;
 *  - `otpiq` is the Iraqi gateway: `provider: 'whatsapp-sms'` tries WhatsApp first
 *    and falls back to SMS by itself — WhatsApp is what people read, SMS is what
 *    always arrives;
 *  - `none` — a deployed function without the OTPIQ key: nothing is minted, sent or
 *    logged (`sendOtp` answers `unavailable`). A plain code in the production logs
 *    would let anyone with log access sign in as anyone.
 */
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { OTP_DEBUG_COLLECTION_EMULATOR_ONLY } from '../shared/paths';
import type { OtpPurpose } from './otp';
import { maskPhone, phoneKey } from './phone';

export const OTPIQ_ENDPOINT = 'https://api.otpiq.com/api/sms';
const TIMEOUT_MS = 10_000;

export type MessagingDriver = 'log' | 'otpiq' | 'none';

export class MessagingError extends Error {}

/** The environment variables the driver choice depends on (injectable for tests). */
export interface MessagingEnv {
  /** Set to 'true' by the Functions emulator. */
  FUNCTIONS_EMULATOR?: string;
  /** Deliberate opt-in for a manual real-delivery test on the emulator. */
  OTP_REAL_SMS?: string;
}

export interface DriverChoice {
  driver: MessagingDriver;
  /** Also mirror the code to `otp_debug/{phoneDigits}` (emulator + `log` only). */
  mirrorToDebug: boolean;
}

/**
 * Which driver delivers, given the OTPIQ key (if bound) and the environment.
 *
 *  - Functions emulator: ALWAYS `log` — even though the emulator loads the live key
 *    from `functions/.secret.local` — unless `OTP_REAL_SMS=true` (and a key exists).
 *    With `log`, the code is also mirrored to `otp_debug` for end-to-end tests.
 *  - Deployed: `otpiq` when the key is present; otherwise `none` — codes are
 *    refused (`unavailable`), with an error logged so the missing secret is obvious,
 *    and never written to the log.
 */
export function selectDriver(apiKey: string | undefined, env: MessagingEnv = process.env): DriverChoice {
  const hasKey = typeof apiKey === 'string' && apiKey.trim().length > 0;
  if (env.FUNCTIONS_EMULATOR === 'true') {
    if (env.OTP_REAL_SMS === 'true') {
      if (hasKey) return { driver: 'otpiq', mirrorToDebug: false };
      logger.error('otp: OTP_REAL_SMS=true but OTPIQ_API_KEY is not set — using the log driver');
    }
    return { driver: 'log', mirrorToDebug: true };
  }
  if (hasKey) return { driver: 'otpiq', mirrorToDebug: false };
  logger.error('otp: OTPIQ_API_KEY is missing — codes cannot be sent (sendOtp answers unavailable)');
  return { driver: 'none', mirrorToDebug: false };
}

/**
 * Whether the process really runs on the Functions emulator (the real
 * environment, never an injected one): the only place a plain code may be logged.
 */
export function onFunctionsEmulator(): boolean {
  return process.env.FUNCTIONS_EMULATOR === 'true';
}

/**
 * Sends a verification code with the given driver.
 *
 * The API key is passed in rather than read from the environment, so the callable
 * that binds the secret is the only thing that ever holds it. `fetchImpl` exists so
 * tests can stub the network; production uses the global `fetch`.
 *
 * Throws `MessagingError` when OTPIQ refuses or cannot be reached, for the `none`
 * driver, and for `otpiq` without a key (never a silent fallback that logs the code).
 */
export async function sendVerificationCode(
  driver: MessagingDriver,
  apiKey: string | undefined,
  phone: string,
  code: string,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  if (driver === 'log') {
    // The whole code only on the Functions emulator — the one place it is ever
    // logged. Anywhere else (the automated tests, a misconfigured process) the line
    // says that a code was "sent", without it.
    if (onFunctionsEmulator()) logger.info(`otp[log]: code for ${maskPhone(phone)} is ${code}`);
    else logger.info(`otp[log]: code for ${maskPhone(phone)} not delivered (log driver)`);
    return;
  }
  if (driver === 'none' || !apiKey) {
    logger.error('otp: no messaging configured — code not sent', { phone: maskPhone(phone) });
    throw new MessagingError('Messaging is not configured.');
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetchImpl(OTPIQ_ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        phoneNumber: phone,
        smsType: 'verification',
        verificationCode: code,
        provider: 'whatsapp-sms',
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      // Never the code (and never the key); the masked number tells support whose
      // message failed. The body is OTPIQ's error text, truncated.
      logger.error('otpiq: send failed', { phone: maskPhone(phone), status: response.status, body: body.slice(0, 500) });
      throw new MessagingError(`Delivery failed (${response.status}).`);
    }
  } catch (error) {
    if (error instanceof MessagingError) throw error;
    const reason = (error as Error)?.name === 'AbortError' ? 'timed out' : String((error as Error)?.message ?? error);
    logger.error('otpiq: connection failed', { phone: maskPhone(phone), reason });
    throw new MessagingError(`Could not reach the messaging service: ${reason}`);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * EMULATOR ONLY: `otp_debug/{phoneDigits}` = `{ code, purpose, at }`, so end-to-end
 * tests can read the code from the Firestore emulator.
 *
 * Two independent guards: the driver choice must ask for it (emulator + `log`), and
 * the Admin SDK must point at the Firestore emulator — checked on the real
 * `process.env`, not an injected one — so a plain code can never land in a real
 * database, whatever a caller passes in.
 */
export async function mirrorCodeToDebug(
  db: Firestore,
  choice: DriverChoice,
  phone: string,
  code: string,
  purpose: OtpPurpose,
): Promise<boolean> {
  if (!choice.mirrorToDebug || choice.driver !== 'log') return false;
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    logger.warn('otp: not mirroring the code to otp_debug — Firestore is not the emulator');
    return false;
  }
  await db
    .collection(OTP_DEBUG_COLLECTION_EMULATOR_ONLY)
    .doc(phoneKey(phone))
    .set({ code, purpose, at: FieldValue.serverTimestamp() });
  return true;
}
