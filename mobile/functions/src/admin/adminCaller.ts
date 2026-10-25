/**
 * Who may call a dashboard callable (SRS §9): the `admin: true` custom claim AND a
 * live `admins/{uid}` doc whose role is one of the allowed ones — the same two
 * halves `setAdminClaim` grants (the claim alone is not enough: a revoked admin's
 * token keeps the claim for up to an hour, the doc is gone at once).
 *
 * Sellers (partners) carry the claim `seller == storeId` and never `admin`.
 */
import { FieldValue, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { FirestorePaths as P } from '../shared/paths';
import { ADMIN_CLAIM, isAdminRole, type AdminCaller, type AdminRole } from './setAdminClaim';

/** The custom claim `reviewPartner` grants a partner: the id of their store. */
export const SELLER_CLAIM = 'seller';

export interface AdminActor {
  uid: string;
  role: AdminRole;
}

/** `permission-denied` unless the caller is an admin with one of `roles`. */
export async function requireAdminRole(
  db: Firestore,
  caller: AdminCaller,
  roles: readonly AdminRole[],
  what: string,
): Promise<AdminActor> {
  const uid = caller.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to the dashboard first.');
  if (caller.claims?.[ADMIN_CLAIM] !== true) throw new HttpsError('permission-denied', 'Admins only.');
  const role: unknown = (await db.collection(P.admins).doc(uid).get()).get('role');
  if (!isAdminRole(role) || !roles.includes(role)) {
    throw new HttpsError('permission-denied', `Your admin role cannot ${what}.`);
  }
  return { uid, role };
}

/** The caller's store when they are a partner (claim `seller`), else null. */
export function sellerStoreOf(caller: AdminCaller): string | null {
  const store = caller.claims?.[SELLER_CLAIM];
  return typeof store === 'string' && store.length > 0 && !store.includes('/') ? store : null;
}

/** `admin_audit_log/{id}` — the shape the dashboard's `AuditLog.add` writes (SRS §6.14). */
export function auditLogEntry(
  adminUid: string,
  action: string,
  target: string,
  before: DocumentData | null,
  after: DocumentData | null,
): DocumentData {
  return { adminUid, action, target, before, after, at: FieldValue.serverTimestamp() };
}
