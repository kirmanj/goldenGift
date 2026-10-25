/**
 * expireCredits against the Firestore emulator (skipped without it), with an
 * injected "now". Own demo- project, cleared before every test.
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { readOpenCreditLots, readWallet, WalletLedger } from '../src/wallet/ledger';
import { DAY_MS } from '../src/wallet/walletSettings';
import { expireCredits } from '../src/wallet/expireCredits';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { assertWalletConsistent, grantBalance, grantCredits, walletTxns } from './walletAudit';

const PROJECT = 'demo-goldengift-expire-credits';
const T0 = Date.UTC(2026, 9, 21, 0, 0);

describe('expireCredits (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `expire-credits-${runId()}`);
  const db = getFirestore(app);
  const deps = { db, logger: { warn: () => undefined } };

  const read = async (path: string) => (await db.doc(path).get()).data();
  const lots = async (uid: string) =>
    (await db.collection(`wallets/${uid}/credit_lots`).get()).docs.map((d) => d.data()).sort((a, b) => a.amount - b.amount);

  async function spendCredits(uid: string, amount: number): Promise<void> {
    await db.runTransaction(async (tx) => {
      const wallet = await readWallet(db, tx, uid);
      const ledger = new WalletLedger(tx, wallet, { openLots: await readOpenCreditLots(db, tx, uid) });
      ledger.spendCredits(amount, { type: 'orderPayment', title: { en: 'Order', ar: 'الطلب', ku: 'داواکاری' } });
      ledger.apply();
    });
  }

  beforeEach(() => clearEmulatorFirestore(PROJECT));
  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  test('due lots are closed and what is left of them debited; others untouched', async () => {
    await grantCredits(db, 'alice', 1000, { expiresAtMs: T0 - 1 }); // due
    await grantCredits(db, 'alice', 2000, { expiresAtMs: T0 }); // due exactly now
    await grantCredits(db, 'alice', 4000, { expiresAtMs: T0 + 1 }); // tomorrow's
    await grantCredits(db, 'alice', 8000, { expiresAtMs: null }); // never
    await grantBalance(db, 'alice', 500);

    const result = await expireCredits(deps, T0);
    assert.deepEqual(result, { wallets: 1, lots: 2, expired: 3000, failed: 0 });
    const wallet = (await read('wallets/alice'))!;
    assert.deepEqual([wallet.credits, wallet.balance], [12000, 500]);
    assert.deepEqual(
      (await lots('alice')).map((l) => [l.amount, l.remaining, l.open, l.expiredAmount ?? null]),
      [
        [1000, 0, false, 1000],
        [2000, 0, false, 2000],
        [4000, 4000, true, null],
        [8000, 8000, true, null],
      ],
    );
    const expiry = (await walletTxns(db, 'alice')).filter((t) => t.type === 'creditExpiry');
    assert.deepEqual(expiry.map((t) => [t.amount, t.bucket, t.creditsAfter, t.balanceAfter, t.title]), [
      [-3000, 'credits', 12000, 500, 'Credits expired'],
    ]);
    await assertWalletConsistent(db, 'alice');
  });

  test('idempotent: a second run (or a retry) expires nothing more', async () => {
    await grantCredits(db, 'alice', 1000, { expiresAtMs: T0 - DAY_MS });
    await expireCredits(deps, T0);
    assert.deepEqual(await expireCredits(deps, T0), { wallets: 0, lots: 0, expired: 0, failed: 0 });
    assert.deepEqual(await expireCredits(deps, T0 + DAY_MS), { wallets: 0, lots: 0, expired: 0, failed: 0 });
    assert.equal((await read('wallets/alice'))?.credits, 0);
    assert.equal((await walletTxns(db, 'alice')).filter((t) => t.type === 'creditExpiry').length, 1);
    await assertWalletConsistent(db, 'alice');
  });

  test('a partly spent lot loses only its remaining credits; a spent lot nothing', async () => {
    await grantCredits(db, 'alice', 3000, { expiresAtMs: T0 - 1 });
    await grantCredits(db, 'alice', 5000, { expiresAtMs: T0 - 1 });
    await spendCredits('alice', 4000); // FIFO: the 3,000 lot entirely, 1,000 of the 5,000 one
    const result = await expireCredits(deps, T0);
    assert.deepEqual(result, { wallets: 1, lots: 1, expired: 4000, failed: 0 });
    assert.equal((await read('wallets/alice'))?.credits, 0);
    await assertWalletConsistent(db, 'alice');
  });

  test('never below zero: credits taken elsewhere without a lot are not debited twice', async () => {
    await grantCredits(db, 'alice', 5000, { expiresAtMs: T0 - 1 });
    // Another writer debited credits without touching the lot.
    await db.doc('wallets/alice').update({ credits: 2000 });
    const result = await expireCredits(deps, T0);
    assert.deepEqual(result, { wallets: 1, lots: 1, expired: 2000, failed: 0 });
    assert.equal((await read('wallets/alice'))?.credits, 0);
    await db.doc('wallets/bob').set({ balance: 0, credits: 0 });
    await grantCredits(db, 'bob', 1, { expiresAtMs: T0 - 1 });
    await db.doc('wallets/bob').update({ credits: 0 });
    assert.deepEqual(await expireCredits(deps, T0), { wallets: 0, lots: 1, expired: 0, failed: 0 });
    assert.equal((await walletTxns(db, 'bob')).filter((t) => t.type === 'creditExpiry').length, 0);
  });

  test('many wallets, several pages', async () => {
    const uids = Array.from({ length: 7 }, (_, i) => `u${i}`);
    for (const uid of uids) {
      await grantCredits(db, uid, 100, { expiresAtMs: T0 - 2 });
      await grantCredits(db, uid, 200, { expiresAtMs: T0 - 1 });
    }
    // A collection that only looks like a wallet's lots is ignored.
    await db.doc('other/x/credit_lots/l1').set({ open: true, remaining: 5, expiresAt: Timestamp.fromMillis(T0 - 1) });
    const result = await expireCredits(deps, T0, { pageSize: 3 });
    assert.deepEqual(result, { wallets: 7, lots: 14, expired: 2100, failed: 0 });
    for (const uid of uids) assert.equal((await read(`wallets/${uid}`))?.credits, 0);
    assert.equal((await read('other/x/credit_lots/l1'))?.open, true);
  });
});
