import assert from 'node:assert/strict';
import { after, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { runOnce } from '../src/shared/idempotency';

/**
 * Needs the Firestore emulator; skipped otherwise. Run with:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npm test
 */
const emulator = process.env.FIRESTORE_EMULATOR_HOST;

describe('runOnce (Firestore emulator)', { skip: emulator ? false : 'FIRESTORE_EMULATOR_HOST not set' }, () => {
  const app = initializeApp({ projectId: 'goldengift-iq' }, 'idempotency-test');
  const db = getFirestore(app);
  const runId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const counter = db.collection('_test_counters').doc(runId);
  const keys: string[] = [];

  after(async () => {
    await Promise.all(keys.map((k) => db.collection('function_runs').doc(k).delete()));
    await counter.delete();
    await deleteApp(app);
  });

  test('runs once, then skips', async () => {
    const key = `test:sequential:${runId}`;
    keys.push(key);
    let calls = 0;
    const fn = (tx: FirebaseFirestore.Transaction) => {
      calls++;
      tx.set(counter, { n: FieldValue.increment(1) }, { merge: true });
    };
    assert.equal(await runOnce(db, key, fn), true);
    assert.equal(await runOnce(db, key, fn), false);
    assert.equal(calls, 1);
    const marker = await db.collection('function_runs').doc(key).get();
    assert.equal(marker.get('key'), key);
    assert.ok(marker.get('at'));
  });

  test('concurrent replays apply the side effect exactly once', async () => {
    const key = `test:concurrent:${runId}`;
    keys.push(key);
    const before = ((await counter.get()).get('n') as number | undefined) ?? 0;
    const results = await Promise.all(
      Array.from({ length: 5 }, () =>
        runOnce(db, key, (tx) => {
          tx.set(counter, { n: FieldValue.increment(1) }, { merge: true });
        }),
      ),
    );
    assert.equal(results.filter(Boolean).length, 1);
    assert.equal((await counter.get()).get('n'), before + 1);
  });

  test('rejects keys that are not valid document ids', async () => {
    await assert.rejects(runOnce(db, 'a/b', () => {}), /invalid idempotency key/);
    await assert.rejects(runOnce(db, '', () => {}), /invalid idempotency key/);
  });
});
