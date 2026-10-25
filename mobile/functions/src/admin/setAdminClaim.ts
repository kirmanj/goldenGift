/**
 * Admin access (SRS §6.14, §7 `setAdminClaim`, §9): who may use the dashboard.
 *
 * Two halves, both required:
 *  - the `admin: true` custom claim — what the security rules check (`isAdmin()`);
 *  - `admins/{uid}` = `{ name, email, role, permissions[], createdAt, updatedAt }` —
 *    who the admin is and what they may do in the dashboard.
 *
 * Order of writes, chosen so that a failure half-way never grants more than intended
 * and a repeat call always completes the change:
 *  - grant:  doc (+ audit) first, claim second. A doc without the claim opens nothing
 *    (the rules only trust the claim; the dashboard needs both).
 *  - revoke: doc (+ audit) first, claim second. Without the doc the dashboard already
 *    refuses the account; the repeat call strips a claim that was left behind.
 *
 * The checks that protect the platform from locking itself out — never revoke
 * yourself, never leave zero super admins — run inside the same transaction as the
 * doc write, so two super admins revoking each other at the same moment cannot both
 * succeed.
 *
 * A changed claim reaches the person's ID token on its next refresh (at most an hour,
 * immediately after signing out and in again). The dashboard additionally requires the
 * `admins/{uid}` doc, which changes at once.
 */
import type { Auth, UserRecord } from 'firebase-admin/auth';
import { FieldValue, type DocumentData, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { authErrorCode } from '../auth/authUsers';
import { stringList, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';

/** `admins/{uid}.role` (SRS §6.14). Only `super` may call `setAdminClaim`. */
export const ADMIN_ROLES = ['super', 'ops', 'content', 'finance'] as const;
export type AdminRole = (typeof ADMIN_ROLES)[number];
export const SUPER_ADMIN_ROLE = 'super' satisfies AdminRole;
/** Role of a NEW admin when the grant names none: never `super` by accident. */
export const DEFAULT_ADMIN_ROLE = 'ops' satisfies AdminRole;

/** The custom claim the security rules check. */
export const ADMIN_CLAIM = 'admin';

/** `admin_audit_log.action` values written here. */
export const AUDIT_ACTION_GRANT = 'admin.grant';
export const AUDIT_ACTION_REVOKE = 'admin.revoke';

export const MAX_ADMIN_NAME_LENGTH = 100;

export const SUPER_ONLY_MESSAGE = 'Only a super admin can grant or revoke admin access.';
export const SELF_REVOKE_MESSAGE = 'You cannot revoke your own admin access. Ask another super admin.';
export const LAST_SUPER_MESSAGE =
  'This is the last super admin. Make another account super admin first.';

export const isAdminRole = (v: unknown): v is AdminRole =>
  typeof v === 'string' && (ADMIN_ROLES as readonly string[]).includes(v);

export interface AdminAccessDeps {
  db: Firestore;
  auth: Auth;
}

/** The caller of `setAdminClaim`. */
export interface AdminCaller {
  /** `request.auth?.uid` */
  uid?: string;
  /** `request.auth?.token` — the decoded ID token, custom claims included. */
  claims?: Readonly<Record<string, unknown>>;
}

/** Validated `setAdminClaim` data. Exactly one of `uid` / `email`. */
export interface SetAdminClaimRequest {
  uid?: string;
  email?: string;
  grant: boolean;
  role?: AdminRole;
  name?: string;
}

/** `admins/{uid}` without its timestamps. */
export interface AdminProfile {
  name: string;
  email: string | null;
  role: AdminRole;
  permissions: string[];
}

/** `admin_audit_log.before` / `.after`: the claim plus the profile; null = no access at all. */
export interface AdminAccessSnapshot {
  admin: boolean;
  role: string | null;
  name: string | null;
  email: string | null;
  permissions: string[];
}

export interface AdminAccessResult {
  uid: string;
  email: string | null;
  /** Whether the account now holds the `admin` claim. */
  admin: boolean;
  /** `admins/{uid}.role` now; null after a revoke. */
  role: AdminRole | null;
  /** false when the account already had exactly this access (nothing was written). */
  changed: boolean;
}

export interface GrantOptions {
  /** Omitted: keep the current role, or `DEFAULT_ADMIN_ROLE` for a new admin. */
  role?: AdminRole;
  /** Omitted: keep the current name, else the Auth display name, else the email's local part. */
  name?: string;
  /** Recorded as `admin_audit_log.adminUid`. */
  actorUid: string;
  /** When set, this uid must still be a super admin when the change commits. */
  requireSuper?: string;
}

export interface RevokeOptions {
  /** Recorded as `admin_audit_log.adminUid`; may not be the account being revoked. */
  actorUid: string;
  /** When set, this uid must still be a super admin when the change commits. */
  requireSuper?: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// setAdminClaim callable
// ─────────────────────────────────────────────────────────────────────────────

/**
 * `setAdminClaim` callable (super admin). Data
 * `{ uid?, email?, grant: boolean, role?: 'super'|'ops'|'content'|'finance', name? }`
 * (exactly one of uid / email) → `AdminAccessResult`.
 *
 * Grant: merges `admin: true` into the account's custom claims (others, e.g. a
 * `seller` claim, are kept) and upserts `admins/{uid}`. Revoke: removes only the
 * `admin` claim and deletes `admins/{uid}`. Both write an `admin_audit_log` entry
 * (`admin.grant` / `admin.revoke`, target `admins/{uid}`, before / after) unless the
 * account already had exactly the requested access.
 *
 * Errors: `unauthenticated` (signed out), `permission-denied` (caller lacks the
 * `admin` claim or is not `super`), `invalid-argument` (malformed data), `not-found`
 * (no account with that uid / email), `failed-precondition` (revoking yourself;
 * revoking or demoting the last super admin).
 */
export async function setAdminClaimCore(
  deps: AdminAccessDeps,
  data: unknown,
  caller: AdminCaller,
): Promise<AdminAccessResult> {
  const callerUid = caller.uid;
  if (!callerUid) throw new HttpsError('unauthenticated', 'Sign in to manage admin access.');
  if (caller.claims?.[ADMIN_CLAIM] !== true) throw new HttpsError('permission-denied', SUPER_ONLY_MESSAGE);
  // Before looking at the target: a non-super admin learns nothing about which accounts exist.
  if (!isSuperProfile((await adminDoc(deps.db, callerUid).get()).data())) {
    throw new HttpsError('permission-denied', SUPER_ONLY_MESSAGE);
  }

  const request = parseSetAdminClaimData(data);
  const user = await findTargetUser(deps.auth, request);
  return request.grant
    ? grantAdminAccess(deps, user, {
        role: request.role,
        name: request.name,
        actorUid: callerUid,
        requireSuper: callerUid,
      })
    : revokeAdminAccess(deps, user, { actorUid: callerUid, requireSuper: callerUid });
}

/** Validates the callable data; `invalid-argument` for anything malformed. */
export function parseSetAdminClaimData(data: unknown): SetAdminClaimRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw new HttpsError('invalid-argument', 'Expected { uid | email, grant, role?, name? }.');
  }
  const input = data as Record<string, unknown>;
  if (typeof input.grant !== 'boolean') throw new HttpsError('invalid-argument', '`grant` must be true or false.');

  const hasUid = input.uid !== undefined && input.uid !== null;
  const hasEmail = input.email !== undefined && input.email !== null;
  if (hasUid === hasEmail) throw new HttpsError('invalid-argument', 'Pass exactly one of `uid` or `email`.');

  const request: SetAdminClaimRequest = { grant: input.grant };
  if (hasUid) {
    if (typeof input.uid !== 'string' || input.uid.trim().length === 0 || input.uid.length > 128) {
      throw new HttpsError('invalid-argument', '`uid` must be a non-empty string of at most 128 characters.');
    }
    request.uid = input.uid.trim();
  } else {
    const email = typeof input.email === 'string' ? input.email.trim() : '';
    if (!looksLikeEmail(email)) throw new HttpsError('invalid-argument', '`email` is not an email address.');
    request.email = email;
  }

  if (input.role !== undefined && input.role !== null) {
    if (!isAdminRole(input.role)) {
      throw new HttpsError('invalid-argument', `\`role\` must be one of ${ADMIN_ROLES.join(', ')}.`);
    }
    request.role = input.role;
  }
  if (input.name !== undefined && input.name !== null) {
    if (typeof input.name !== 'string' || input.name.trim().length > MAX_ADMIN_NAME_LENGTH) {
      throw new HttpsError('invalid-argument', `\`name\` must be a string of at most ${MAX_ADMIN_NAME_LENGTH} characters.`);
    }
    if (input.name.trim().length > 0) request.name = input.name.trim();
  }
  return request;
}

/** Deliberately loose: Firebase Auth is the judge of the exact syntax. */
export function looksLikeEmail(value: string): boolean {
  return value.length <= 320 && /^[^\s@]+@[^\s@]+$/.test(value);
}

async function findTargetUser(auth: Auth, request: SetAdminClaimRequest): Promise<UserRecord> {
  try {
    return request.uid !== undefined ? await auth.getUser(request.uid) : await auth.getUserByEmail(request.email!);
  } catch (e) {
    const code = authErrorCode(e);
    if (code === 'auth/user-not-found') {
      throw new HttpsError('not-found', `No account with that ${request.uid !== undefined ? 'uid' : 'email'}.`);
    }
    if (code === 'auth/invalid-email' || code === 'auth/invalid-uid' || code === 'auth/argument-error') {
      throw new HttpsError('invalid-argument', `That ${request.uid !== undefined ? 'uid' : 'email'} is not valid.`);
    }
    throw e;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grant / revoke — shared by the callable and scripts/create-admin.ts
// ─────────────────────────────────────────────────────────────────────────────

/** Gives `user` the `admin` claim and an `admins/{uid}` profile (see the file comment). */
export async function grantAdminAccess(
  deps: AdminAccessDeps,
  user: UserRecord,
  options: GrantOptions,
): Promise<AdminAccessResult> {
  const { db } = deps;
  const ref = adminDoc(db, user.uid);
  const claimBefore = user.customClaims?.[ADMIN_CLAIM] === true;

  const { profile, docChanged } = await db.runTransaction(async (tx) => {
    // ── Reads ──
    if (options.requireSuper !== undefined) await assertSuperInTransaction(db, tx, options.requireSuper);
    const snap = await tx.get(ref);
    const existing = snap.data();
    const next = nextProfile(user, existing, options);
    if (isSuperProfile(existing) && next.role !== SUPER_ADMIN_ROLE) {
      await assertAnotherSuper(db, tx, user.uid);
    }

    // ── Writes ──
    if (claimBefore && existing !== undefined && sameProfile(existing, next)) {
      return { profile: next, docChanged: false };
    }
    const now = FieldValue.serverTimestamp();
    tx.set(
      ref,
      { ...next, updatedAt: now, ...(existing?.createdAt == null && { createdAt: now }) },
      { merge: true },
    );
    tx.create(
      db.collection(P.adminAuditLog).doc(),
      auditEntry(options.actorUid, AUDIT_ACTION_GRANT, user.uid, accessSnapshot(claimBefore, existing), accessSnapshot(true, next)),
    );
    return { profile: next, docChanged: true };
  });

  const claimChanged = await setAdminClaimValue(deps.auth, user.uid, true);
  return {
    uid: user.uid,
    email: user.email ?? null,
    admin: true,
    role: profile.role,
    changed: docChanged || claimChanged,
  };
}

/** Removes the `admin` claim (keeping every other claim) and deletes `admins/{uid}`. */
export async function revokeAdminAccess(
  deps: AdminAccessDeps,
  user: UserRecord,
  options: RevokeOptions,
): Promise<AdminAccessResult> {
  if (user.uid === options.actorUid) throw new HttpsError('failed-precondition', SELF_REVOKE_MESSAGE);
  const { db } = deps;
  const ref = adminDoc(db, user.uid);
  const claims = user.customClaims ?? {};
  const claimBefore = claims[ADMIN_CLAIM] === true;

  const docChanged = await db.runTransaction(async (tx) => {
    // ── Reads ──
    if (options.requireSuper !== undefined) await assertSuperInTransaction(db, tx, options.requireSuper);
    const snap = await tx.get(ref);
    const existing = snap.data();
    if (isSuperProfile(existing)) await assertAnotherSuper(db, tx, user.uid);

    // ── Writes ──
    if (existing === undefined && !(ADMIN_CLAIM in claims)) return false;
    if (existing !== undefined) tx.delete(ref);
    tx.create(
      db.collection(P.adminAuditLog).doc(),
      auditEntry(options.actorUid, AUDIT_ACTION_REVOKE, user.uid, accessSnapshot(claimBefore, existing), null),
    );
    return true;
  });

  const claimChanged = await setAdminClaimValue(deps.auth, user.uid, false);
  return { uid: user.uid, email: user.email ?? null, admin: false, role: null, changed: docChanged || claimChanged };
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

const adminDoc = (db: Firestore, uid: string) => db.collection(P.admins).doc(uid);

function isSuperProfile(data: DocumentData | undefined): boolean {
  return data?.role === SUPER_ADMIN_ROLE;
}

/** `permission-denied` unless `uid` holds a `super` admins doc (read in `tx`, so checked at commit). */
async function assertSuperInTransaction(db: Firestore, tx: Transaction, uid: string): Promise<void> {
  if (!isSuperProfile((await tx.get(adminDoc(db, uid))).data())) {
    throw new HttpsError('permission-denied', SUPER_ONLY_MESSAGE);
  }
}

/** `failed-precondition` unless a super admin other than `uid` exists. */
async function assertAnotherSuper(db: Firestore, tx: Transaction, uid: string): Promise<void> {
  const supers = await tx.get(db.collection(P.admins).where('role', '==', SUPER_ADMIN_ROLE).limit(2));
  if (!supers.docs.some((d) => d.id !== uid)) throw new HttpsError('failed-precondition', LAST_SUPER_MESSAGE);
}

/** What `admins/{uid}` should hold after a grant. */
function nextProfile(user: UserRecord, existing: DocumentData | undefined, options: GrantOptions): AdminProfile {
  const currentRole: unknown = existing?.role;
  const role = options.role ?? (isAdminRole(currentRole) ? currentRole : DEFAULT_ADMIN_ROLE);
  const name =
    options.name ??
    stringOrNull(existing?.name) ??
    stringOrNull(user.displayName) ??
    stringOrNull(user.email?.split('@')[0]) ??
    'Admin';
  return {
    name,
    email: user.email ?? null,
    role,
    // Kept across grants (a role change does not silently drop them); [] for a new admin.
    permissions: existing === undefined ? [] : stringList(existing.permissions),
  };
}

function sameProfile(existing: DocumentData, next: AdminProfile): boolean {
  return (
    existing.name === next.name &&
    (existing.email ?? null) === next.email &&
    existing.role === next.role &&
    Array.isArray(existing.permissions) &&
    existing.permissions.length === next.permissions.length &&
    next.permissions.every((p, i) => existing.permissions[i] === p)
  );
}

function accessSnapshot(admin: boolean, profile: DocumentData | AdminProfile | undefined): AdminAccessSnapshot | null {
  if (!admin && profile === undefined) return null;
  return {
    admin,
    role: stringOrNull(profile?.role),
    name: stringOrNull(profile?.name),
    email: stringOrNull(profile?.email),
    permissions: stringList(profile?.permissions),
  };
}

/** `admin_audit_log/{id}` (SRS §6.14) — the same shape the dashboard's `AuditLog.add` writes. */
export function auditEntry(
  adminUid: string,
  action: string,
  uid: string,
  before: AdminAccessSnapshot | null,
  after: AdminAccessSnapshot | null,
): DocumentData {
  return {
    adminUid,
    action,
    target: `${P.admins}/${uid}`,
    before,
    after,
    at: FieldValue.serverTimestamp(),
  };
}

/**
 * Sets (`true`) or removes (`false`) the `admin` claim on the account's CURRENT
 * claims — re-read here, so a claim another writer set meanwhile (e.g. `seller`) is
 * kept. Returns false when the claim already had that state.
 */
async function setAdminClaimValue(auth: Auth, uid: string, admin: boolean): Promise<boolean> {
  const claims: Record<string, unknown> = { ...((await auth.getUser(uid)).customClaims ?? {}) };
  if (admin ? claims[ADMIN_CLAIM] === true : !(ADMIN_CLAIM in claims)) return false;
  if (admin) claims[ADMIN_CLAIM] = true;
  else delete claims[ADMIN_CLAIM];
  await auth.setCustomUserClaims(uid, Object.keys(claims).length > 0 ? claims : null);
  return true;
}
