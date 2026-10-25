/**
 * `setUserBlocked` (SRS §9 Users "block"): a super or ops admin blocks or
 * unblocks a customer.
 *
 * Block: `users/{uid}.isBlocked = true` (placeOrder refuses the account, the
 * referral functions stop rewarding it) + the `admin_audit_log` entry
 * `user.block` in one transaction, then the Auth account is disabled (verifyOtp,
 * Google and Apple sign-in refuse it) and its refresh tokens are revoked (other
 * devices are signed out within the hour). Unblock: the reverse (`user.unblock`,
 * Auth account enabled again).
 *
 * Firestore first, Auth second: a repeat call always finishes a change that
 * failed half-way (the audit entry is only written when `isBlocked` changes).
 * An admin account cannot be blocked (revoke its admin access first), and nobody
 * blocks themselves.
 */
import type { Auth, UserRecord } from 'firebase-admin/auth';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { authErrorCode } from '../auth/authUsers';
import { FirestorePaths as P } from '../shared/paths';
import { graphemeLength } from '../shared/text';
import { auditLogEntry, isUid, requireAdminRole } from './adminRoles';
import { ADMIN_CLAIM, type AdminCaller, type AdminRole } from './setAdminClaim';

/** `UsersAccess.canBlock` in the dashboard. */
export const BLOCK_USER_ROLES: readonly AdminRole[] = ['super', 'ops'];
export const BLOCK_REASON_MAX = 300;
export const AUDIT_ACTION_BLOCK = 'user.block';
export const AUDIT_ACTION_UNBLOCK = 'user.unblock';
export const BLOCK_ADMIN_MESSAGE = 'This account has admin access. Revoke it first (Admins), then block the account.';
export const BLOCK_SELF_MESSAGE = 'You cannot block your own account.';

export interface SetUserBlockedRequest {
  uid: string;
  blocked: boolean;
  reason: string | null;
}

export interface SetUserBlockedDeps {
  db: Firestore;
  auth: Auth;
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

export function parseSetUserBlockedData(data: unknown): SetUserBlockedRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) throw bad('Expected { uid, blocked, reason? }.');
  const d = data as Record<string, unknown>;
  if (!isUid(d.uid)) throw bad('`uid` is missing or invalid.');
  if (typeof d.blocked !== 'boolean') throw bad('`blocked` must be true or false.');
  let reason: string | null = null;
  if (d.reason !== undefined && d.reason !== null) {
    if (typeof d.reason !== 'string') throw bad('`reason` must be a string.');
    const trimmed = d.reason.trim();
    if (graphemeLength(trimmed) > BLOCK_REASON_MAX) throw bad(`\`reason\` is longer than ${BLOCK_REASON_MAX} characters.`);
    reason = trimmed.length > 0 ? trimmed : null;
  }
  return { uid: d.uid, blocked: d.blocked, reason };
}

async function authUserOrNull(auth: Auth, uid: string): Promise<UserRecord | null> {
  try {
    return await auth.getUser(uid);
  } catch (e) {
    if (authErrorCode(e) === 'auth/user-not-found') return null;
    throw e;
  }
}

export async function setUserBlockedCore(
  deps: SetUserBlockedDeps,
  data: unknown,
  caller: AdminCaller,
): Promise<{ uid: string; blocked: boolean }> {
  const { db, auth } = deps;
  const admin = await requireAdminRole(db, caller, BLOCK_USER_ROLES, 'Only super and ops admins can block accounts.');
  const request = parseSetUserBlockedData(data);
  if (request.blocked && request.uid === admin.uid) throw new HttpsError('failed-precondition', BLOCK_SELF_MESSAGE);

  const authUser = await authUserOrNull(auth, request.uid);
  if (request.blocked && authUser?.customClaims?.[ADMIN_CLAIM] === true) {
    throw new HttpsError('failed-precondition', BLOCK_ADMIN_MESSAGE);
  }

  const userRef = db.collection(P.users).doc(request.uid);
  await db.runTransaction(async (tx) => {
    // ── Reads ──
    const [userSnap, adminSnap] = await tx.getAll(userRef, db.collection(P.admins).doc(request.uid));
    if (!userSnap.exists) throw new HttpsError('not-found', 'No user with that uid.');
    if (request.blocked && adminSnap.exists) throw new HttpsError('failed-precondition', BLOCK_ADMIN_MESSAGE);
    const wasBlocked = userSnap.get('isBlocked') === true;
    if (wasBlocked === request.blocked) return;

    // ── Writes ──
    tx.update(userRef, { isBlocked: request.blocked, updatedAt: FieldValue.serverTimestamp() });
    tx.create(
      db.collection(P.adminAuditLog).doc(),
      auditLogEntry(
        admin.uid,
        request.blocked ? AUDIT_ACTION_BLOCK : AUDIT_ACTION_UNBLOCK,
        `${P.users}/${request.uid}`,
        { isBlocked: wasBlocked, authDisabled: authUser?.disabled ?? null },
        { isBlocked: request.blocked, authDisabled: authUser === null ? null : request.blocked, reason: request.reason },
      ),
    );
  });

  // The Auth account follows (an account deleted from Auth has nothing to disable).
  if (authUser !== null) {
    if (authUser.disabled !== request.blocked) await auth.updateUser(request.uid, { disabled: request.blocked });
    if (request.blocked) await auth.revokeRefreshTokens(request.uid);
  }
  return { uid: request.uid, blocked: request.blocked };
}
