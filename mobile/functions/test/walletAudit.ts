/**
 * Emulator-test helpers for wallets: seed money the way the functions do (through
 * the ledger, so every change has its transaction) and check the SRS Phase 7 exit
 * criterion — every wallet change has a matching transaction with correct
 * `balanceAfter` / `creditsAfter`.
 */
import assert from 'node:assert/strict';
import type { DocumentData, Firestore } from 'firebase-admin/firestore';
import { epochMillis, integer } from '../src/shared/firestoreParse';
import { readWallet, WalletLedger, type CreditLotSource } from '../src/wallet/ledger';

const TITLE = { en: 'Test', ar: 'اختبار', ku: 'تاقیکردنەوە' };

/** Adds a credit lot (source `admin` unless given) through the ledger. */
export async function grantCredits(
  db: Firestore,
  uid: string,
  amount: number,
  lot: { expiresAtMs?: number | null; source?: CreditLotSource } = {},
): Promise<void> {
  await db.runTransaction(async (tx) => {
    const ledger = new WalletLedger(tx, await readWallet(db, tx, uid));
    ledger.addCredits(amount, { type: 'adminAdjustment', title: TITLE }, { source: lot.source ?? 'admin', expiresAtMs: lot.expiresAtMs ?? null });
    ledger.apply();
  });
}

/** Adds real money through the ledger. */
export async function grantBalance(db: Firestore, uid: string, amount: number): Promise<void> {
  await db.runTransaction(async (tx) => {
    const ledger = new WalletLedger(tx, await readWallet(db, tx, uid));
    ledger.addBalance(amount, { type: 'adminAdjustment', title: TITLE });
    ledger.apply();
  });
}

/** The wallet's transactions in the order they happened (createdAt, then id). */
export async function walletTxns(db: Firestore, uid: string): Promise<Array<DocumentData & { id: string }>> {
  const snap = await db.collection(`wallets/${uid}/transactions`).get();
  return snap.docs
    .map((d): DocumentData & { id: string } => ({ id: d.id, ...d.data() }))
    .sort((a, b) => (epochMillis(a.createdAt) ?? 0) - (epochMillis(b.createdAt) ?? 0) || (a.id < b.id ? -1 : 1));
}

/**
 * Replays the transactions from `start` and checks every `balanceAfter` /
 * `creditsAfter` and the final wallet; open lots never hold more than the
 * credits. Returns the wallet.
 */
export async function assertWalletConsistent(
  db: Firestore,
  uid: string,
  start: { balance: number; credits: number } = { balance: 0, credits: 0 },
): Promise<{ balance: number; credits: number }> {
  let balance = start.balance;
  let credits = start.credits;
  for (const t of await walletTxns(db, uid)) {
    assert.ok(t.bucket === 'balance' || t.bucket === 'credits', `${t.id}: bucket`);
    assert.ok(Number.isInteger(t.amount) && t.amount !== 0, `${t.id}: amount ${t.amount}`);
    if (t.bucket === 'balance') balance += t.amount;
    else credits += t.amount;
    assert.equal(t.balanceAfter, balance, `${t.id}: balanceAfter`);
    assert.equal(t.creditsAfter, credits, `${t.id}: creditsAfter`);
    assert.ok(balance >= 0 && credits >= 0, `${t.id}: below zero`);
    for (const key of ['title', 'titleAr', 'titleKu']) assert.ok(typeof t[key] === 'string' && t[key].length > 0, `${t.id}: ${key}`);
  }
  const wallet = (await db.doc(`wallets/${uid}`).get()).data();
  assert.equal(integer(wallet?.balance), balance, 'wallet balance');
  assert.equal(integer(wallet?.credits), credits, 'wallet credits');
  const lots = await db.collection(`wallets/${uid}/credit_lots`).where('open', '==', true).get();
  const open = lots.docs.reduce((s, d) => s + integer(d.get('remaining')), 0);
  assert.ok(open <= credits, `open lots ${open} > credits ${credits}`);
  return { balance, credits };
}
