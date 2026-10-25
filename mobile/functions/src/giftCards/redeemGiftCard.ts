/**
 * `redeemGiftCard` (SRS §5.22 "Redeem adds the balance to wallet credits", §7).
 *
 * Data `{ code }` (12 characters, normalized by the app) → `{ giftCardId, amount,
 * credits }`. One transaction: the card must be `sent`, not expired, not disabled
 * and still hold a balance; its balance becomes wallet CREDITS — a
 * `giftCardRedeem` transaction (bucket credits, `giftCardId`, correct
 * `balanceAfter` / `creditsAfter`) and a credit lot (source `giftCard`) that
 * expires with the card — and the card becomes `redeemed` (balance 0,
 * `redeemedAt`, `recipientUid` = the caller).
 *
 * Errors: `unauthenticated`; `not-found` (no card with that code — counted);
 * `failed-precondition` `{ reason: expired | redeemed | disabled | not_sent }`;
 * `resource-exhausted` after 10 wrong codes per user per hour (rolling window in
 * `function_runs/giftCardRedeem:{uid}`, functions only).
 */
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { epochMillis, integer, string } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { readWallet, WalletLedger } from '../wallet/ledger';
import { GIFT_CARD_REDEEM_TITLE } from './giftCardMessages';
import { isGiftCardCode, normalizeGiftCardCode } from './giftCardRules';

export const REDEEM_WRONG_CODE_LIMIT = 10;
export const REDEEM_WINDOW_MS = 60 * 60 * 1000;

export const GiftCardRedeemReason = ['expired', 'redeemed', 'disabled', 'not_sent'] as const;
export type GiftCardRedeemReason = (typeof GiftCardRedeemReason)[number];

const MESSAGES: Record<GiftCardRedeemReason, string> = {
  expired: 'This gift card has expired.',
  redeemed: 'This gift card was already redeemed.',
  disabled: 'This gift card is no longer valid.',
  not_sent: 'This gift card has not been sent yet.',
};

export const NOT_FOUND_MESSAGE = 'No gift card matches this code.';
export const TOO_MANY_MESSAGE = 'Too many wrong codes. Please try again in an hour.';

export interface RedeemResult {
  giftCardId: string;
  amount: number;
  credits: number;
}

export interface RedeemDeps {
  db: Firestore;
  now?: () => number;
}

const throttleId = (uid: string) => `giftCardRedeem:${uid}`;

function recentFailures(raw: unknown, nowMs: number): number[] {
  return Array.isArray(raw)
    ? raw.filter((v): v is number => typeof v === 'number' && Number.isFinite(v) && v > nowMs - REDEEM_WINDOW_MS)
    : [];
}

/** Why a card cannot be redeemed now, or null when it can. */
export function redeemRefusal(card: Record<string, unknown>, nowMs: number): GiftCardRedeemReason | null {
  const status = string(card.status);
  if (status === 'disabled') return 'disabled';
  if (status === 'redeemed' || integer(card.balance) <= 0) return 'redeemed';
  const expiresAt = epochMillis(card.expiresAt);
  if (status === 'expired' || (expiresAt !== null && expiresAt <= nowMs)) return 'expired';
  if (status !== 'sent') return 'not_sent';
  return null;
}

export async function redeemGiftCardCore(deps: RedeemDeps, data: unknown, uid: string | undefined): Promise<RedeemResult> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to redeem a gift card.');
  const raw = typeof data === 'object' && data !== null ? (data as { code?: unknown }).code : undefined;
  if (typeof raw !== 'string' || raw.length > 64) throw new HttpsError('invalid-argument', 'Enter the 12-character code.');
  const code = normalizeGiftCardCode(raw);
  const { db } = deps;
  const nowMs = (deps.now ?? Date.now)();
  const throttleRef = db.collection(P.functionRuns).doc(throttleId(uid));

  if (recentFailures((await throttleRef.get()).get('failures'), nowMs).length >= REDEEM_WRONG_CODE_LIMIT) {
    throw new HttpsError('resource-exhausted', TOO_MANY_MESSAGE);
  }

  const match = isGiftCardCode(code)
    ? (await db.collection(P.giftCards).where('code', '==', code).limit(1).get()).docs[0]
    : undefined;
  if (match === undefined) {
    await db.runTransaction(async (tx) => {
      const failures = recentFailures((await tx.get(throttleRef)).get('failures'), nowMs);
      tx.set(throttleRef, { key: throttleId(uid), failures: [...failures, nowMs], at: FieldValue.serverTimestamp() });
    });
    throw new HttpsError('not-found', NOT_FOUND_MESSAGE);
  }

  return db.runTransaction(async (tx) => {
    // ── Reads ──
    const card = (await tx.get(match.ref)).data();
    if (card === undefined || card.code !== code) throw new HttpsError('not-found', NOT_FOUND_MESSAGE);
    const refusal = redeemRefusal(card, nowMs);
    if (refusal !== null) throw new HttpsError('failed-precondition', MESSAGES[refusal], { reason: refusal });
    const wallet = await readWallet(db, tx, uid);

    // ── Writes ──
    const amount = integer(card.balance);
    const ledger = new WalletLedger(tx, wallet, { idPrefix: `giftCard-${match.id}` });
    ledger.addCredits(
      amount,
      { type: 'giftCardRedeem', title: GIFT_CARD_REDEEM_TITLE, giftCardId: match.id },
      { source: 'giftCard', expiresAtMs: epochMillis(card.expiresAt), giftCardId: match.id },
    );
    ledger.apply();
    const ts = FieldValue.serverTimestamp();
    tx.update(match.ref, { status: 'redeemed', balance: 0, redeemedAt: ts, recipientUid: uid, redeemedBy: uid, updatedAt: ts });
    return { giftCardId: match.id, amount, credits: ledger.credits };
  });
}
