/**
 * `joinBonus` (SRS §5.19, §7 `onUserCreate`): after `processNewUser` created the
 * pending `referrals/{uid}`, the NEW user gets `app_settings/referral.joinBonus`
 * credits (a lot, source `referral`, expiring `creditsExpiryDays` from now; a
 * `referralCredit` transaction with the referral id; `joinBonusPaid`; an in-app
 * "welcome gift" notification) — unless the referrer already has
 * `maxReferralsPerMonth` referrals this Iraq-time month, in which case the
 * referral is cancelled with the flag `monthlyCap`, nothing is paid and the new
 * user gets the usual "referral code not applied" notice.
 *
 * The cap counts the referrer's non-cancelled referrals of the month created
 * BEFORE this one (same instant → lower id first), so simultaneous sign-ups at
 * the cap are decided the same way whatever order their functions run in.
 *
 * Once per referral: `function_runs/joinBonus:{referralId}` commits with the
 * decision (paid / capped / no bonus configured).
 */
import { FieldValue, Timestamp, type Firestore, type QueryDocumentSnapshot, type QuerySnapshot, type Transaction } from 'firebase-admin/firestore';
import { notificationDoc } from '../notifications/notifyUser';
import { BAGHDAD_UTC_OFFSET_MS, baghdadNow } from '../orders/checkoutRules';
import { epochMillis, stringOrNull } from '../shared/firestoreParse';
import { runOnceIf } from '../shared/idempotency';
import { FirestorePaths as P } from '../shared/paths';
import { referralNotAppliedNotification } from '../users/referralNotice';
import { readWallet, WalletLedger } from '../wallet/ledger';
import { creditExpiryAt, parseReferralSettings } from '../wallet/walletSettings';
import { JOIN_BONUS_TITLE, joinBonusNotification } from '../wallet/walletTexts';

export type JoinBonusOutcome =
  | { status: 'paid'; amount: number }
  | { status: 'monthlyCap' }
  /** joinBonus is 0: the referral stays pending without a payment. */
  | { status: 'noBonus' }
  /** No pending referral for this user, or already decided. */
  | { status: 'skipped' };

export function joinBonusKey(referralId: string): string {
  return `joinBonus:${referralId}`;
}

/** Start (epoch ms) of the Iraq-time calendar month containing `ms`. */
export function baghdadMonthStartMs(ms: number): number {
  const t = baghdadNow(ms);
  return Date.UTC(t.year, t.month - 1, 1) - BAGHDAD_UTC_OFFSET_MS;
}

/** Referrals read per page while counting toward the monthly cap. */
export const CAP_PAGE_SIZE = 100;

/**
 * The referrer's non-cancelled referrals this month created before `referralId`
 * (read in `tx`), counted up to `cap` — paged in `createdAt` order and stopped as
 * soon as the cap is reached or the referrals are no longer earlier, so a very
 * popular referrer never means an unbounded read.
 */
async function earlierReferralsThisMonth(
  db: Firestore,
  tx: Transaction,
  referrerUid: string,
  referralId: string,
  createdAtMs: number,
  cap: number,
): Promise<number> {
  const base = db
    .collection(P.referrals)
    .where('referrerUid', '==', referrerUid)
    .where('createdAt', '>=', Timestamp.fromMillis(baghdadMonthStartMs(createdAtMs)))
    .orderBy('createdAt')
    .limit(CAP_PAGE_SIZE);
  let count = 0;
  let last: QueryDocumentSnapshot | null = null;
  for (;;) {
    const snap: QuerySnapshot = await tx.get(last === null ? base : base.startAfter(last));
    for (const d of snap.docs) {
      const at = epochMillis(d.get('createdAt'));
      if (at === null) continue;
      if (at > createdAtMs || (at === createdAtMs && d.id >= referralId)) return count;
      if (d.get('status') !== 'cancelled') count++;
      if (count >= cap) return count;
    }
    if (snap.size < CAP_PAGE_SIZE) return count;
    last = snap.docs[snap.docs.length - 1];
  }
}

export async function applyJoinBonus(
  db: Firestore,
  uid: string,
  options: { now?: () => number } = {},
): Promise<JoinBonusOutcome> {
  const referralId = uid; // referrals/{referredUid}
  const referralRef = db.collection(P.referrals).doc(referralId);
  const userRef = db.collection(P.users).doc(uid);
  const nowMs = (options.now ?? Date.now)();

  let outcome: JoinBonusOutcome = { status: 'skipped' };
  await runOnceIf(db, joinBonusKey(referralId), async (tx) => {
    outcome = { status: 'skipped' };
    // ── Reads ──
    const [referralSnap, userSnap, settingsSnap] = await tx.getAll(
      referralRef,
      userRef,
      db.collection(P.appSettings).doc('referral'),
    );
    const referral = referralSnap.data();
    if (referral === undefined || referral.referredUid !== uid) return false;
    if (referral.status !== 'pending' || referral.joinBonusPaid === true) return false;
    const referrerUid = stringOrNull(referral.referrerUid);
    const user = userSnap.data();
    if (referrerUid === null || user === undefined || user.isDeleted === true) return false;

    const settings = parseReferralSettings(settingsSnap.data());
    const createdAtMs = epochMillis(referral.createdAt) ?? nowMs;
    const capped =
      settings.maxReferralsPerMonth > 0 &&
      (await earlierReferralsThisMonth(db, tx, referrerUid, referralId, createdAtMs, settings.maxReferralsPerMonth)) >=
        settings.maxReferralsPerMonth;
    const wallet = !capped && settings.joinBonus > 0 ? await readWallet(db, tx, uid) : null;

    // ── Writes ──
    const ts = FieldValue.serverTimestamp();
    if (capped) {
      tx.update(referralRef, { status: 'cancelled', flags: FieldValue.arrayUnion('monthlyCap'), updatedAt: ts });
      tx.create(db.collection(P.notifications).doc(`${uid}-referralNotApplied`), referralNotAppliedNotification(uid));
      outcome = { status: 'monthlyCap' };
      return true;
    }
    if (wallet === null) {
      outcome = { status: 'noBonus' };
      return true;
    }
    const ledger = new WalletLedger(tx, wallet, { idPrefix: `joinBonus-${referralId}` });
    ledger.addCredits(
      settings.joinBonus,
      { type: 'referralCredit', title: JOIN_BONUS_TITLE, referralId },
      { source: 'referral', expiresAtMs: creditExpiryAt(nowMs, settings.creditsExpiryDays), referralId },
    );
    ledger.apply();
    tx.update(referralRef, { joinBonusPaid: true, joinBonusAmount: settings.joinBonus, updatedAt: ts });
    tx.create(
      db.collection(P.notifications).doc(`${uid}-joinBonus`),
      notificationDoc(uid, joinBonusNotification(referralId, settings.joinBonus)),
    );
    outcome = { status: 'paid', amount: settings.joinBonus };
    return true;
  });
  return outcome;
}
