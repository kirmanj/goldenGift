/**
 * `expireCredits` (SRS §7, scheduled daily 03:00 Asia/Baghdad): every credit lot
 * whose `expiresAt` has passed and that still has `remaining` credits is closed,
 * and the wallet loses what was left of it — one `creditExpiry` transaction per
 * wallet and run (bucket `credits`, never below zero).
 *
 * Batched: a collection-group query over `credit_lots` (`open == true`,
 * `expiresAt <= now`, index credit_lots (open, expiresAt) collection group),
 * paged with a cursor; one transaction per wallet re-reads its lots, so a lot
 * spent at the same moment is never debited twice. Idempotent: a closed lot is
 * never matched again, so a re-run (or a retried one) expires nothing twice.
 * Gift-card expiry joins this job in Phase 8.
 */
import { Timestamp, type DocumentReference, type Firestore, type QueryDocumentSnapshot } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { FirestorePaths as P } from '../shared/paths';
import { parseCreditLot, readWallet, WalletLedger } from './ledger';
import { CREDIT_EXPIRY_TITLE } from './walletTexts';

export const EXPIRE_PAGE_SIZE = 300;
/** Upper bound per run (pages × page size lots); the next run continues. */
export const EXPIRE_MAX_PAGES = 100;

export interface ExpireCreditsDeps {
  db: Firestore;
  logger?: Pick<typeof functionsLogger, 'warn'>;
}

export interface ExpireCreditsResult {
  /** Wallets that lost credits. */
  wallets: number;
  /** Lots closed. */
  lots: number;
  /** Credits debited (IQD). */
  expired: number;
  /** Wallets whose transaction failed (retried by the next run). */
  failed: number;
}

/** Closes the due lots of one wallet in a transaction. */
export async function expireWalletLots(
  db: Firestore,
  uid: string,
  lotRefs: readonly DocumentReference[],
  nowMs: number,
): Promise<{ lots: number; expired: number }> {
  return db.runTransaction(async (tx) => {
    // ── Reads ──
    const wallet = await readWallet(db, tx, uid);
    const snaps = lotRefs.length === 0 ? [] : await tx.getAll(...lotRefs);
    const due = snaps
      .filter((s) => s.exists)
      .map((s) => parseCreditLot(s.ref, s.data()!))
      .filter((l) => l.open && l.expiresAtMs !== null && l.expiresAtMs <= nowMs);
    if (due.length === 0) return { lots: 0, expired: 0 };

    // ── Writes ──
    const ledger = new WalletLedger(tx, wallet, { openLots: due });
    const entry = ledger.expireLots(
      due.map((l) => l.id),
      nowMs,
      { type: 'creditExpiry', title: CREDIT_EXPIRY_TITLE },
    );
    ledger.apply();
    return { lots: due.length, expired: entry === null ? 0 : -entry.amount };
  });
}

export async function expireCredits(
  deps: ExpireCreditsDeps,
  nowMs: number,
  options: { pageSize?: number; maxPages?: number } = {},
): Promise<ExpireCreditsResult> {
  const { db } = deps;
  const log = deps.logger ?? functionsLogger;
  const pageSize = options.pageSize ?? EXPIRE_PAGE_SIZE;
  const maxPages = options.maxPages ?? EXPIRE_MAX_PAGES;
  const result: ExpireCreditsResult = { wallets: 0, lots: 0, expired: 0, failed: 0 };
  const debited = new Set<string>();
  const failed = new Set<string>();

  let cursor: QueryDocumentSnapshot | null = null;
  for (let page = 0; page < maxPages; page++) {
    let query = db
      .collectionGroup(P.creditLots)
      .where('open', '==', true)
      .where('expiresAt', '<=', Timestamp.fromMillis(nowMs))
      .orderBy('expiresAt')
      .limit(pageSize);
    if (cursor !== null) query = query.startAfter(cursor);
    const snap = await query.get();
    if (snap.empty) break;
    cursor = snap.docs[snap.docs.length - 1];

    // Only wallets/{uid}/credit_lots/{id}.
    const byWallet = new Map<string, DocumentReference[]>();
    for (const doc of snap.docs) {
      const walletDoc = doc.ref.parent.parent;
      if (walletDoc === null || walletDoc.parent.id !== P.wallets || walletDoc.parent.parent !== null) continue;
      byWallet.set(walletDoc.id, [...(byWallet.get(walletDoc.id) ?? []), doc.ref]);
    }
    for (const [uid, refs] of byWallet) {
      try {
        const r = await expireWalletLots(db, uid, refs, nowMs);
        result.lots += r.lots;
        result.expired += r.expired;
        if (r.expired > 0) debited.add(uid);
      } catch (e) {
        failed.add(uid);
        log.warn('expireCredits: wallet failed', { uid, error: e instanceof Error ? e.message : String(e) });
      }
    }
    if (snap.size < pageSize) break;
  }
  return { ...result, wallets: debited.size, failed: failed.size };
}
