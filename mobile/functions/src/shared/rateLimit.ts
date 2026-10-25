/**
 * Rolling-window rate limits for callables (SRS §8 Security): one
 * `function_runs/{key}` document per limited subject = `{ key, hits: [epoch ms…],
 * at }` — functions-only (the rules deny every client), one read + one write, no
 * index, and self-pruning: only the hits inside the window are kept, so the
 * document never grows past `limit` entries.
 *
 * Two ways to use it:
 *  - `consumeRateLimit` counts every call (e.g. partner applications, payment
 *    sessions): the call is refused once `limit` calls happened in the window;
 *  - `assertUnderRateLimit` + `recordRateLimitHit` count only FAILURES (e.g. wrong
 *    invite codes): check before the attempt, record after a failed one.
 * Inside a caller's own transaction use `readRateLimit` / `writeRateLimit`.
 *
 * Keys name the limit and the subject, e.g. `rl:santaJoin:{uid}`; they must be
 * valid document ids (no `/`).
 */
import { FieldValue, type DocumentReference, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { FirestorePaths as P } from './paths';

export interface RateLimit {
  /** Hits allowed per window. */
  limit: number;
  windowMs: number;
}

export function rateLimitRef(db: Firestore, key: string): DocumentReference {
  if (key.length === 0 || key.includes('/') || Buffer.byteLength(key, 'utf8') > 1500) {
    throw new Error(`rateLimit: invalid key "${key}"`);
  }
  return db.collection(P.functionRuns).doc(key);
}

/** The hits still inside the window (pure). */
export function recentHits(raw: unknown, nowMs: number, windowMs: number): number[] {
  return Array.isArray(raw)
    ? raw.filter((v): v is number => typeof v === 'number' && Number.isFinite(v) && v > nowMs - windowMs && v <= nowMs + 60_000)
    : [];
}

/** `resource-exhausted` with `details.reason = 'rate_limited'` and the window in seconds. */
export function rateLimited(message: string, limit: RateLimit): HttpsError {
  return new HttpsError('resource-exhausted', message, {
    reason: 'rate_limited',
    limit: limit.limit,
    windowSeconds: Math.round(limit.windowMs / 1000),
  });
}

/** Reads the window inside `tx` (call before the transaction's first write). */
export async function readRateLimit(
  tx: Transaction,
  ref: DocumentReference,
  limit: RateLimit,
  nowMs: number,
): Promise<{ hits: number[]; full: boolean }> {
  const hits = recentHits((await tx.get(ref)).get('hits'), nowMs, limit.windowMs);
  return { hits, full: hits.length >= limit.limit };
}

/** Stages one more hit (with the pruned window) in `tx`. */
export function writeRateLimit(tx: Transaction, ref: DocumentReference, hits: readonly number[], nowMs: number, limit: RateLimit): void {
  const kept = [...hits, nowMs].slice(-Math.max(1, limit.limit));
  tx.set(ref, { key: ref.id, hits: kept, at: FieldValue.serverTimestamp() });
}

/**
 * Counts one call for `key`; throws `rateLimited(message)` (nothing recorded)
 * when the window is already full.
 */
export async function consumeRateLimit(db: Firestore, key: string, limit: RateLimit, nowMs: number, message: string): Promise<void> {
  const ref = rateLimitRef(db, key);
  const allowed = await db.runTransaction(async (tx) => {
    const { hits, full } = await readRateLimit(tx, ref, limit, nowMs);
    if (full) return false;
    writeRateLimit(tx, ref, hits, nowMs, limit);
    return true;
  });
  if (!allowed) throw rateLimited(message, limit);
}

/** Throws `rateLimited(message)` when `key` already has `limit` recorded hits in the window (reads only). */
export async function assertUnderRateLimit(db: Firestore, key: string, limit: RateLimit, nowMs: number, message: string): Promise<void> {
  const hits = recentHits((await rateLimitRef(db, key).get()).get('hits'), nowMs, limit.windowMs);
  if (hits.length >= limit.limit) throw rateLimited(message, limit);
}

/** Records one hit (e.g. a failed attempt) for `key`. */
export async function recordRateLimitHit(db: Firestore, key: string, limit: RateLimit, nowMs: number): Promise<void> {
  const ref = rateLimitRef(db, key);
  await db.runTransaction(async (tx) => {
    const { hits } = await readRateLimit(tx, ref, limit, nowMs);
    writeRateLimit(tx, ref, hits, nowMs, limit);
  });
}
