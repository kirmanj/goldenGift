/**
 * One-time phone codes: generate, verify, burn.
 *
 * The policy — six digits, hashed at rest, five-minute expiry, five attempts, four
 * codes per phone per thirty minutes — is carried over intact from the proven
 * implementation it was ported from, because every one of those numbers answers a
 * real attack.
 *
 * The active code lives at a **deterministic document id** — one per phone per
 * purpose, `otp_codes/{purpose}:{phoneDigits}` — which makes "a single active code"
 * a property of the storage rather than a query that has to be kept true, turns
 * verification into one transactional read, and needs no index. (A row per code
 * found by query would also race: two concurrent verifies could each read the code
 * before either wrote an attempt.)
 *
 * Three send limits, each stopping something different:
 *
 *   **Per phone** (4 / 30 min) stops number-bombing one person.
 *   **Per IP** (10 / 15 min) stops a script walking a range of numbers.
 *   **Global** (500 / day) stops an attacker who rotates both. Every message costs
 *   money, so it is a spending limit as much as a security control, and it is logged
 *   loudly when it bites because hitting it is either an attack or a launch.
 *
 * The code itself is only ever held in memory and handed to the messaging driver —
 * never stored, never returned, never logged (the `log` driver aside).
 */
import { createHash, randomBytes, randomInt, scryptSync, timingSafeEqual } from 'node:crypto';
import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { FirestorePaths as P } from '../shared/paths';
import { maskPhone, normalizeDigits, phoneKey } from './phone';

/** `login` signs in (`verifyOtp`); `changePhone` moves a signed-in account to a new number. */
export const OTP_PURPOSES = ['login', 'changePhone'] as const;
export type OtpPurpose = (typeof OTP_PURPOSES)[number];

export const CODE_LENGTH = 6;
export const MAX_ATTEMPTS = 5;
export const EXPIRY_SECONDS = 5 * 60;
export const PHONE_LIMIT = { count: 4, windowMs: 30 * 60_000 } as const;
export const IP_LIMIT = { count: 10, windowMs: 15 * 60_000 } as const;
export const GLOBAL_DAILY_LIMIT = 500;
/**
 * Wrong codes per phone (all purposes) in a rolling day. Five attempts per code
 * and four codes per thirty minutes would still allow ~960 guesses a day at one
 * number — about a 1-in-1000 daily chance of breaking a six-digit code by brute
 * force. After this many wrong codes the number cannot be verified until the
 * window rolls (the person can still sign in with Google / Apple).
 */
export const VERIFY_FAILURE_LIMIT = { count: 15, windowMs: 24 * 60 * 60_000 } as const;

/** The single refusal for a wrong, expired, missing or foreign code — see `verifyOtp`. */
export const INVALID_CODE_MESSAGE = 'That code is wrong or has expired.';

export const isOtpPurpose = (v: unknown): v is OtpPurpose =>
  typeof v === 'string' && (OTP_PURPOSES as readonly string[]).includes(v);

/** `otp_codes/{purpose}:{phoneDigits}` */
export const otpCodeId = (purpose: OtpPurpose, phone: string): string => `${purpose}:${phoneKey(phone)}`;

const codeDoc = (db: Firestore, purpose: OtpPurpose, phone: string) =>
  db.collection(P.otpCodes).doc(otpCodeId(purpose, phone));

/** Hashed, not stored raw: a rate limiter needs to tell devices apart, not identify them. */
export const hashIp = (ip: string | undefined | null): string | null =>
  ip ? createHash('sha256').update(ip).digest('hex').slice(0, 32) : null;

// ─────────────────────────────────────────────────────────────────────────────
// Hashing
// ─────────────────────────────────────────────────────────────────────────────

/**
 * scrypt from the standard library, salted per code.
 *
 * A six-digit code has a million possibilities, which a fast hash would let anyone
 * with a copy of the database exhaust in about a second. scrypt's work factor is the
 * whole defence; it costs ~50 ms per verification, which is the right side of the
 * trade for something a person types once.
 */
function hashCode(code: string): string {
  const salt = randomBytes(16);
  return `${salt.toString('hex')}:${scryptSync(code, salt, 32).toString('hex')}`;
}

/** Constant-time equality of two codes (the store-review demo code). */
function sameDigits(a: string, b: string): boolean {
  const x = Buffer.from(a, 'utf8');
  const y = Buffer.from(b, 'utf8');
  return x.length === y.length && timingSafeEqual(x, y);
}

/** Constant-time. A comparison that returns early leaks the code one byte at a time. */
function checkCode(code: string, stored: unknown): boolean {
  if (typeof stored !== 'string') return false;
  const [saltHex, hashHex] = stored.split(':');
  if (!saltHex || !hashHex) return false;
  try {
    const expected = Buffer.from(hashHex, 'hex');
    const actual = scryptSync(code, Buffer.from(saltHex, 'hex'), expected.length);
    return timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Throttling
// ─────────────────────────────────────────────────────────────────────────────

/**
 * A rolling window held as a list of timestamps on one `otp_throttle` document.
 * One read and one write, no index, and self-pruning, so the document cannot grow
 * without bound however hard it is hit. Returns false when the window is full.
 */
async function hitWindow(db: Firestore, docId: string, limit: number, windowMs: number): Promise<boolean> {
  const ref = db.collection(P.otpThrottle).doc(docId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const hits = snap.get('hits');
    const recent = (Array.isArray(hits) ? (hits as unknown[]) : []).filter(
      (t): t is number => typeof t === 'number' && t > now - windowMs,
    );
    if (recent.length >= limit) return false;
    recent.push(now);
    tx.set(ref, { hits: recent, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
}

/** A fixed daily ceiling on what the whole platform may spend on messages. */
async function underGlobalCeiling(db: Firestore, day: string): Promise<boolean> {
  const ref = db.collection(P.otpThrottle).doc(`global:${day}`);
  return db.runTransaction(async (tx) => {
    const sent = (await tx.get(ref)).get('sent');
    const count = typeof sent === 'number' ? sent : 0;
    if (count >= GLOBAL_DAILY_LIMIT) return false;
    tx.set(ref, { sent: count + 1, day, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Generate
// ─────────────────────────────────────────────────────────────────────────────

export interface GenerateOptions {
  /** `hashIp(request.rawRequest.ip)`; null / absent skips the per-IP limit. */
  ipHash?: string | null;
  /** `changePhone`: the uid that asked — only that uid can spend the code. */
  uid?: string;
  /**
   * Runs after the per-phone and per-IP limits and before the global ceiling is
   * charged and the code minted. A refusal thrown here sends nothing and spends
   * nothing — but has still been rate-limited, so it cannot be used as a free
   * oracle (e.g. "does another account own this number?").
   */
  beforeIssue?: () => Promise<void>;
  /**
   * Store-review demo account only (reviewLogin.ts): the code to store instead of a
   * random one. Nothing is sent for it, so it does not charge the global ceiling.
   */
  fixedCode?: string;
}

export interface GenerateResult {
  /** In memory only. Handed to the messaging driver and never written down. */
  code: string;
  expiresInSeconds: number;
}

/**
 * Mints a code, replacing whatever was outstanding for this phone and purpose.
 *
 * The replacement is the point: asking for a second code must invalidate the first,
 * or someone who intercepts one message has an unbounded window to use it while the
 * victim carries on with a newer code and notices nothing.
 *
 * Errors: `resource-exhausted` for any of the three limits.
 */
export async function generateOtp(
  db: Firestore,
  phone: string,
  purpose: OtpPurpose,
  options: GenerateOptions = {},
): Promise<GenerateResult> {
  if (!(await hitWindow(db, `phone:${phoneKey(phone)}`, PHONE_LIMIT.count, PHONE_LIMIT.windowMs))) {
    throw new HttpsError(
      'resource-exhausted',
      'Too many codes have been sent to this number. Wait half an hour and try again.',
    );
  }
  if (options.ipHash && !(await hitWindow(db, `ip:${options.ipHash}`, IP_LIMIT.count, IP_LIMIT.windowMs))) {
    throw new HttpsError('resource-exhausted', 'Too many requests from this device. Try again shortly.');
  }

  await options.beforeIssue?.();

  const day = new Date().toISOString().slice(0, 10);
  if (options.fixedCode === undefined && !(await underGlobalCeiling(db, day))) {
    logger.error('otp: global daily ceiling reached', { day, limit: GLOBAL_DAILY_LIMIT, phone: maskPhone(phone) });
    throw new HttpsError('resource-exhausted', 'Codes are temporarily unavailable. Please try again later.');
  }

  // randomInt, not Math.random: Math.random is predictable from prior output, which
  // for a login code means guessable.
  const code = options.fixedCode ?? String(randomInt(100_000, 1_000_000));

  await codeDoc(db, purpose, phone).set({
    phone,
    purpose,
    hash: hashCode(code),
    attempts: 0,
    ...(options.uid !== undefined && { uid: options.uid }),
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + EXPIRY_SECONDS * 1000),
  });

  return { code, expiresInSeconds: EXPIRY_SECONDS };
}

// ─────────────────────────────────────────────────────────────────────────────
// Verify
// ─────────────────────────────────────────────────────────────────────────────

/** `'123 456'`, `'١٢٣٤٥٦'` → `'123456'`; null unless exactly six digits remain. */
export function normalizeCode(input: unknown): string | null {
  if (typeof input !== 'string') return null;
  // Same digit folding as phone numbers: the code is typed on the same keyboards.
  const code = normalizeDigits(input).replace(/\D/g, '');
  return code.length === CODE_LENGTH ? code : null;
}

/**
 * Checks a code and burns it (deletes the code doc) when it is right.
 *
 * A wrong code, an expired code, a code that was never issued and (for
 * `changePhone`) a code issued to another uid all produce the *same* refusal —
 * `unauthenticated`, `INVALID_CODE_MESSAGE` — so nobody can enumerate which numbers
 * have a code in flight. Only the attempt ceiling is reported differently
 * (`resource-exhausted`), because the person hitting it must ask for a new code.
 *
 * The whole check runs in one transaction; without it, five parallel guesses would
 * all read `attempts: 0` and the ceiling would never fall.
 *
 * `expectedUid`: required owner of a `changePhone` code. A foreign uid is refused
 * WITHOUT counting an attempt — it could not use the code even if it guessed right,
 * and counting would let any signed-in user burn someone else's pending change.
 *
 * `expectedCode` (store-review demo account, reviewLogin.ts): the only code that
 * may pass, compared in constant time on top of the stored hash; anything else
 * counts as a wrong attempt like any wrong code.
 */
export async function verifyOtp(
  db: Firestore,
  phone: string,
  code: string,
  purpose: OtpPurpose,
  expectedUid?: string,
  expectedCode?: string,
): Promise<void> {
  const ref = codeDoc(db, purpose, phone);
  const failRef = db.collection(P.otpThrottle).doc(`verifyFail:${phoneKey(phone)}`);

  const outcome = await db.runTransaction(async (tx) => {
    const [snap, failSnap] = await tx.getAll(ref, failRef);
    const data = snap.data();
    const now = Date.now();
    const rawFails = failSnap.get('hits');
    const fails = (Array.isArray(rawFails) ? (rawFails as unknown[]) : []).filter(
      (t): t is number => typeof t === 'number' && t > now - VERIFY_FAILURE_LIMIT.windowMs,
    );

    if (!data) return 'invalid' as const;
    if (expectedUid !== undefined && data.uid !== expectedUid) return 'invalid' as const;
    const expiresAt = data.expiresAt as Timestamp | undefined;
    if (typeof expiresAt?.toMillis !== 'function' || expiresAt.toMillis() < now) return 'invalid' as const;
    const attempts = typeof data.attempts === 'number' ? data.attempts : 0;
    if (attempts >= MAX_ATTEMPTS) return 'exhausted' as const;
    // The daily ceiling of wrong codes for this number (checked before the code, so
    // a locked number cannot be probed for the right one either).
    if (fails.length >= VERIFY_FAILURE_LIMIT.count) return 'locked' as const;

    if (!checkCode(code, data.hash) || (expectedCode !== undefined && !sameDigits(code, expectedCode))) {
      // Read-then-write inside the transaction: concurrent guesses serialise here.
      tx.update(ref, { attempts: attempts + 1 });
      tx.set(failRef, { hits: [...fails, now].slice(-VERIFY_FAILURE_LIMIT.count), updatedAt: FieldValue.serverTimestamp() });
      return 'invalid' as const;
    }

    // Deleted rather than marked used: the throttle docs are what the rate limits
    // count, and a spent code that still exists is only a chance to get a check wrong.
    tx.delete(ref);
    return 'ok' as const;
  });

  if (outcome === 'exhausted') {
    throw new HttpsError('resource-exhausted', 'Too many wrong codes. Ask for a new one.');
  }
  if (outcome === 'locked') {
    logger.warn('otp: daily wrong-code ceiling reached', { phone: maskPhone(phone), purpose });
    throw new HttpsError('resource-exhausted', 'Too many wrong codes for this number. Please try again tomorrow.');
  }
  if (outcome === 'invalid') {
    throw new HttpsError('unauthenticated', INVALID_CODE_MESSAGE);
  }
}
