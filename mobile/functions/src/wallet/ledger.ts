/**
 * Wallet ledger (SRS §5.18, §6.11): the ONLY code that changes `wallets/{uid}`.
 * Every movement is one `wallets/{uid}/transactions/{id}` document with the
 * signed amount, its bucket and the wallet's `balanceAfter` / `creditsAfter`
 * right after it — so replaying a wallet's transactions in order always ends at
 * the stored wallet.
 *
 *  - `balance` is real money (refunds, top-ups); it never expires.
 *  - `credits` are promotional. Each credit top-up is a lot
 *    `wallets/{uid}/credit_lots/{id}` = `{ amount, remaining, open, source
 *    (referral | giftCard | refund | admin), expiresAt | null, createdAt, … }`.
 *    Spending consumes the open lots FIFO (oldest `createdAt` first), then any
 *    untracked credits (credits added before lots existed, which never expire);
 *    `expireCredits` debits what is left of a lot once `expiresAt` has passed.
 *
 * Use inside a Firestore transaction: read with `readWallet` / `readOpenCreditLots`
 * (before the transaction's first write), stage movements on a `WalletLedger`,
 * then `apply()` it together with the transaction's other writes. Nothing here
 * goes below zero: a debit larger than the bucket throws (callers check first and
 * answer `insufficient_funds`).
 *
 * Transaction ids are `{idPrefix}-{n}` (n = 1, 2, … in movement order), so the
 * app's `orderBy('createdAt', descending)` lists movements of one commit — which
 * share a server timestamp — newest first, and a fixed prefix (e.g. the order id)
 * makes a writer's transactions deterministic.
 */
import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from 'firebase-admin/firestore';
import type { Trilingual } from '../notifications/orderMessages';
import type { WalletTxnType } from '../shared/enums';
import { epochMillis, integer, string } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';

/** `WalletBucket` (wallet_model.dart). */
export const WalletBucket = ['balance', 'credits'] as const;
export type WalletBucket = (typeof WalletBucket)[number];

/** Where a credit lot came from. */
export const CreditLotSource = ['referral', 'giftCard', 'refund', 'admin'] as const;
export type CreditLotSource = (typeof CreditLotSource)[number];

/** Open lots read per wallet (a wallet holds a handful; the transaction write budget is 500). */
export const MAX_OPEN_LOTS = 200;

export class InsufficientFundsError extends Error {
  constructor(
    readonly bucket: WalletBucket,
    readonly available: number,
    readonly requested: number,
  ) {
    super(`wallet: ${requested} ${bucket} requested, ${available} available`);
  }
}

export interface WalletSnapshot {
  uid: string;
  ref: DocumentReference;
  exists: boolean;
  balance: number;
  credits: number;
}

export interface CreditLot {
  id: string;
  ref: DocumentReference;
  amount: number;
  remaining: number;
  source: string;
  createdAtMs: number;
  expiresAtMs: number | null;
  open: boolean;
}

/** What a transaction document says besides the amounts. */
export interface TxnInput {
  type: WalletTxnType;
  title: Trilingual;
  orderId?: string | null;
  referralId?: string | null;
  giftCardId?: string | null;
  /** The admin who made an `adminAdjustment`. */
  byUid?: string | null;
  /** The admin's reason (dashboard only). */
  reason?: string | null;
}

/** A new credit lot. */
export interface NewLotInput {
  source: CreditLotSource;
  /** Epoch ms; null = never expires. */
  expiresAtMs: number | null;
  orderId?: string | null;
  referralId?: string | null;
  giftCardId?: string | null;
}

/** One staged movement. */
export interface LedgerEntry {
  txnId: string;
  bucket: WalletBucket;
  /** Signed: + credit, − debit. */
  amount: number;
  balanceAfter: number;
  creditsAfter: number;
}

export function walletRef(db: Firestore, uid: string): DocumentReference {
  return db.collection(P.wallets).doc(uid);
}

/** `wallets/{uid}` read in `tx` (a missing wallet reads as 0 / 0). */
export async function readWallet(db: Firestore, tx: Transaction, uid: string): Promise<WalletSnapshot> {
  const ref = walletRef(db, uid);
  const snap = await tx.get(ref);
  return {
    uid,
    ref,
    exists: snap.exists,
    balance: integer(snap.get('balance')),
    credits: integer(snap.get('credits')),
  };
}

export function parseCreditLot(ref: DocumentReference, data: DocumentData): CreditLot {
  const remaining = Math.max(0, integer(data.remaining));
  return {
    id: ref.id,
    ref,
    amount: integer(data.amount),
    remaining,
    source: string(data.source),
    createdAtMs: epochMillis(data.createdAt) ?? 0,
    expiresAtMs: epochMillis(data.expiresAt),
    open: typeof data.open === 'boolean' ? data.open && remaining > 0 : remaining > 0,
  };
}

/** FIFO: oldest first; same instant → by id. */
export function sortFifo<T extends { createdAtMs: number; id: string }>(lots: readonly T[]): T[] {
  return [...lots].sort((a, b) => a.createdAtMs - b.createdAtMs || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

/** The wallet's open lots, FIFO, read in `tx`. */
export async function readOpenCreditLots(db: Firestore, tx: Transaction, uid: string): Promise<CreditLot[]> {
  const snap = await tx.get(
    walletRef(db, uid).collection(P.creditLots).where('open', '==', true).limit(MAX_OPEN_LOTS),
  );
  return sortFifo(snap.docs.map((d) => parseCreditLot(d.ref, d.data())).filter((l) => l.open));
}

/** Pure FIFO plan: how much each lot gives to spend `amount`; `untracked` is the rest. */
export function planFifo(
  lots: ReadonlyArray<{ id: string; remaining: number }>,
  amount: number,
): { takes: Array<{ id: string; take: number; remainingAfter: number }>; untracked: number } {
  let left = Math.max(0, amount);
  const takes: Array<{ id: string; take: number; remainingAfter: number }> = [];
  for (const lot of lots) {
    if (left === 0) break;
    const take = Math.min(lot.remaining, left);
    if (take <= 0) continue;
    takes.push({ id: lot.id, take, remainingAfter: lot.remaining - take });
    left -= take;
  }
  return { takes, untracked: left };
}

function assertAmount(amount: number): void {
  if (!Number.isSafeInteger(amount) || amount <= 0) throw new Error(`wallet: invalid amount ${amount}`);
}

/** Stages movements on one wallet inside a transaction; `apply()` writes them. */
export class WalletLedger {
  private balanceNow: number;
  private creditsNow: number;
  private seq = 0;
  private readonly prefix: string;
  private readonly lots: Map<string, CreditLot> | null;
  private readonly txns: Array<{ ref: DocumentReference; data: DocumentData }> = [];
  private readonly newLots: Array<{ ref: DocumentReference; data: DocumentData }> = [];
  private readonly lotUpdates = new Map<string, { ref: DocumentReference; data: DocumentData }>();
  readonly entries: LedgerEntry[] = [];

  constructor(
    private readonly tx: Transaction,
    readonly wallet: WalletSnapshot,
    options: {
      /** Transaction id prefix; default: a fresh auto id. */
      idPrefix?: string;
      /** The wallet's open lots (`readOpenCreditLots`) — required to spend or expire credits. */
      openLots?: readonly CreditLot[];
    } = {},
  ) {
    this.balanceNow = wallet.balance;
    this.creditsNow = wallet.credits;
    this.prefix = options.idPrefix ?? wallet.ref.collection(P.transactions).doc().id;
    this.lots = options.openLots === undefined ? null : new Map(sortFifo(options.openLots).map((l) => [l.id, { ...l }]));
  }

  get balance(): number {
    return this.balanceNow;
  }

  get credits(): number {
    return this.creditsNow;
  }

  /** + real money (refund, top-up, admin). */
  addBalance(amount: number, txn: TxnInput): LedgerEntry {
    assertAmount(amount);
    this.balanceNow += amount;
    return this.record('balance', amount, txn);
  }

  /** − real money; throws `InsufficientFundsError` below zero. */
  spendBalance(amount: number, txn: TxnInput): LedgerEntry {
    assertAmount(amount);
    if (amount > this.balanceNow) throw new InsufficientFundsError('balance', this.balanceNow, amount);
    this.balanceNow -= amount;
    return this.record('balance', -amount, txn);
  }

  /** + credits as a new lot with its own expiry. */
  addCredits(amount: number, txn: TxnInput, lot: NewLotInput): LedgerEntry {
    assertAmount(amount);
    this.creditsNow += amount;
    const entry = this.record('credits', amount, txn);
    const ref = this.wallet.ref.collection(P.creditLots).doc();
    const now = FieldValue.serverTimestamp();
    this.newLots.push({
      ref,
      data: {
        amount,
        remaining: amount,
        open: true,
        source: lot.source,
        expiresAt: lot.expiresAtMs === null ? null : Timestamp.fromMillis(lot.expiresAtMs),
        orderId: lot.orderId ?? null,
        referralId: lot.referralId ?? null,
        giftCardId: lot.giftCardId ?? null,
        txnId: entry.txnId,
        createdAt: now,
        updatedAt: now,
      },
    });
    return entry;
  }

  /** − credits: the open lots FIFO, then untracked credits. Throws below zero. */
  spendCredits(amount: number, txn: TxnInput): LedgerEntry {
    assertAmount(amount);
    const lots = this.requireLots();
    if (amount > this.creditsNow) throw new InsufficientFundsError('credits', this.creditsNow, amount);
    const open = [...lots.values()].filter((l) => l.open && l.remaining > 0);
    for (const take of planFifo(open, amount).takes) {
      const lot = lots.get(take.id)!;
      lot.remaining = take.remainingAfter;
      lot.open = lot.remaining > 0;
      this.lotUpdates.set(lot.id, {
        ref: lot.ref,
        data: { remaining: lot.remaining, open: lot.open, updatedAt: FieldValue.serverTimestamp() },
      });
    }
    this.creditsNow -= amount;
    return this.record('credits', -amount, txn);
  }

  /**
   * Closes the given open lots (expired at `nowMs`): each gives up what is left
   * of it, but the wallet never goes below zero. One `txn` for the total, or null
   * when nothing was left to debit (the lots are closed either way).
   */
  expireLots(lotIds: readonly string[], nowMs: number, txn: TxnInput): LedgerEntry | null {
    const lots = this.requireLots();
    let total = 0;
    for (const id of lotIds) {
      const lot = lots.get(id);
      if (lot === undefined || !lot.open) continue;
      const take = Math.min(lot.remaining, this.creditsNow - total);
      total += take;
      lot.remaining = 0;
      lot.open = false;
      this.lotUpdates.set(lot.id, {
        ref: lot.ref,
        data: {
          remaining: 0,
          open: false,
          expiredAmount: take,
          expiredAt: Timestamp.fromMillis(nowMs),
          updatedAt: FieldValue.serverTimestamp(),
        },
      });
    }
    if (total <= 0) return null;
    this.creditsNow -= total;
    return this.record('credits', -total, txn);
  }

  /** Writes the wallet, its new transactions and the lot changes through the transaction. */
  apply(): void {
    const now = FieldValue.serverTimestamp();
    if (this.txns.length > 0) {
      if (this.wallet.exists) {
        this.tx.update(this.wallet.ref, { balance: this.balanceNow, credits: this.creditsNow, updatedAt: now });
      } else {
        this.tx.create(this.wallet.ref, {
          balance: this.balanceNow,
          credits: this.creditsNow,
          currency: 'IQD',
          createdAt: now,
          updatedAt: now,
        });
      }
    }
    for (const t of this.txns) this.tx.create(t.ref, t.data);
    for (const l of this.newLots) this.tx.create(l.ref, l.data);
    for (const l of this.lotUpdates.values()) this.tx.update(l.ref, l.data);
  }

  private requireLots(): Map<string, CreditLot> {
    if (this.lots === null) throw new Error('wallet: open credit lots were not loaded');
    return this.lots;
  }

  private record(bucket: WalletBucket, amount: number, txn: TxnInput): LedgerEntry {
    const txnId = `${this.prefix}-${++this.seq}`;
    const entry: LedgerEntry = {
      txnId,
      bucket,
      amount,
      balanceAfter: this.balanceNow,
      creditsAfter: this.creditsNow,
    };
    this.entries.push(entry);
    this.txns.push({
      ref: this.wallet.ref.collection(P.transactions).doc(txnId),
      data: {
        type: txn.type,
        amount,
        bucket,
        title: txn.title.en,
        titleAr: txn.title.ar,
        titleKu: txn.title.ku,
        orderId: txn.orderId ?? null,
        referralId: txn.referralId ?? null,
        giftCardId: txn.giftCardId ?? null,
        byUid: txn.byUid ?? null,
        reason: txn.reason ?? null,
        balanceAfter: this.balanceNow,
        creditsAfter: this.creditsNow,
        createdAt: FieldValue.serverTimestamp(),
      },
    });
    return entry;
  }
}
