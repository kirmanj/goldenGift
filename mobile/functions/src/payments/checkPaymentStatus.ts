/**
 * `checkPaymentStatus` (SRS §7): the app's "I've paid — check status" button.
 * A customer who paid but closed the browser before ZainCash redirected them to
 * `zainCashReturn` would otherwise wait for `expirePaymentSessions` (up to ~45 min).
 *
 * Data `{ sessionId }` → `{ status: 'pending' | 'paid' | 'failed' | 'expired' }` —
 * the session's status after the check. Only the session's owner; at most
 * CHECK_RATE_LIMIT checks per session (rolling 5 minutes). A session that is no
 * longer `pending` is answered from Firestore without asking the gateway. Otherwise
 * ZainCash is asked for that one transaction (server to server, the client
 * `expirePaymentSessions` uses) and a final answer is settled through
 * `settlePaymentSession` — the one place that marks payments paid / failed — so
 * the result is idempotent and replays (or a racing redirect) are safe. A
 * `pending` gateway answer changes nothing.
 *
 * Errors: unauthenticated; invalid-argument; not-found ("Payment session not
 * found."); permission-denied (not yours); resource-exhausted (too many checks);
 * unavailable (gateway not configured or not answering — try again).
 */
import type { Firestore } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import type { PushMessaging } from '../notifications/push';
import { string, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { consumeRateLimit, type RateLimit } from '../shared/rateLimit';
import { SessionStatus, settlePaymentSession } from './settlePayment';
import type { PaymentGateway } from './zainCash';

/** Checks per session per rolling 5 minutes. */
export const CHECK_RATE_LIMIT: RateLimit = { limit: 6, windowMs: 5 * 60 * 1000 };
export const SESSION_NOT_FOUND = 'Payment session not found.';

const SESSION_ID = /^[A-Za-z0-9_-]{1,128}$/;

export interface CheckPaymentStatusDeps {
  db: Firestore;
  messaging: PushMessaging | null;
  /** null = not configured → `unavailable`. */
  gateway: PaymentGateway | null;
  now?: () => number;
  logger?: Pick<typeof functionsLogger, 'warn' | 'info' | 'error'>;
}

export function parseCheckPaymentStatusData(data: unknown): { sessionId: string } {
  const id = typeof data === 'object' && data !== null && !Array.isArray(data) ? (data as { sessionId?: unknown }).sessionId : undefined;
  if (typeof id !== 'string' || !SESSION_ID.test(id)) throw new HttpsError('invalid-argument', '`sessionId` is missing or invalid.');
  return { sessionId: id };
}

function sessionStatus(v: unknown): SessionStatus {
  return (SessionStatus as readonly unknown[]).includes(v) ? (v as SessionStatus) : 'pending';
}

export async function checkPaymentStatusCore(
  deps: CheckPaymentStatusDeps,
  data: unknown,
  uid: string | undefined,
): Promise<{ status: SessionStatus }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to check a payment.');
  const { sessionId } = parseCheckPaymentStatusData(data);
  const { db } = deps;
  const log = deps.logger ?? functionsLogger;
  const nowMs = (deps.now ?? Date.now)();
  const ref = db.collection(P.paymentSessions).doc(sessionId);

  const session = (await ref.get()).data();
  if (session === undefined) throw new HttpsError('not-found', SESSION_NOT_FOUND);
  if (session.uid !== uid) throw new HttpsError('permission-denied', 'This is not your payment.');
  // After the ownership check, so nobody can use up someone else's checks.
  await consumeRateLimit(db, `rl:payCheck:${sessionId}`, CHECK_RATE_LIMIT, nowMs, 'Please wait a moment before checking again.');

  const status = sessionStatus(session.status);
  if (status !== 'pending') return { status };
  const txnId = stringOrNull(session.gatewayTxnId);
  // The gateway transaction was never created: nothing can have been paid.
  if (txnId === null) return { status };
  const gateway = deps.gateway;
  if (gateway === null || gateway.id !== string(session.gateway)) {
    throw new HttpsError('unavailable', 'Online payment is not available right now. Please try again.');
  }

  let check;
  try {
    check = await gateway.checkTransaction(txnId, nowMs);
  } catch (e) {
    log.warn('checkPaymentStatus: gateway status check failed', { sessionId, error: e instanceof Error ? e.message : String(e) });
    throw new HttpsError('unavailable', 'We could not reach the payment service. Please try again.');
  }
  if (check.reference !== null && check.reference !== sessionId) {
    log.error('checkPaymentStatus: gateway names another session', { sessionId });
    return { status };
  }
  if (check.outcome === 'pending') return { status: 'pending' };

  const settled = await settlePaymentSession(
    { db, messaging: deps.messaging, logger: log, now: () => nowMs },
    sessionId,
    { outcome: check.outcome, transactionId: txnId, rawStatus: check.rawStatus, message: null },
  );
  if (!settled.found) throw new HttpsError('not-found', SESSION_NOT_FOUND);
  if (settled.changed) log.info('checkPaymentStatus: settled', { sessionId, status: settled.status, effect: settled.effect });
  return { status: settled.status };
}
