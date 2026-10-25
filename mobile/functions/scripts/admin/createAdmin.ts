/**
 * Core of scripts/create-admin.ts: bootstraps an admin without a calling admin —
 * the only way to create the FIRST super admin, since `setAdminClaim` requires a
 * super admin caller. Uses the same grant logic as `setAdminClaim` (claim merged
 * into the existing claims, `admins/{uid}` upserted, `admin_audit_log` entry), so
 * the result is indistinguishable from a grant made in the dashboard.
 */
import type { Auth, UserRecord } from 'firebase-admin/auth';
import { authErrorCode } from '../../src/auth/authUsers';
import {
  ADMIN_ROLES,
  MAX_ADMIN_NAME_LENGTH,
  SUPER_ADMIN_ROLE,
  grantAdminAccess,
  isAdminRole,
  looksLikeEmail,
  type AdminAccessDeps,
  type AdminAccessResult,
  type AdminRole,
} from '../../src/admin/setAdminClaim';

/** `admin_audit_log.adminUid` of grants made by this script (there is no admin uid to record). */
export const CREATE_ADMIN_ACTOR = 'script:create-admin';

/** Firebase Auth's own minimum. */
export const MIN_PASSWORD_LENGTH = 6;

export interface CreateAdminInput {
  email: string;
  name: string;
  /** Creates the email/password account when none exists; ignored for an existing account. */
  password?: string;
  role: AdminRole;
}

export interface CreateAdminResult extends AdminAccessResult {
  /** true when this run created the Auth account. */
  userCreated: boolean;
  /** true when `--password` was given for an account that already existed (left unchanged). */
  passwordIgnored: boolean;
  /** The account's custom claims after the grant. */
  claims: Record<string, unknown>;
}

/** Command-line values → input, or the list of problems (never both). */
export function parseCreateAdminInput(raw: {
  email?: string;
  name?: string;
  password?: string;
  role?: string;
}): { input: CreateAdminInput; problems: [] } | { input: null; problems: string[] } {
  const problems: string[] = [];
  const email = raw.email?.trim() ?? '';
  const name = raw.name?.trim() ?? '';
  const role = raw.role ?? SUPER_ADMIN_ROLE;
  if (!looksLikeEmail(email)) problems.push('--email must be an email address.');
  if (name.length === 0 || name.length > MAX_ADMIN_NAME_LENGTH) {
    problems.push(`--name is required (1–${MAX_ADMIN_NAME_LENGTH} characters).`);
  }
  if (raw.password !== undefined && raw.password.length < MIN_PASSWORD_LENGTH) {
    problems.push(`--password must be at least ${MIN_PASSWORD_LENGTH} characters.`);
  }
  if (!isAdminRole(role)) problems.push(`--role must be one of ${ADMIN_ROLES.join(', ')}.`);
  if (problems.length > 0 || !isAdminRole(role)) return { input: null, problems };
  return { input: { email, name, role, ...(raw.password !== undefined && { password: raw.password }) }, problems: [] };
}

/**
 * Finds the account by email — creating it with `password` when it does not exist —
 * and grants it admin access with `role`. Running it again converges (no second
 * account, no duplicate audit entry when nothing changed).
 *
 * Throws (plain `Error` or `HttpsError`) when there is no account and no password,
 * or when the grant would demote the last super admin.
 */
export async function createAdmin(deps: AdminAccessDeps, input: CreateAdminInput): Promise<CreateAdminResult> {
  let user = await findByEmail(deps.auth, input.email);
  let userCreated = false;
  if (user === null) {
    if (input.password === undefined) {
      throw new Error(
        `No account with email ${input.email}. Pass --password to create an email/password account, ` +
          'or create it in the Firebase console first.',
      );
    }
    user = await createEmailUser(deps.auth, input);
    userCreated = user !== null;
    user ??= await findByEmail(deps.auth, input.email);
    if (user === null) throw new Error(`Could not create or find the account ${input.email}.`);
  }

  const result = await grantAdminAccess(deps, user, {
    role: input.role,
    name: input.name,
    actorUid: CREATE_ADMIN_ACTOR,
  });
  const claims = (await deps.auth.getUser(user.uid)).customClaims ?? {};
  return {
    ...result,
    userCreated,
    passwordIgnored: !userCreated && input.password !== undefined,
    claims,
  };
}

async function findByEmail(auth: Auth, email: string): Promise<UserRecord | null> {
  try {
    return await auth.getUserByEmail(email);
  } catch (e) {
    if (authErrorCode(e) === 'auth/user-not-found') return null;
    throw e;
  }
}

/** The new account, or null when another writer created it meanwhile. */
async function createEmailUser(auth: Auth, input: CreateAdminInput): Promise<UserRecord | null> {
  try {
    return await auth.createUser({ email: input.email, password: input.password, displayName: input.name });
  } catch (e) {
    if (authErrorCode(e) === 'auth/email-already-exists') return null;
    throw e;
  }
}
