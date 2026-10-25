/**
 * Secret Santa (SRS §5.16, §6.14): `joinSecretSanta` and `drawSecretSanta`.
 *
 * The organiser creates `secret_santa_groups/{id}` and their own
 * `members/{uid}` from the app (one batch, checked by the rules); everyone else
 * joins with the 8-character invite code through `joinSecretSanta` (they cannot
 * read the group before they are a member). `drawSecretSanta` writes one
 * `assignments/{giverUid}` per member — readable only by that giver and admins,
 * so each member sees only their own assignee — and marks the group `drawn`.
 *
 * Errors follow `SecretSantaFailure.from` (secret_santa_repository.dart):
 * `not-found` with a message (bad code / group), `permission-denied` (not the
 * organiser), `failed-precondition` `{ reason: drawn | too_few | full | impossible }`.
 */
import { FieldValue, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { notifyUser } from '../notifications/notifyUser';
import type { PushMessaging } from '../notifications/push';
import { epochMillis, string, stringList, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { assertUnderRateLimit, recordRateLimitHit, type RateLimit } from '../shared/rateLimit';
import { graphemeLength } from '../shared/text';
import { drawAssignments, isValidDraw, type RandomSource } from './draw';
import { secretSantaDrawNotification } from './secretSantaMessages';

/** `SecretSantaGroup.minMembers` / `maxMembers`. */
export const MIN_MEMBERS = 3;
export const MAX_MEMBERS = 50;
/** `SecretSantaMember.maxWishlistNote`. */
export const MAX_WISHLIST_NOTE = 300;
export const MAX_MEMBER_NAME = 60;
/** `SecretSantaRepository._alphabet`: no 0 / O / 1 / I. */
export const INVITE_CODE_PATTERN = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/;

export type SecretSantaFailureReason = 'drawn' | 'too_few' | 'full' | 'impossible';

const MESSAGES: Record<SecretSantaFailureReason, string> = {
  drawn: 'Names have already been drawn in this group.',
  too_few: `At least ${MIN_MEMBERS} members are needed to draw names.`,
  full: `This group already has ${MAX_MEMBERS} members.`,
  impossible: 'The exclusions leave no valid draw. Remove some exclusions and try again.',
};

export function secretSantaFailure(reason: SecretSantaFailureReason): HttpsError {
  return new HttpsError('failed-precondition', MESSAGES[reason], { reason });
}

export interface SecretSantaDeps {
  db: Firestore;
  messaging: PushMessaging | null;
  random?: RandomSource;
  logger?: Pick<typeof functionsLogger, 'warn'>;
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

function isDocId(v: unknown): v is string {
  return typeof v === 'string' && v.length > 0 && v.length <= 128 && !v.includes('/') && v !== '.' && v !== '..';
}

// ─────────────────────────────────────────────────────────────────────────────
// joinSecretSanta
// ─────────────────────────────────────────────────────────────────────────────

export interface JoinRequest {
  inviteCode: string;
  name: string;
  wishlistNote: string | null;
}

/** `SecretSantaRepository.join` sends the code trimmed + upper-cased. */
export function normalizeInviteCode(code: string): string {
  return code.replace(/\s+/g, '').toUpperCase();
}

export function parseJoinData(data: unknown): JoinRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) throw bad('Expected { inviteCode, name, wishlistNote? }.');
  const d = data as Record<string, unknown>;
  if (typeof d.inviteCode !== 'string' || d.inviteCode.trim().length === 0) throw bad('`inviteCode` is missing.');
  if (typeof d.name !== 'string') throw bad('`name` is missing.');
  const name = d.name.trim();
  if (name.length === 0 || graphemeLength(name) > MAX_MEMBER_NAME) throw bad(`\`name\` must be 1–${MAX_MEMBER_NAME} characters.`);
  let wishlistNote: string | null = null;
  if (d.wishlistNote !== undefined && d.wishlistNote !== null) {
    if (typeof d.wishlistNote !== 'string') throw bad('`wishlistNote` must be a string.');
    const note = d.wishlistNote.trim();
    if (graphemeLength(note) > MAX_WISHLIST_NOTE) throw bad(`\`wishlistNote\` is longer than ${MAX_WISHLIST_NOTE} characters.`);
    wishlistNote = note.length > 0 ? note : null;
  }
  return { inviteCode: normalizeInviteCode(d.inviteCode), name, wishlistNote };
}

const NO_GROUP = 'No Secret Santa group matches this invite code.';

/** Wrong invite codes per user (rolling hour): guessing codes is refused after this many. */
export const JOIN_WRONG_CODE_LIMIT: RateLimit = { limit: 10, windowMs: 60 * 60 * 1000 };
export const JOIN_TOO_MANY_MESSAGE = 'Too many wrong invite codes. Please try again in an hour.';
export const joinRateLimitKey = (uid: string) => `rl:santaJoin:${uid}`;

export async function joinSecretSantaCore(
  db: Firestore,
  data: unknown,
  uid: string | undefined,
  options: { now?: () => number } = {},
): Promise<{ groupId: string }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to join a Secret Santa group.');
  const request = parseJoinData(data);
  const nowMs = (options.now ?? Date.now)();
  const limitKey = joinRateLimitKey(uid);
  await assertUnderRateLimit(db, limitKey, JOIN_WRONG_CODE_LIMIT, nowMs, JOIN_TOO_MANY_MESSAGE);
  const wrongCode = async (): Promise<never> => {
    await recordRateLimitHit(db, limitKey, JOIN_WRONG_CODE_LIMIT, nowMs);
    throw new HttpsError('not-found', NO_GROUP);
  };
  if (!INVITE_CODE_PATTERN.test(request.inviteCode)) return wrongCode();

  const groups = db.collection(P.secretSantaGroups);
  const userRef = db.collection(P.users).doc(uid);
  let unknownCode = false;
  try {
    return await db.runTransaction(async (tx) => {
      unknownCode = false;
      const matches = await tx.get(groups.where('inviteCode', '==', request.inviteCode).limit(5));
      if (matches.empty) {
        unknownCode = true;
        throw new HttpsError('not-found', NO_GROUP);
      }
      // Already a member (of any group with this code): the same answer again.
      const mine = matches.docs.find((d) => stringList(d.get('memberUids')).includes(uid));
      if (mine !== undefined) return { groupId: mine.id };
      // Codes are random but the app picks them, so two groups could share one (or a
      // copy-cat group could be created with a code someone saw): the OLDEST open
      // group with the code wins, never whichever the query happens to return first.
      const byAge = [...matches.docs].sort(
        (a, b) => (epochMillis(a.get('createdAt')) ?? 0) - (epochMillis(b.get('createdAt')) ?? 0) || (a.id < b.id ? -1 : 1),
      );
      const group = byAge.find((d) => d.get('status') === 'open') ?? byAge[0];
      if (group.get('status') !== 'open') throw secretSantaFailure('drawn');
      if (stringList(group.get('memberUids')).length >= MAX_MEMBERS) throw secretSantaFailure('full');
      const user = (await tx.get(userRef)).data();
      if (user?.isDeleted === true || user?.isBlocked === true) {
        throw new HttpsError('permission-denied', 'This account cannot join groups.');
      }

      const ts = FieldValue.serverTimestamp();
      tx.create(group.ref.collection(P.members).doc(uid), {
        name: request.name,
        phone: stringOrNull(user?.phone),
        joinedAt: ts,
        wishlistNote: request.wishlistNote,
      });
      tx.update(group.ref, { memberUids: FieldValue.arrayUnion(uid), updatedAt: ts });
      return { groupId: group.id };
    });
  } catch (e) {
    if (unknownCode) return wrongCode();
    throw e;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// drawSecretSanta
// ─────────────────────────────────────────────────────────────────────────────

interface Member {
  uid: string;
  name: string;
  wishlistNote: string | null;
  exclusions: string[];
}

export function parseDrawData(data: unknown): { groupId: string } {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) throw bad('Expected { groupId }.');
  const { groupId } = data as Record<string, unknown>;
  if (!isDocId(groupId)) throw bad('`groupId` is missing or invalid.');
  return { groupId };
}

export async function drawSecretSantaCore(
  deps: SecretSantaDeps,
  data: unknown,
  uid: string | undefined,
): Promise<{ ok: true }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to draw names.');
  const { groupId } = parseDrawData(data);
  const { db } = deps;
  const groupRef = db.collection(P.secretSantaGroups).doc(groupId);

  const outcome = await db.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    const group = groupSnap.data();
    if (group === undefined) throw new HttpsError('not-found', 'Secret Santa group not found.');
    if (group.organiserUid !== uid) throw new HttpsError('permission-denied', 'Only the organiser can draw names.');
    if (group.status !== 'open') return { drawn: false as const, group };

    const memberUids = new Set(stringList(group.memberUids));
    const memberSnaps = await tx.get(groupRef.collection(P.members).limit(MAX_MEMBERS + 1));
    const members: Member[] = memberSnaps.docs
      .filter((d) => memberUids.has(d.id))
      .map((d) => ({
        uid: d.id,
        name: string(d.get('name')),
        wishlistNote: stringOrNull(d.get('wishlistNote')),
        exclusions: stringList(d.get('exclusions')),
      }));
    if (members.length < MIN_MEMBERS) throw secretSantaFailure('too_few');
    if (members.length > MAX_MEMBERS) throw secretSantaFailure('full');

    const uids = members.map((m) => m.uid);
    const exclusions = Object.fromEntries(members.map((m) => [m.uid, m.exclusions]));
    const assignments = drawAssignments(uids, exclusions, deps.random ?? Math.random);
    if (assignments === null) throw secretSantaFailure('impossible');
    if (!isValidDraw(uids, exclusions, assignments)) throw new Error('drawSecretSanta: invalid draw');

    const byUid = new Map(members.map((m) => [m.uid, m]));
    const ts = FieldValue.serverTimestamp();
    for (const [giver, receiver] of assignments) {
      const assignee = byUid.get(receiver)!;
      tx.set(groupRef.collection(P.assignments).doc(giver), {
        assigneeUid: receiver,
        assigneeName: assignee.name,
        assigneeWishlistNote: assignee.wishlistNote,
        drawnAt: ts,
      });
    }
    tx.update(groupRef, { status: 'drawn', drawnAt: ts, updatedAt: ts });
    return { drawn: true as const, group };
  });

  // Notifications: once per member (fixed ids). The organiser calling again after
  // a crash between the commit and the pushes sends whatever is still missing.
  await notifyMembers(deps, groupId, outcome.group);
  if (!outcome.drawn) throw secretSantaFailure('drawn');
  return { ok: true };
}

async function notifyMembers(deps: SecretSantaDeps, groupId: string, group: DocumentData): Promise<void> {
  if (group.status !== 'open' && group.status !== 'drawn') return;
  const log = deps.logger ?? functionsLogger;
  const notification = secretSantaDrawNotification(groupId, string(group.name));
  await Promise.all(
    stringList(group.memberUids).map((member) =>
      notifyUser({ db: deps.db, messaging: deps.messaging, logger: log }, member, notification, {
        notificationId: `secretSanta-${groupId}-${member}`,
      }).catch((e: unknown) =>
        log.warn('drawSecretSanta: notification failed', { groupId, uid: member, error: e instanceof Error ? e.message : String(e) }),
      ),
    ),
  );
}
