/**
 * Time-based gift-card state (SRS §5.22, §7), run every 30 minutes by
 * `sendScheduledGiftCards`:
 *  - a `pending` card whose `scheduledAt` has come is sent (`status` sent,
 *    `sentAt`), linked to the recipient's account if they have one by now, and
 *    the recipient and purchaser are notified;
 *  - a `pending` / `sent` card past `expiresAt` becomes `expired`
 *    (`redeemGiftCard` refuses expired cards by date anyway — this keeps the
 *    status the app and dashboard show right).
 * Each card changes in its own transaction (re-read first), so a redeem or a
 * disable racing the job always wins cleanly. Notification ids are fixed per
 * card, so a re-run never notifies twice.
 */
import { FieldValue, Timestamp, type DocumentData } from 'firebase-admin/firestore';
import type { NotifyDeps } from '../notifications/notifyUser';
import { epochMillis, integer, string, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { notifyIssued } from './issueGiftCard';
import { NO_RECIPIENT_LOOKUP, type RecipientLookup } from './recipients';

/** Cards handled per run and kind (the next run picks up the rest). */
export const SCHEDULED_BATCH = 200;

export async function sendDueGiftCards(
  deps: NotifyDeps & { recipients?: RecipientLookup },
  nowMs: number,
): Promise<{ sent: string[] }> {
  const { db } = deps;
  const recipients = deps.recipients ?? NO_RECIPIENT_LOOKUP;
  const due = await db
    .collection(P.giftCards)
    .where('status', '==', 'pending')
    .where('scheduledAt', '<=', Timestamp.fromMillis(nowMs))
    .orderBy('scheduledAt')
    .limit(SCHEDULED_BATCH)
    .get();

  // The purchasers' names in one batched read (not one read per card).
  const purchaserUids = [
    ...new Set(
      due.docs.map((d) => stringOrNull(d.get('purchaserUid'))).filter((u): u is string => u !== null && !u.includes('/')),
    ),
  ];
  const names = new Map<string, string | null>();
  if (purchaserUids.length > 0) {
    for (const snap of await db.getAll(...purchaserUids.map((u) => db.collection(P.users).doc(u)))) {
      names.set(snap.id, stringOrNull(snap.get('name')));
    }
  }

  const sent: string[] = [];
  for (const doc of due.docs) {
    // Verified-identity match (Firebase Auth) before the transaction: it is not a Firestore read.
    const before = doc.data();
    const matched =
      stringOrNull(before.recipientUid) ??
      (await recipients.byContact(stringOrNull(before.recipientPhone), stringOrNull(before.recipientEmail)));
    const card = await db.runTransaction(async (tx) => {
      const data = (await tx.get(doc.ref)).data();
      if (data === undefined || data.status !== 'pending') return null;
      const scheduledAt = epochMillis(data.scheduledAt);
      if (scheduledAt !== null && scheduledAt > nowMs) return null;
      const expiresAt = epochMillis(data.expiresAt);
      if (expiresAt !== null && expiresAt <= nowMs) return null; // the expiry pass handles it
      const recipientUid = stringOrNull(data.recipientUid) ?? matched;
      const ts = FieldValue.serverTimestamp();
      tx.update(doc.ref, { status: 'sent', sentAt: ts, recipientUid, updatedAt: ts });
      return { ...data, recipientUid } as DocumentData;
    });
    if (card === null) continue;
    sent.push(doc.id);
    const purchaserUid = stringOrNull(card.purchaserUid);
    await notifyIssued(deps, {
      id: doc.id,
      amount: integer(card.amount),
      status: 'sent',
      recipientUid: stringOrNull(card.recipientUid),
      purchaserUid,
      recipientName: string(card.recipientName),
      purchaserName: purchaserUid === null ? null : (names.get(purchaserUid) ?? null),
      scheduledAtMs: null,
    });
  }
  return { sent };
}

export async function expireGiftCards(deps: Pick<NotifyDeps, 'db'>, nowMs: number): Promise<{ expired: string[] }> {
  const { db } = deps;
  const past = await db
    .collection(P.giftCards)
    .where('status', 'in', ['pending', 'sent'])
    .where('expiresAt', '<=', Timestamp.fromMillis(nowMs))
    .orderBy('expiresAt')
    .limit(SCHEDULED_BATCH)
    .get();

  const expired: string[] = [];
  for (const doc of past.docs) {
    const changed = await db.runTransaction(async (tx) => {
      const data = (await tx.get(doc.ref)).data();
      if (data === undefined || !['pending', 'sent'].includes(string(data.status))) return false;
      const expiresAt = epochMillis(data.expiresAt);
      if (expiresAt === null || expiresAt > nowMs) return false;
      const ts = FieldValue.serverTimestamp();
      tx.update(doc.ref, { status: 'expired', expiredAt: ts, updatedAt: ts });
      return true;
    });
    if (changed) expired.push(doc.id);
  }
  return { expired };
}
