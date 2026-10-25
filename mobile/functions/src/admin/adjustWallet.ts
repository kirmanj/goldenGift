/**
 * `adjustWallet` (SRS §9 Users "adjust wallet or credits (with reason)", §6.11):
 * a super or finance admin adds to / takes from a customer's balance or credits.
 *
 * One transaction: the wallet (created at 0 / 0 when `onUserCreate` has not made
 * it yet), one `adminAdjustment` transaction (`byUid`, `reason`, correct
 * `balanceAfter` / `creditsAfter`) and the `admin_audit_log` entry `wallet.adjust`.
 * Positive credits become a lot (source `admin`, expiring per
 * `app_settings/referral.creditsExpiryDays`); negative credits are taken FIFO from
 * the open lots. Nothing goes below zero (`insufficient_funds`).
 *
 * Optional `requestId` (≤ 128, no `/`): the same id again returns the first
 * result without adjusting twice (a retried call).
 */
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { FirestorePaths as P } from '../shared/paths';
import { readOpenCreditLots, readWallet, WalletLedger, type CreditLot, type WalletBucket } from '../wallet/ledger';
import { creditExpiryAt, parseReferralSettings } from '../wallet/walletSettings';
import { adjustmentTitle } from '../wallet/walletTexts';
import { auditLogEntry, isUid, requireAdminRole } from './adminRoles';
import type { AdminCaller, AdminRole } from './setAdminClaim';

/** `UsersAccess.canAdjustWallet` in the dashboard. */
export const ADJUST_WALLET_ROLES: readonly AdminRole[] = ['super', 'finance'];
/** `WalletAdjustment.maxAmount` / `reasonMin` / `reasonMax`. */
export const MAX_ADJUSTMENT = 10_000_000;
export const ADJUST_REASON_MIN = 3;
export const ADJUST_REASON_MAX = 300;
export const AUDIT_ACTION_WALLET_ADJUST = 'wallet.adjust';

export interface AdjustWalletRequest {
  uid: string;
  bucket: WalletBucket;
  /** Signed whole IQD, ≠ 0. */
  amount: number;
  reason: string;
  requestId: string | null;
}

export interface AdjustWalletResult {
  balance: number;
  credits: number;
  txnId: string;
}

export interface AdjustWalletDeps {
  db: Firestore;
  now?: () => number;
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

export function parseAdjustWalletData(data: unknown): AdjustWalletRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw bad("Expected { uid, bucket: 'balance' | 'credits', amount, reason }.");
  }
  const d = data as Record<string, unknown>;
  if (!isUid(d.uid)) throw bad('`uid` is missing or invalid.');
  if (d.bucket !== 'balance' && d.bucket !== 'credits') throw bad("`bucket` must be 'balance' or 'credits'.");
  if (typeof d.amount !== 'number' || !Number.isSafeInteger(d.amount) || d.amount === 0) {
    throw bad('`amount` must be a whole number of IQD other than 0.');
  }
  if (Math.abs(d.amount) > MAX_ADJUSTMENT) throw bad(`\`amount\` may be at most ${MAX_ADJUSTMENT} IQD either way.`);
  const reason = typeof d.reason === 'string' ? d.reason.trim() : '';
  if (reason.length < ADJUST_REASON_MIN || reason.length > ADJUST_REASON_MAX) {
    throw bad(`\`reason\` must be ${ADJUST_REASON_MIN}–${ADJUST_REASON_MAX} characters.`);
  }
  let requestId: string | null = null;
  if (d.requestId !== undefined && d.requestId !== null) {
    if (!isUid(d.requestId)) throw bad('`requestId` is invalid.');
    requestId = d.requestId;
  }
  return { uid: d.uid, bucket: d.bucket, amount: d.amount, reason, requestId };
}

export async function adjustWalletCore(
  deps: AdjustWalletDeps,
  data: unknown,
  caller: AdminCaller,
): Promise<AdjustWalletResult> {
  const { db } = deps;
  const admin = await requireAdminRole(db, caller, ADJUST_WALLET_ROLES, 'Only super and finance admins can adjust wallets.');
  const request = parseAdjustWalletData(data);
  const nowMs = (deps.now ?? Date.now)();
  const userRef = db.collection(P.users).doc(request.uid);
  const runRef = request.requestId === null ? null : db.collection(P.functionRuns).doc(`adjustWallet:${request.requestId}`);

  return db.runTransaction(async (tx) => {
    // ── Reads ──
    if (runRef !== null) {
      const run = await tx.get(runRef);
      if (run.exists) return run.get('result') as AdjustWalletResult;
    }
    const user = await tx.get(userRef);
    if (!user.exists) throw new HttpsError('not-found', 'No user with that uid.');
    const wallet = await readWallet(db, tx, request.uid);
    const credits = request.bucket === 'credits';
    const lots: CreditLot[] | undefined = credits && request.amount < 0 ? await readOpenCreditLots(db, tx, request.uid) : undefined;
    const settings =
      credits && request.amount > 0
        ? parseReferralSettings((await tx.get(db.collection(P.appSettings).doc('referral'))).data())
        : null;

    const current = credits ? wallet.credits : wallet.balance;
    if (current + request.amount < 0) {
      throw new HttpsError(
        'failed-precondition',
        `This would take the ${request.bucket} below zero (it is ${current} IQD).`,
        { reason: 'insufficient_funds' },
      );
    }

    // ── Writes ──
    const ledger = new WalletLedger(tx, wallet, { openLots: lots });
    const txn = {
      type: 'adminAdjustment' as const,
      title: adjustmentTitle(request.bucket),
      byUid: admin.uid,
      reason: request.reason,
    };
    const amount = Math.abs(request.amount);
    const entry = !credits
      ? request.amount > 0
        ? ledger.addBalance(amount, txn)
        : ledger.spendBalance(amount, txn)
      : request.amount > 0
        ? ledger.addCredits(amount, txn, { source: 'admin', expiresAtMs: creditExpiryAt(nowMs, settings!.creditsExpiryDays) })
        : ledger.spendCredits(amount, txn);
    ledger.apply();

    const result: AdjustWalletResult = { balance: ledger.balance, credits: ledger.credits, txnId: entry.txnId };
    tx.create(
      db.collection(P.adminAuditLog).doc(),
      auditLogEntry(
        admin.uid,
        AUDIT_ACTION_WALLET_ADJUST,
        `${P.wallets}/${request.uid}`,
        { balance: wallet.balance, credits: wallet.credits },
        { ...result, bucket: request.bucket, amount: request.amount, reason: request.reason },
      ),
    );
    if (runRef !== null) tx.create(runRef, { key: runRef.id, result, at: FieldValue.serverTimestamp() });
    return result;
  });
}
