/**
 * Who may call an admin callable (SRS §6.14, §9): the `admin` custom claim in
 * the caller's ID token AND an `admins/{uid}` doc whose `role` is one of the
 * function's roles. Plus the `admin_audit_log` entry shape every admin change
 * writes (the dashboard's `AuditLog.add`).
 */
import { FieldValue, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { FirestorePaths as P } from '../shared/paths';
import { ADMIN_CLAIM, isAdminRole, type AdminCaller, type AdminRole } from './setAdminClaim';

/** The caller's uid and role; `unauthenticated` / `permission-denied` otherwise. */
export async function requireAdminRole(
  db: Firestore,
  caller: AdminCaller,
  roles: readonly AdminRole[],
  deniedMessage: string,
): Promise<{ uid: string; role: AdminRole }> {
  const uid = caller.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to the dashboard first.');
  if (caller.claims?.[ADMIN_CLAIM] !== true) throw new HttpsError('permission-denied', deniedMessage);
  const role: unknown = (await db.collection(P.admins).doc(uid).get()).get('role');
  if (!isAdminRole(role) || !roles.includes(role)) throw new HttpsError('permission-denied', deniedMessage);
  return { uid, role };
}

/** `admin_audit_log/{id}` (SRS §6.14): `adminUid, action, target, before, after, at`. */
export function auditLogEntry(
  adminUid: string,
  action: string,
  target: string,
  before: DocumentData | null,
  after: DocumentData | null,
): DocumentData {
  return { adminUid, action, target, before, after, at: FieldValue.serverTimestamp() };
}

/** `uid` of a document id the callables accept. */
export function isUid(v: unknown): v is string {
  return typeof v === 'string' && v.length > 0 && v.length <= 128 && !v.includes('/') && v !== '.' && v !== '..';
}
