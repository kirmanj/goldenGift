/**
 * Secret Santa (SRS §5.16): the draw as a pure function (never a self-match,
 * exclusions honoured, `impossible` exact), then joinSecretSanta /
 * drawSecretSanta against the Firestore emulator (own demo- project; skipped
 * without it, see ./emulators.ts).
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { drawAssignments, isValidDraw, seededRandom, shuffled } from '../src/secretSanta/draw';
import {
  JOIN_WRONG_CODE_LIMIT,
  drawSecretSantaCore,
  joinSecretSantaCore,
  parseJoinData,
  type SecretSantaDeps,
} from '../src/secretSanta/secretSanta';
import { syncWishNoteToAssignment } from '../src/secretSanta/wishNoteSync';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';

const members = (n: number) => Array.from({ length: n }, (_, i) => `m${i + 1}`);

describe('drawAssignments (pure)', () => {
  test('never self-matches, everyone gives and receives once — 3 to 50 members × 200 seeds', () => {
    for (let n = 3; n <= 50; n++) {
      const uids = members(n);
      for (let seed = 1; seed <= 200; seed++) {
        const draw = drawAssignments(uids, {}, seededRandom(seed * 7919 + n));
        assert.ok(draw, `n=${n} seed=${seed}`);
        assert.ok(isValidDraw(uids, {}, draw), `n=${n} seed=${seed}`);
        for (const [giver, receiver] of draw) assert.notEqual(giver, receiver);
      }
    }
  });

  test('is random: different seeds give different draws', () => {
    const uids = members(8);
    const seen = new Set<string>();
    for (let seed = 1; seed <= 100; seed++) {
      const d = drawAssignments(uids, {}, seededRandom(seed))!;
      seen.add(uids.map((u) => d.get(u)).join(','));
    }
    assert.ok(seen.size > 50, `only ${seen.size} distinct draws`);
  });

  test('honours exclusions (asymmetric: the giver must not draw them)', () => {
    const uids = members(6);
    const exclusions = { m1: ['m2', 'm3'], m2: ['m1'], m4: ['m5', 'm6', 'm1'], unknown: ['m1'] };
    for (let seed = 1; seed <= 300; seed++) {
      const d = drawAssignments(uids, exclusions, seededRandom(seed))!;
      assert.ok(isValidDraw(uids, exclusions, d));
      assert.ok(!['m2', 'm3'].includes(d.get('m1')!));
      assert.notEqual(d.get('m2'), 'm1');
      assert.ok(!['m5', 'm6', 'm1'].includes(d.get('m4')!));
    }
  });

  test('finds the only valid draw when the exclusions leave just one', () => {
    // m1 → m2 → m3 → m1 is the only allowed cycle.
    const uids = members(3);
    const exclusions = { m1: ['m3'], m2: ['m1'], m3: ['m2'] };
    for (let seed = 1; seed <= 50; seed++) {
      const d = drawAssignments(uids, exclusions, seededRandom(seed))!;
      assert.deepEqual([d.get('m1'), d.get('m2'), d.get('m3')], ['m2', 'm3', 'm1']);
    }
  });

  test('impossible when the exclusions leave no valid draw', () => {
    // Nobody may draw m3.
    assert.equal(drawAssignments(members(3), { m1: ['m3'], m2: ['m3'] }), null);
    // m1 excludes everyone.
    assert.equal(drawAssignments(members(4), { m1: ['m2', 'm3', 'm4'] }), null);
    // Two members may only draw each other… and m3, m4 both may only draw m1.
    assert.equal(drawAssignments(members(4), { m3: ['m2', 'm4'], m4: ['m2', 'm3'] }), null);
    assert.equal(drawAssignments(['m1'], {}), null);
  });

  test('isValidDraw rejects self-matches, doubles and exclusions', () => {
    const uids = members(3);
    assert.equal(isValidDraw(uids, {}, new Map([['m1', 'm1'], ['m2', 'm3'], ['m3', 'm2']])), false);
    assert.equal(isValidDraw(uids, {}, new Map([['m1', 'm2'], ['m2', 'm1'], ['m3', 'm1']])), false);
    assert.equal(isValidDraw(uids, { m1: ['m2'] }, new Map([['m1', 'm2'], ['m2', 'm3'], ['m3', 'm1']])), false);
    assert.equal(isValidDraw(uids, {}, new Map([['m1', 'm2'], ['m2', 'm3'], ['m3', 'm1']])), true);
  });

  test('shuffled keeps every element', () => {
    assert.deepEqual(shuffled([1, 2, 3, 4, 5], seededRandom(3)).sort(), [1, 2, 3, 4, 5]);
  });
});

describe('parseJoinData', () => {
  test('normalises the code, trims, drops an empty note', () => {
    assert.deepEqual(parseJoinData({ inviteCode: ' abcd 2345 ', name: ' Sara ', wishlistNote: '  ' }), {
      inviteCode: 'ABCD2345',
      name: 'Sara',
      wishlistNote: null,
    });
  });
  test('rejects bad input', () => {
    for (const data of [null, {}, { inviteCode: 'ABCD2345' }, { inviteCode: 'ABCD2345', name: '' }, { inviteCode: '', name: 'A' }, { inviteCode: 'ABCD2345', name: 'A', wishlistNote: 'x'.repeat(301) }]) {
      assert.throws(() => parseJoinData(data), (e: unknown) => e instanceof HttpsError && e.code === 'invalid-argument', JSON.stringify(data));
    }
  });
});

const PROJECT = 'demo-goldengift-secret-santa';

async function rejectsWith(promise: Promise<unknown>, code: string, reason?: string, message?: RegExp): Promise<void> {
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, `expected HttpsError, got ${String(e)}`);
    assert.equal(e.code, code, e.message);
    if (reason !== undefined) assert.equal((e.details as { reason?: string } | undefined)?.reason, reason);
    if (message !== undefined) assert.match(e.message, message);
    return true;
  });
}

describe('joinSecretSanta / drawSecretSanta (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `secret-santa-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  const deps: SecretSantaDeps = { db, messaging: fcm, random: seededRandom(42), logger: { warn: () => undefined } };
  const read = async (path: string) => (await db.doc(path).get()).data();

  /** A group as SecretSantaRepository.create writes it, with the organiser as first member. */
  async function seedGroup(id: string, over: DocumentData = {}, memberNames: Record<string, string> = { org: 'Organiser' }): Promise<void> {
    const uids = Object.keys(memberNames);
    await db.doc(`secret_santa_groups/${id}`).set({
      name: 'Family 2026',
      type: 'family',
      budget: 25000,
      exchangeDate: Timestamp.fromMillis(Date.UTC(2026, 11, 24)),
      organiserUid: 'org',
      status: 'open',
      inviteCode: 'ABCD2345',
      memberUids: uids,
      createdAt: Timestamp.now(),
      ...over,
    });
    for (const uid of uids) {
      await db.doc(`secret_santa_groups/${id}/members/${uid}`).set({ name: memberNames[uid], phone: null, joinedAt: Timestamp.now() });
    }
  }

  async function seedUser(uid: string, over: DocumentData = {}): Promise<void> {
    await db.doc(`users/${uid}`).set({ name: uid, phone: '7501234567', locale: 'en', fcmTokens: [`tok-${uid}`], notificationsEnabled: true, ...over });
  }

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    fcm.reset();
    for (const uid of ['org', 'ali', 'sara', 'dana', 'blocked']) await seedUser(uid, uid === 'blocked' ? { isBlocked: true } : {});
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  test('join: adds the member doc and memberUids; joining again is the same answer', async () => {
    await seedGroup('g1');
    assert.deepEqual(await joinSecretSantaCore(db, { inviteCode: 'abcd2345', name: ' Ali ', wishlistNote: 'Books please' }, 'ali'), { groupId: 'g1' });
    const member = await read('secret_santa_groups/g1/members/ali');
    assert.equal(member?.name, 'Ali');
    assert.equal(member?.phone, '7501234567');
    assert.equal(member?.wishlistNote, 'Books please');
    assert.ok(member?.joinedAt instanceof Timestamp);
    assert.deepEqual((await read('secret_santa_groups/g1'))?.memberUids, ['org', 'ali']);

    assert.deepEqual(await joinSecretSantaCore(db, { inviteCode: 'ABCD2345', name: 'Ali again' }, 'ali'), { groupId: 'g1' });
    assert.equal((await read('secret_santa_groups/g1/members/ali'))?.name, 'Ali');
    assert.deepEqual((await read('secret_santa_groups/g1'))?.memberUids, ['org', 'ali']);
  });

  test('join errors: unknown code (not-found WITH a message), drawn, full, blocked, signed out', async () => {
    await rejectsWith(joinSecretSantaCore(db, { inviteCode: 'ZZZZ9999', name: 'Ali' }, 'ali'), 'not-found', undefined, /invite code/);
    await rejectsWith(joinSecretSantaCore(db, { inviteCode: 'bad', name: 'Ali' }, 'ali'), 'not-found', undefined, /invite code/);
    await seedGroup('drawn', { status: 'drawn', inviteCode: 'DRAW2345' });
    await rejectsWith(joinSecretSantaCore(db, { inviteCode: 'DRAW2345', name: 'Ali' }, 'ali'), 'failed-precondition', 'drawn');
    await seedGroup('full', { inviteCode: 'FULL2345', memberUids: Array.from({ length: 50 }, (_, i) => `u${i}`) });
    await rejectsWith(joinSecretSantaCore(db, { inviteCode: 'FULL2345', name: 'Ali' }, 'ali'), 'failed-precondition', 'full');
    await seedGroup('g1');
    await rejectsWith(joinSecretSantaCore(db, { inviteCode: 'ABCD2345', name: 'B' }, 'blocked'), 'permission-denied');
    await rejectsWith(joinSecretSantaCore(db, { inviteCode: 'ABCD2345', name: 'B' }, undefined), 'unauthenticated');
  });

  test('draw: one private assignment per member, never self, group drawn, every member notified', async () => {
    await seedGroup('g1', {}, { org: 'Organiser', ali: 'Ali', sara: 'Sara', dana: 'Dana' });
    await db.doc('secret_santa_groups/g1/members/sara').update({ wishlistNote: 'Plants' });
    assert.deepEqual(await drawSecretSantaCore(deps, { groupId: 'g1' }, 'org'), { ok: true });

    const group = await read('secret_santa_groups/g1');
    assert.equal(group?.status, 'drawn');
    assert.ok(group?.drawnAt instanceof Timestamp);
    const snap = await db.collection('secret_santa_groups/g1/assignments').get();
    assert.deepEqual(snap.docs.map((d) => d.id).sort(), ['ali', 'dana', 'org', 'sara']);
    const pairs = new Map(snap.docs.map((d) => [d.id, d.get('assigneeUid') as string]));
    assert.ok(isValidDraw(['org', 'ali', 'sara', 'dana'], {}, pairs));
    const names: Record<string, string> = { org: 'Organiser', ali: 'Ali', sara: 'Sara', dana: 'Dana' };
    for (const d of snap.docs) {
      assert.equal(d.get('assigneeName'), names[d.get('assigneeUid') as string]);
      assert.equal(d.get('assigneeWishlistNote'), d.get('assigneeUid') === 'sara' ? 'Plants' : null);
      assert.ok(d.get('drawnAt') instanceof Timestamp);
    }
    // Member docs never carry the assignee (everyone can read them).
    for (const uid of Object.keys(names)) assert.equal((await read(`secret_santa_groups/g1/members/${uid}`))?.assigneeUid, undefined);

    const notes = await db.collection('notifications').where('type', '==', 'secretSantaDraw').get();
    assert.deepEqual(notes.docs.map((d) => d.get('userId')).sort(), ['ali', 'dana', 'org', 'sara']);
    const n = notes.docs[0].data();
    assert.equal(n.data.route, '/secret-santa/g1');
    assert.match(n.title, /names drawn/);
    assert.ok(n.titleAr.length > 0 && n.titleKu.length > 0 && n.bodyKu.length > 0);
    assert.equal(fcm.calls.length, 4);
  });

  test('draw again → drawn (assignments unchanged, no second notification)', async () => {
    await seedGroup('g1', {}, { org: 'O', ali: 'A', sara: 'S' });
    await drawSecretSantaCore(deps, { groupId: 'g1' }, 'org');
    const first = (await db.collection('secret_santa_groups/g1/assignments').get()).docs.map((d) => [d.id, d.get('assigneeUid')]);
    await rejectsWith(drawSecretSantaCore(deps, { groupId: 'g1' }, 'org'), 'failed-precondition', 'drawn');
    const second = (await db.collection('secret_santa_groups/g1/assignments').get()).docs.map((d) => [d.id, d.get('assigneeUid')]);
    assert.deepEqual(second, first);
    assert.equal((await db.collection('notifications').get()).size, 3);
    assert.equal(fcm.calls.length, 3);
  });

  test('draw honours exclusions; impossible exclusions change nothing', async () => {
    await seedGroup('g1', {}, { org: 'O', ali: 'A', sara: 'S' });
    await db.doc('secret_santa_groups/g1/members/org').update({ exclusions: ['sara'] });
    await drawSecretSantaCore(deps, { groupId: 'g1' }, 'org');
    assert.equal((await read('secret_santa_groups/g1/assignments/org'))?.assigneeUid, 'ali');

    await seedGroup('g2', { inviteCode: 'EFGH2345' }, { org: 'O', ali: 'A', sara: 'S' });
    await db.doc('secret_santa_groups/g2/members/org').update({ exclusions: ['sara'] });
    await db.doc('secret_santa_groups/g2/members/ali').update({ exclusions: ['sara'] });
    await rejectsWith(drawSecretSantaCore(deps, { groupId: 'g2' }, 'org'), 'failed-precondition', 'impossible');
    assert.equal((await read('secret_santa_groups/g2'))?.status, 'open');
    assert.equal((await db.collection('secret_santa_groups/g2/assignments').get()).size, 0);
  });

  test('draw errors: not the organiser, too few members, unknown group', async () => {
    await seedGroup('g1', {}, { org: 'O', ali: 'A' });
    await rejectsWith(drawSecretSantaCore(deps, { groupId: 'g1' }, 'ali'), 'permission-denied');
    await rejectsWith(drawSecretSantaCore(deps, { groupId: 'g1' }, 'org'), 'failed-precondition', 'too_few');
    await rejectsWith(drawSecretSantaCore(deps, { groupId: 'nope' }, 'org'), 'not-found', undefined, /not found/);
    await rejectsWith(drawSecretSantaCore(deps, { groupId: 'a/b' }, 'org'), 'invalid-argument');
    await rejectsWith(drawSecretSantaCore(deps, { groupId: 'g1' }, undefined), 'unauthenticated');
  });

  // ── Phase 10 ──

  test('join: 10 wrong invite codes per user per hour, then resource-exhausted (even for a right code)', async () => {
    await seedGroup('g1');
    let clock = Date.UTC(2026, 9, 21, 9, 0);
    const join = (code: string, uid = 'ali') => joinSecretSantaCore(db, { inviteCode: code, name: 'Ali' }, uid, { now: () => clock });
    for (let i = 0; i < JOIN_WRONG_CODE_LIMIT.limit; i++) {
      await rejectsWith(join(i % 2 === 0 ? 'ZZZZ9999' : 'not-a-code'), 'not-found', undefined, /invite code/);
    }
    await rejectsWith(join('ABCD2345'), 'resource-exhausted', 'rate_limited');
    // Another user is unaffected; right codes never count; the window rolls.
    assert.deepEqual(await join('ABCD2345', 'sara'), { groupId: 'g1' });
    assert.deepEqual(await join('ABCD2345', 'sara'), { groupId: 'g1' });
    clock += JOIN_WRONG_CODE_LIMIT.windowMs + 1;
    assert.deepEqual(await join('ABCD2345'), { groupId: 'g1' });
  });

  test('join: two open groups with one code → the OLDEST wins (a copy-cat group cannot capture joiners)', async () => {
    await seedGroup('zz-original', { createdAt: Timestamp.fromMillis(Date.UTC(2026, 9, 1)) });
    await seedGroup('aa-copycat', { organiserUid: 'dana', createdAt: Timestamp.fromMillis(Date.UTC(2026, 9, 20)) }, { dana: 'Dana' });
    assert.deepEqual(await joinSecretSantaCore(db, { inviteCode: 'ABCD2345', name: 'Ali' }, 'ali'), { groupId: 'zz-original' });
  });

  test('a wish note edited after the draw reaches the giver who drew that member — only that assignment', async () => {
    await seedGroup('g1', {}, { org: 'Organiser', ali: 'Ali', sara: 'Sara' });
    await drawSecretSantaCore(deps, { groupId: 'g1' }, 'org');
    const giverOf = async (uid: string) =>
      (await db.collection('secret_santa_groups/g1/assignments').where('assigneeUid', '==', uid).get()).docs[0];
    const giver = (await giverOf('sara')).id;

    const before = (await read('secret_santa_groups/g1/members/sara'))!;
    await db.doc('secret_santa_groups/g1/members/sara').update({ wishlistNote: 'Plants, not books' });
    const after = (await read('secret_santa_groups/g1/members/sara'))!;
    assert.deepEqual(await syncWishNoteToAssignment(db, { groupId: 'g1', memberUid: 'sara', before, after }), { synced: true, giverUid: giver });
    assert.equal((await read(`secret_santa_groups/g1/assignments/${giver}`))?.assigneeWishlistNote, 'Plants, not books');
    for (const d of (await db.collection('secret_santa_groups/g1/assignments').get()).docs) {
      if (d.id !== giver) assert.equal(d.get('assigneeWishlistNote'), null, `${d.id} untouched`);
    }

    // Replays and late events change nothing (the CURRENT note is what is copied).
    assert.deepEqual(await syncWishNoteToAssignment(db, { groupId: 'g1', memberUid: 'sara', before, after }), { synced: false, reason: 'upToDate' });
    await db.doc('secret_santa_groups/g1/members/sara').update({ wishlistNote: null });
    assert.deepEqual(await syncWishNoteToAssignment(db, { groupId: 'g1', memberUid: 'sara', before, after }), { synced: true, giverUid: giver });
    assert.equal((await read(`secret_santa_groups/g1/assignments/${giver}`))?.assigneeWishlistNote, null);

    // Unchanged notes and other fields are ignored.
    assert.deepEqual(await syncWishNoteToAssignment(db, { groupId: 'g1', memberUid: 'sara', before: after, after: { ...after, name: 'S' } }), {
      synced: false,
      reason: 'unchanged',
    });
  });

  test('before the draw there is no assignment to update (the draw copies the note itself)', async () => {
    await seedGroup('g1', {}, { org: 'Organiser', ali: 'Ali', sara: 'Sara' });
    const before = (await read('secret_santa_groups/g1/members/ali'))!;
    await db.doc('secret_santa_groups/g1/members/ali').update({ wishlistNote: 'Tea' });
    const after = (await read('secret_santa_groups/g1/members/ali'))!;
    assert.deepEqual(await syncWishNoteToAssignment(db, { groupId: 'g1', memberUid: 'ali', before, after }), { synced: false, reason: 'notDrawn' });
    await drawSecretSantaCore(deps, { groupId: 'g1' }, 'org');
    const giver = (await db.collection('secret_santa_groups/g1/assignments').where('assigneeUid', '==', 'ali').get()).docs[0];
    assert.equal(giver.get('assigneeWishlistNote'), 'Tea');
    assert.deepEqual(await syncWishNoteToAssignment(db, { groupId: 'missing', memberUid: 'ali', before, after }), { synced: false, reason: 'missing' });
  });
});
