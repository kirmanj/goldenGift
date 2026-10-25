import { FieldValue, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { FirestorePaths } from './paths';

/**
 * Runs `fn` at most once per `key` (SRS §7: every function is idempotent).
 *
 * In one Firestore transaction: if `function_runs/{key}` exists, nothing happens
 * and `false` is returned; otherwise `fn(tx)` runs and the marker
 * `{ key, at: serverTimestamp }` is created in the same transaction, so the
 * side effects and the marker commit together or not at all. Returns `true`
 * when `fn` ran.
 *
 * Keys name the event, e.g. `orderBonus:{orderId}`, `joinBonus:{referralId}`,
 * `issueGiftCard:{orderId}`. They become document ids, so they must not contain
 * `/` (and cannot be `.`, `..` or `__…__`).
 *
 * Contract for `fn`:
 *  - Do ALL Firestore writes through the given `tx` (never `db.doc().set()` or a
 *    batch) — otherwise they are not covered by the once-only guarantee.
 *  - Do every `tx.get()` before the first write (Firestore transaction rule).
 *  - No external side effects (FCM, email, HTTP): the transaction may be retried,
 *    so `fn` can execute more than once before a single commit. Send those after
 *    `runOnce` resolves `true`.
 */
export async function runOnce(
  db: Firestore,
  key: string,
  fn: (tx: Transaction) => Promise<void> | void,
): Promise<boolean> {
  assertValidKey(key);
  const marker = db.collection(FirestorePaths.functionRuns).doc(key);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(marker);
    if (snap.exists) return false;
    await fn(tx);
    tx.create(marker, { key, at: FieldValue.serverTimestamp() });
    return true;
  });
}

/**
 * `runOnce` for effects that may not be due yet: `fn` returns `true` when it
 * applied the effect (the marker is created with it) and `false` when it decided
 * nothing is due — then NO marker is written, so a later call can still apply it.
 * When `fn` returns `false` it must not have written anything through `tx`.
 *
 * Used where the key names the effect rather than the event, e.g.
 * `orderBonus:{referralId}`: many delivered orders may be checked, only the first
 * that qualifies pays. Same contract as `runOnce` otherwise. Returns whether `fn`
 * applied the effect in this call.
 */
export async function runOnceIf(
  db: Firestore,
  key: string,
  fn: (tx: Transaction) => Promise<boolean>,
): Promise<boolean> {
  assertValidKey(key);
  const marker = db.collection(FirestorePaths.functionRuns).doc(key);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(marker);
    if (snap.exists) return false;
    const applied = await fn(tx);
    if (applied) tx.create(marker, { key, at: FieldValue.serverTimestamp() });
    return applied;
  });
}

function assertValidKey(key: string): void {
  if (
    key.length === 0 ||
    key.includes('/') ||
    key === '.' ||
    key === '..' ||
    /^__.*__$/.test(key) ||
    Buffer.byteLength(key, 'utf8') > 1500
  ) {
    throw new Error(`runOnce: invalid idempotency key "${key}"`);
  }
}
