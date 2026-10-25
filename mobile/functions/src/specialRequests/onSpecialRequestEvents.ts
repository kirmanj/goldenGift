/**
 * Special-request notifications to the customer (SRS §4.5, §5.17):
 *  - `onSpecialRequestMessage` — a new `special_requests/{id}/messages/{msg}` by an
 *    admin (role `admin`) → "New reply to your request" with the message. System
 *    messages (`system: true`, e.g. acceptQuote's "Quote accepted") and the
 *    "Quote: …" message the dashboard posts in the same batch as the quote
 *    (`quotedAt` == the message's `at`) are skipped — the quote has its own.
 *  - `onSpecialRequestUpdate` — the request's `status` became `quoted` →
 *    "Your quote is ready" with the amount.
 * Notification ids are derived from the message id / event id, so a retried
 * trigger never notifies twice.
 */
import { createHash } from 'node:crypto';
import type { DocumentData } from 'firebase-admin/firestore';
import { notifyUser, type NotifyDeps } from '../notifications/notifyUser';
import { epochMillis, integer, string, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { specialRequestQuotedNotification, specialRequestReplyNotification } from './specialRequestMessages';

export type SpecialRequestNotifyResult =
  | { notified: true; notificationId: string }
  | { notified: false; reason: 'notAdmin' | 'system' | 'quoteMessage' | 'missing' | 'unchanged' | 'duplicate' };

function eventHash(eventId: string): string {
  return createHash('sha256').update(eventId, 'utf8').digest('hex').slice(0, 16);
}

export async function handleSpecialRequestMessage(
  deps: NotifyDeps,
  event: { requestId: string; messageId: string; message: DocumentData | undefined },
): Promise<SpecialRequestNotifyResult> {
  const { message, requestId } = event;
  if (message === undefined) return { notified: false, reason: 'missing' };
  if (message.role !== 'admin') return { notified: false, reason: 'notAdmin' };
  if (message.system === true) return { notified: false, reason: 'system' };

  const request = (await deps.db.collection(P.specialRequests).doc(requestId).get()).data();
  const userId = stringOrNull(request?.userId);
  if (request === undefined || userId === null) return { notified: false, reason: 'missing' };
  const at = epochMillis(message.at);
  if (request.status === 'quoted' && at !== null && epochMillis(request.quotedAt) === at) {
    return { notified: false, reason: 'quoteMessage' };
  }

  const notificationId = `sr-${requestId}-msg-${event.messageId}`.slice(0, 1400);
  const result = await notifyUser(deps, userId, specialRequestReplyNotification(requestId, string(message.text)), {
    notificationId,
  });
  return result.created ? { notified: true, notificationId } : { notified: false, reason: 'duplicate' };
}

export async function handleSpecialRequestUpdate(
  deps: NotifyDeps,
  event: { eventId: string; requestId: string; before: DocumentData | undefined; after: DocumentData | undefined },
): Promise<SpecialRequestNotifyResult> {
  const { before, after, requestId } = event;
  if (before === undefined || after === undefined) return { notified: false, reason: 'missing' };
  if (after.status !== 'quoted' || before.status === 'quoted') return { notified: false, reason: 'unchanged' };
  const userId = stringOrNull(after.userId);
  if (userId === null) return { notified: false, reason: 'missing' };

  const notificationId = `sr-${requestId}-quoted-${eventHash(event.eventId)}`;
  const result = await notifyUser(deps, userId, specialRequestQuotedNotification(requestId, integer(after.quoteAmount)), {
    notificationId,
  });
  return result.created ? { notified: true, notificationId } : { notified: false, reason: 'duplicate' };
}
