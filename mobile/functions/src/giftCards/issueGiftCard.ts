/**
 * Issuing gift cards (SRS §5.22, §6.10, §7 `issueGiftCard`).
 *
 *  - `prepareGiftCard` builds one `gift_cards/{id}` doc inside a transaction: a
 *    unique 12-character code, the template snapshot, `status` sent (or pending
 *    while `scheduledAt` is in the future), `expiresAt` and the recipient's uid
 *    when the phone / email is an app user's VERIFIED one (recipients.ts — never
 *    the profile fields). Shared by the order trigger and `adminIssueGiftCard`.
 *  - `handleGiftCardOrderWrite` is the `onGiftCardOrderPaid` trigger: when a
 *    `giftCard` order is paid (created paid — wallet — or marked paid — cash on
 *    delivery, by onOrderStatusChange on delivery) and has no `giftCardId`, it
 *    issues the card, links it on the order and marks the order delivered (a
 *    wallet order would otherwise stay cancellable — and refundable — after the
 *    card exists); once per order (`function_runs/issueGiftCard:{orderId}`). When
 *    an order whose card was issued is cancelled / returned / refunded later, the
 *    card is disabled unless it was already redeemed.
 *  - `linkGiftCardsToNewUser`: a card sent to a phone / email that had no account
 *    yet shows up in My Gift Cards once that person signs up.
 */
import { createHash } from 'node:crypto';
import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { normalizePhone } from '../auth/phone';
import { notifyUser, type NotifyDeps } from '../notifications/notifyUser';
import { baghdadNow, isoDate } from '../orders/checkoutRules';
import { epochMillis, integer, mapList, string, stringOrNull } from '../shared/firestoreParse';
import { runOnce, runOnceIf } from '../shared/idempotency';
import { FirestorePaths as P } from '../shared/paths';
import {
  giftCardReceivedNotification,
  giftCardScheduledNotification,
  giftCardSentNotification,
} from './giftCardMessages';
import { DAY_MS, GIFT_CARD_VALIDITY_DAYS, generateGiftCardCode, parseTemplate, type GiftCardTemplate } from './giftCardRules';
import { NO_RECIPIENT_LOOKUP, type RecipientLookup } from './recipients';

/** Statuses after which a card bought with the order must no longer be usable. */
export const REVERSED_ORDER_STATUSES: readonly string[] = ['cancelledByBuyer', 'cancelledBySeller', 'returned', 'refunded'];

/** Code collisions are ~1 in 10^18; a few retries are more than enough. */
const CODE_ATTEMPTS = 5;

export interface NewGiftCard {
  templateId: string;
  amount: number;
  /** null for cards an admin issued. */
  purchaserUid: string | null;
  recipientName: string;
  recipientPhone: string | null;
  recipientEmail: string | null;
  message: string;
  photoUrl: string | null;
  /** Epoch ms; null = send now. */
  scheduledAtMs: number | null;
  expiresAtMs: number;
  orderId: string | null;
  /** The admin who issued it by hand (`adminIssueGiftCard`). */
  issuedBy: string | null;
}

export interface PreparedGiftCard {
  ref: DocumentReference;
  code: string;
  status: 'pending' | 'sent';
  recipientUid: string | null;
  /** Writes `gift_cards/{id}` through the transaction. */
  write(): void;
}

export const expiryFrom = (nowMs: number) => nowMs + GIFT_CARD_VALIDITY_DAYS * DAY_MS;

/**
 * Reads (in `tx`) a free code — and the recipient through `recipients` (Firebase
 * Auth: verified phone / email only) — then `write()` creates the card.
 */
export async function prepareGiftCard(
  db: Firestore,
  tx: Transaction,
  card: NewGiftCard,
  template: GiftCardTemplate | null,
  nowMs: number,
  random?: (n: number) => Buffer,
  recipients: RecipientLookup = NO_RECIPIENT_LOOKUP,
): Promise<PreparedGiftCard> {
  const recipientUid = await recipients.byContact(card.recipientPhone, card.recipientEmail);
  const cards = db.collection(P.giftCards);
  let code: string | null = null;
  for (let i = 0; i < CODE_ATTEMPTS && code === null; i++) {
    const candidate = generateGiftCardCode(random);
    if ((await tx.get(cards.where('code', '==', candidate).limit(1))).empty) code = candidate;
  }
  if (code === null) throw new Error('issueGiftCard: could not find a free code');

  const ref = cards.doc();
  const status: 'pending' | 'sent' = card.scheduledAtMs !== null && card.scheduledAtMs > nowMs ? 'pending' : 'sent';
  const ts = FieldValue.serverTimestamp();
  const name = template?.name ?? { en: '', ar: null, ku: null };
  const data: DocumentData = {
    code,
    templateId: card.templateId,
    amount: card.amount,
    balance: card.amount,
    purchaserUid: card.purchaserUid,
    recipientName: card.recipientName,
    recipientPhone: card.recipientPhone,
    recipientEmail: card.recipientEmail,
    recipientUid,
    message: card.message,
    photoUrl: card.photoUrl,
    scheduledAt: card.scheduledAtMs === null ? null : Timestamp.fromMillis(card.scheduledAtMs),
    sentAt: status === 'sent' ? ts : null,
    redeemedAt: null,
    expiresAt: Timestamp.fromMillis(card.expiresAtMs),
    status,
    orderId: card.orderId,
    issuedBy: card.issuedBy,
    templateName: name.en,
    templateNameAr: name.ar,
    templateNameKu: name.ku,
    gradientStart: template?.gradientStart ?? null,
    gradientEnd: template?.gradientEnd ?? null,
    artworkUrl: template?.artworkUrl ?? null,
    createdAt: ts,
    updatedAt: ts,
  };
  return { ref, code, status, recipientUid, write: () => tx.create(ref, data) };
}

/** Sends the "received" / "sent" / "scheduled" notifications of a just-issued card (best effort). */
export async function notifyIssued(
  deps: NotifyDeps,
  card: {
    id: string;
    amount: number;
    status: 'pending' | 'sent';
    recipientUid: string | null;
    purchaserUid: string | null;
    recipientName: string;
    purchaserName: string | null;
    scheduledAtMs: number | null;
  },
): Promise<number> {
  const log = deps.logger ?? functionsLogger;
  let sent = 0;
  const send = async (uid: string, n: Parameters<typeof notifyUser>[2], suffix: string) => {
    try {
      if ((await notifyUser(deps, uid, n, { notificationId: `giftCard-${card.id}-${suffix}` })).created) sent++;
    } catch (e) {
      log.warn('gift card notification failed', { giftCardId: card.id, error: e instanceof Error ? e.message : String(e) });
    }
  };
  if (card.status === 'sent' && card.recipientUid !== null) {
    await send(card.recipientUid, giftCardReceivedNotification(card.id, card.amount, card.purchaserName), 'received');
  }
  if (card.purchaserUid !== null && card.purchaserUid !== card.recipientUid) {
    if (card.status === 'sent') {
      await send(card.purchaserUid, giftCardSentNotification(card.id, card.amount, card.recipientName), 'sent');
    } else if (card.scheduledAtMs !== null) {
      const d = baghdadNow(card.scheduledAtMs);
      const date = isoDate(d.year, d.month, d.day);
      await send(card.purchaserUid, giftCardScheduledNotification(card.id, card.amount, card.recipientName, date), 'scheduled');
    }
  }
  return sent;
}

// ─────────────────────────────────────────────────────────────────────────────
// onGiftCardOrderPaid
// ─────────────────────────────────────────────────────────────────────────────

export interface GiftCardOrderEvent {
  eventId: string;
  orderId: string;
  before: DocumentData | undefined;
  after: DocumentData | undefined;
}

export type GiftCardOrderResult =
  | { action: 'skipped'; reason: 'deleted' | 'notGiftCard' | 'alreadyIssued' | 'notPaid' | 'cancelled' | 'replayed' }
  | { action: 'issued'; giftCardId: string; status: 'pending' | 'sent'; notified: number }
  | { action: 'disabled' | 'notDisabled'; giftCardId: string };

export interface GiftCardDeps extends NotifyDeps {
  /** Epoch ms; tests pin the clock. */
  now?: () => number;
  random?: (n: number) => Buffer;
  /** Verified-identity recipient matching (recipients.ts); absent = nobody is matched. */
  recipients?: RecipientLookup;
}

function eventHash(eventId: string): string {
  return createHash('sha256').update(eventId, 'utf8').digest('hex').slice(0, 16);
}

/** `order.giftCard` (written by purchaseGiftCard). */
function orderGiftCard(order: DocumentData): DocumentData {
  const g: unknown = order.giftCard;
  return g !== null && typeof g === 'object' ? (g as DocumentData) : {};
}

export async function handleGiftCardOrderWrite(deps: GiftCardDeps, event: GiftCardOrderEvent): Promise<GiftCardOrderResult> {
  const { after, before, orderId } = event;
  if (after === undefined) return { action: 'skipped', reason: 'deleted' };
  if (after.orderType !== 'giftCard') return { action: 'skipped', reason: 'notGiftCard' };

  const issuedId = stringOrNull(after.giftCardId);
  if (issuedId !== null) {
    const reversed = REVERSED_ORDER_STATUSES.includes(string(after.status));
    const wasReversed = before !== undefined && REVERSED_ORDER_STATUSES.includes(string(before.status));
    if (!reversed || wasReversed) return { action: 'skipped', reason: 'alreadyIssued' };
    return disableForReversedOrder(deps.db, orderId, issuedId, after, event.eventId);
  }
  if (after.paymentStatus !== 'paid') return { action: 'skipped', reason: 'notPaid' };
  if (REVERSED_ORDER_STATUSES.includes(string(after.status))) return { action: 'skipped', reason: 'cancelled' };

  const { db } = deps;
  const nowMs = (deps.now ?? Date.now)();
  const orderRef = db.collection(P.orders).doc(orderId);
  let issued: (PreparedGiftCard & { card: NewGiftCard; purchaserName: string | null }) | null = null;

  const applied = await runOnceIf(db, `issueGiftCard:${orderId}`, async (tx) => {
    issued = null;
    // ── Reads ──
    const order = (await tx.get(orderRef)).data();
    if (
      order === undefined ||
      order.orderType !== 'giftCard' ||
      stringOrNull(order.giftCardId) !== null ||
      order.paymentStatus !== 'paid' ||
      REVERSED_ORDER_STATUSES.includes(string(order.status))
    ) {
      return false;
    }
    const g = orderGiftCard(order);
    const templateId = string(g.templateId);
    const templateSnap = templateId.length > 0 && !templateId.includes('/') ? await tx.get(db.collection(P.giftCardTemplates).doc(templateId)) : null;
    const template = templateSnap?.exists ? parseTemplate(templateSnap.id, templateSnap.data()!) : null;
    const purchaserUid = stringOrNull(order.userId);
    const purchaser = purchaserUid === null ? undefined : (await tx.get(db.collection(P.users).doc(purchaserUid))).data();
    const card: NewGiftCard = {
      templateId,
      amount: integer(g.amount) || integer(order.subtotal),
      purchaserUid,
      recipientName: string(g.recipientName),
      recipientPhone: stringOrNull(g.recipientPhone),
      recipientEmail: stringOrNull(g.recipientEmail),
      message: string(g.message),
      photoUrl: stringOrNull(g.photoUrl),
      scheduledAtMs: epochMillis(g.scheduledAt),
      expiresAtMs: expiryFrom(nowMs),
      orderId,
      issuedBy: null,
    };
    const prepared = await prepareGiftCard(db, tx, card, template, nowMs, deps.random, deps.recipients);

    // ── Writes ──
    prepared.write();
    const update: Record<string, unknown> = { giftCardId: prepared.ref.id, updatedAt: FieldValue.serverTimestamp() };
    if (order.status !== 'delivered') {
      // Nothing left to deliver: the card exists (sent or scheduled).
      update.status = 'delivered';
      update.items = mapList(order.items).map((i) => ({ ...i, status: 'delivered' }));
      update.statusNote = 'Gift card issued';
      update.statusUpdatedBy = null;
      update.statusUpdatedByRole = 'admin';
    }
    tx.update(orderRef, update);
    issued = { ...prepared, card, purchaserName: stringOrNull(purchaser?.name) };
    return true;
  });

  const done = issued as (PreparedGiftCard & { card: NewGiftCard; purchaserName: string | null }) | null;
  if (!applied || done === null) return { action: 'skipped', reason: 'replayed' };
  const notified = await notifyIssued(deps, {
    id: done.ref.id,
    amount: done.card.amount,
    status: done.status,
    recipientUid: done.recipientUid,
    purchaserUid: done.card.purchaserUid,
    recipientName: done.card.recipientName,
    purchaserName: done.purchaserName,
    scheduledAtMs: done.card.scheduledAtMs,
  });
  return { action: 'issued', giftCardId: done.ref.id, status: done.status, notified };
}

/** The order of an issued card was cancelled / returned / refunded: the card can no longer be used. */
async function disableForReversedOrder(
  db: Firestore,
  orderId: string,
  giftCardId: string,
  order: DocumentData,
  eventId: string,
): Promise<GiftCardOrderResult> {
  let disabled = false;
  await runOnce(db, `giftCardReversed:${orderId}:${eventHash(eventId)}`, async (tx) => {
    const ref = db.collection(P.giftCards).doc(giftCardId);
    const card = (await tx.get(ref)).data();
    disabled = false;
    if (card === undefined || !['pending', 'sent'].includes(string(card.status))) return;
    const ts = FieldValue.serverTimestamp();
    tx.update(ref, {
      status: 'disabled',
      disabledReason: `Order ${string(order.orderNumber)} was ${string(order.status)}`,
      disabledBy: null,
      disabledAt: ts,
      updatedAt: ts,
    });
    disabled = true;
  });
  return { action: disabled ? 'disabled' : 'notDisabled', giftCardId };
}

// ─────────────────────────────────────────────────────────────────────────────
// New users: cards that were sent to them before they had an account
// ─────────────────────────────────────────────────────────────────────────────

/** E.164 of a `users` doc (`countryCode` + national `phone`), or null. */
export function userE164(user: DocumentData): string | null {
  const phone = stringOrNull(user.phone);
  if (phone === null) return null;
  return normalizePhone(phone.startsWith('+') ? phone : `${stringOrNull(user.countryCode) ?? '+964'}${phone}`);
}

/** Cards a new user may see at once (the rest are linked when they are sent / redeemed). */
export const LINK_BATCH = 50;

/**
 * After the app creates `users/{uid}`: cards sent to the account's VERIFIED
 * phone / email (Firebase Auth, recipients.ts — not the profile doc the app just
 * wrote) before it existed get `recipientUid`; the user is notified once per card.
 */
export async function linkGiftCardsToNewUser(
  deps: NotifyDeps & { recipients?: RecipientLookup },
  uid: string,
  user: DocumentData | undefined,
): Promise<{ linked: string[] }> {
  if (user === undefined || user.isDeleted === true) return { linked: [] };
  const { db } = deps;
  const cards = db.collection(P.giftCards);
  const { phone, email } = await (deps.recipients ?? NO_RECIPIENT_LOOKUP).contactsOf(uid);
  const candidates = new Map<string, DocumentReference>();
  if (phone !== null) {
    for (const d of (await cards.where('recipientPhone', '==', phone).where('recipientUid', '==', null).limit(LINK_BATCH).get()).docs) {
      candidates.set(d.id, d.ref);
    }
  }
  if (email !== null) {
    for (const d of (await cards.where('recipientEmail', '==', email).where('recipientUid', '==', null).limit(LINK_BATCH).get()).docs) {
      candidates.set(d.id, d.ref);
    }
  }

  const linked: string[] = [];
  const toNotify: Array<{ id: string; amount: number; purchaserUid: string | null }> = [];
  for (const ref of candidates.values()) {
    const card = await db.runTransaction(async (tx) => {
      const data = (await tx.get(ref)).data();
      if (data === undefined || stringOrNull(data.recipientUid) !== null) return null;
      tx.update(ref, { recipientUid: uid, updatedAt: FieldValue.serverTimestamp() });
      return data;
    });
    if (card === null) continue;
    linked.push(ref.id);
    if (card.status === 'sent') toNotify.push({ id: ref.id, amount: integer(card.amount), purchaserUid: stringOrNull(card.purchaserUid) });
  }
  // One batched read of the purchasers' names (not one read per card).
  const purchaserUids = [...new Set(toNotify.map((c) => c.purchaserUid).filter((u): u is string => u !== null && !u.includes('/')))];
  const names = new Map<string, string | null>();
  if (purchaserUids.length > 0) {
    for (const snap of await db.getAll(...purchaserUids.map((u) => db.collection(P.users).doc(u)))) {
      names.set(snap.id, stringOrNull(snap.get('name')));
    }
  }
  for (const c of toNotify) {
    await notifyIssued(deps, {
      id: c.id,
      amount: c.amount,
      status: 'sent',
      recipientUid: uid,
      // The purchaser was told when the card went out.
      purchaserUid: null,
      recipientName: '',
      purchaserName: c.purchaserUid === null ? null : (names.get(c.purchaserUid) ?? null),
      scheduledAtMs: null,
    });
  }
  return { linked };
}
