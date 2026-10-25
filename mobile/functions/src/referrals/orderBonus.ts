/**
 * `orderBonus` (SRS §5.19, §7 `onOrderStatusChange`): when a referred customer's
 * first order is DELIVERED and PAID, the referrer gets `app_settings/referral.orderBonus`
 * credits — exactly once per referral, however often events replay and however
 * many orders the friend places.
 *
 * Once-only: `runOnceIf` with `function_runs/orderBonus:{referralId}` — the
 * marker commits together with the payment (or with the abuse cancellation), and
 * an order that does not qualify writes nothing, so the next one is checked again.
 * The order is also flagged `referralCredited` and the referral keeps
 * `orderBonusPaid` / `firstOrderId`.
 *
 * Qualifies: referral `pending`; the order is this referral's friend's, `delivered`,
 * `paymentStatus` `paid`, not yet `referralCredited`, and paid with money
 * (`total + walletUsed > 0` — an order paid entirely with credits does not count).
 *
 * Abuse checks first (SRS §5.19) — the referral is cancelled with a flag instead
 * of paid: the referrer is deleted (`deleted`) or blocked (`blocked`), the friend
 * is blocked / deleted (`blocked`), self-referral (`selfReferral`), or both
 * accounts carry the same `deviceId` (`sameDevice`).
 *
 * After the commit the referrer is notified (in-app + push in their language,
 * type `referralCredited`, opens `/invite`), once (fixed notification id).
 */
import { FieldValue, type DocumentData } from 'firebase-admin/firestore';
import { notifyUser, type NotifyDeps } from '../notifications/notifyUser';
import { integer, stringOrNull } from '../shared/firestoreParse';
import { runOnceIf } from '../shared/idempotency';
import { FirestorePaths as P } from '../shared/paths';
import { readWallet, WalletLedger } from '../wallet/ledger';
import { creditExpiryAt, parseReferralSettings } from '../wallet/walletSettings';
import { ORDER_BONUS_TITLE, orderBonusNotification } from '../wallet/walletTexts';

export type OrderBonusOutcome =
  | { status: 'paid'; referralId: string; amount: number; notified: boolean }
  | { status: 'cancelled'; referralId: string; flag: string }
  | { status: 'notDue' };

export function orderBonusKey(referralId: string): string {
  return `orderBonus:${referralId}`;
}

function deviceIdOf(data: DocumentData | undefined): string | null {
  const id = data?.deviceId;
  return typeof id === 'string' && id.trim().length > 0 ? id.trim() : null;
}

/** The abuse flag that cancels this referral, or null when it may be paid. */
export function referralAbuseFlag(
  referral: DocumentData,
  referrer: DocumentData | undefined,
  referred: DocumentData | undefined,
): string | null {
  if (referrer === undefined || referrer.isDeleted === true) return 'deleted';
  if (referrer.isBlocked === true) return 'blocked';
  if (referred === undefined || referred.isDeleted === true || referred.isBlocked === true) return 'blocked';
  if (referral.referrerUid === referral.referredUid) return 'selfReferral';
  const device = deviceIdOf(referrer);
  if (device !== null && device === deviceIdOf(referred)) return 'sameDevice';
  return null;
}

/** Whether `order` can complete its customer's referral. */
export function orderQualifies(order: DocumentData | undefined, referredUid: string): boolean {
  return (
    order !== undefined &&
    order.userId === referredUid &&
    order.status === 'delivered' &&
    order.paymentStatus === 'paid' &&
    order.referralCredited !== true &&
    integer(order.total) + integer(order.walletUsed) > 0
  );
}

/**
 * Checks `orderId` (just delivered) against its customer's referral and pays
 * the referrer when it is due. Safe to call for every delivered event.
 */
export async function applyOrderBonus(
  deps: NotifyDeps & { now?: () => number },
  orderId: string,
  referredUid: string,
): Promise<OrderBonusOutcome> {
  const { db } = deps;
  const referralId = referredUid; // referrals/{referredUid}
  const referralRef = db.collection(P.referrals).doc(referralId);
  const orderRef = db.collection(P.orders).doc(orderId);
  const nowMs = (deps.now ?? Date.now)();

  let outcome: OrderBonusOutcome = { status: 'notDue' };
  await runOnceIf(db, orderBonusKey(referralId), async (tx) => {
    outcome = { status: 'notDue' };
    // ── Reads ──
    const [referralSnap, orderSnap] = await tx.getAll(referralRef, orderRef);
    const referral = referralSnap.data();
    if (referral === undefined || referral.status !== 'pending' || referral.orderBonusPaid === true) return false;
    if (referral.referredUid !== referredUid) return false;
    if (!orderQualifies(orderSnap.data(), referredUid)) return false;
    const referrerUid = stringOrNull(referral.referrerUid);
    if (referrerUid === null || referrerUid.includes('/')) return false;

    const [referrerSnap, referredSnap, settingsSnap] = await tx.getAll(
      db.collection(P.users).doc(referrerUid),
      db.collection(P.users).doc(referredUid),
      db.collection(P.appSettings).doc('referral'),
    );
    const flag = referralAbuseFlag(referral, referrerSnap.data(), referredSnap.data());
    const settings = parseReferralSettings(settingsSnap.data());
    const wallet = flag === null && settings.orderBonus > 0 ? await readWallet(db, tx, referrerUid) : null;

    // ── Writes ──
    const ts = FieldValue.serverTimestamp();
    if (flag !== null) {
      tx.update(referralRef, { status: 'cancelled', flags: FieldValue.arrayUnion(flag), updatedAt: ts });
      outcome = { status: 'cancelled', referralId, flag };
      return true;
    }
    if (wallet !== null) {
      const ledger = new WalletLedger(tx, wallet, { idPrefix: `orderBonus-${referralId}` });
      ledger.addCredits(
        settings.orderBonus,
        { type: 'referralCredit', title: ORDER_BONUS_TITLE, referralId, orderId },
        { source: 'referral', expiresAtMs: creditExpiryAt(nowMs, settings.creditsExpiryDays), referralId, orderId },
      );
      ledger.apply();
    }
    tx.update(referralRef, {
      status: 'completed',
      orderBonusPaid: wallet !== null,
      orderBonusAmount: wallet !== null ? settings.orderBonus : 0,
      firstOrderId: orderId,
      completedAt: ts,
      updatedAt: ts,
    });
    tx.update(orderRef, { referralCredited: true, updatedAt: ts });
    outcome = { status: 'paid', referralId, amount: wallet !== null ? settings.orderBonus : 0, notified: false };
    return true;
  });

  // Notify (also when an earlier attempt paid but failed before notifying: the fixed id sends it once).
  const referral = (await referralRef.get()).data();
  const amount = integer(referral?.orderBonusAmount);
  if (referral?.status === 'completed' && referral.firstOrderId === orderId && referral.orderBonusPaid === true && amount > 0) {
    const referrerUid = stringOrNull(referral.referrerUid);
    if (referrerUid !== null) {
      const result = await notifyUser(
        deps,
        referrerUid,
        orderBonusNotification(referralId, amount, stringOrNull(referral.referredName)),
        { notificationId: `referral-${referralId}-orderBonus` },
      );
      const ran = outcome as OrderBonusOutcome; // assigned inside the transaction callback
      if (ran.status === 'paid') outcome = { ...ran, notified: result.created };
    }
  }
  return outcome as OrderBonusOutcome;
}
