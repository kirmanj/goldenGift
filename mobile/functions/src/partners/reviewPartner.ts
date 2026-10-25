/**
 * Stores / Partners decisions (SRS §5.25, §9): `reviewPartner` and
 * `setStoreStatus`, super | ops admins. Every change writes its
 * `admin_audit_log` entry in the same transaction; the owner is notified after.
 *
 * Approve (`pendingApproval` → `active`, `commissionPercent` 0–50):
 *  - the store becomes active with the commission (PROVISIONAL, SRS §12 item 5:
 *    commission set per store at approval, payouts handled manually);
 *  - `admins/{ownerUid}` = `{ role: 'seller', storeId, name, email, permissions: [] }`
 *    (the dashboard reads the display name from it) and `users/{ownerUid}`
 *    gets `role: seller` + the store in `storeIds`;
 *  - the custom claim `seller: storeId` is merged into the owner's claims, every
 *    other claim kept. Sellers NEVER get `admin: true` — the rules treat that as
 *    full admin. An owner who is a staff admin cannot become a seller.
 *  Approving an already active store again re-applies the claim and the admins
 *  doc (a repair after a half-finished call) without another audit entry.
 *
 * Reject (`pendingApproval` only, reason 3–500): the application is archived on
 * `stores/{id}/private/application` (`rejectedAt`, `rejectReason`, `rejectedBy`,
 * the store doc as `store`) and the store doc is deleted, so the owner may apply
 * again; the archive stays readable by admins and the owner.
 *
 * `setStoreStatus` (`active` ⇄ `suspended`, reason 3–500): `status`,
 * `statusReason`; a suspended store's products stop being orderable (placeOrder)
 * and its seller's dashboard is paused. The seller claim is kept.
 */
import type { Auth } from 'firebase-admin/auth';
import { FieldValue, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { auditLogEntry, requireAdminRole, SELLER_CLAIM } from '../admin/adminCaller';
import { ADMIN_CLAIM, isAdminRole, type AdminCaller, type AdminRole } from '../admin/setAdminClaim';
import { authErrorCode } from '../auth/authUsers';
import { notifyUser } from '../notifications/notifyUser';
import type { PushMessaging } from '../notifications/push';
import { isDocId } from '../orders/createOrderDoc';
import { decimal, string, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { graphemeLength } from '../shared/text';
import {
  partnerApprovedNotification,
  partnerRejectedNotification,
  storeReactivatedNotification,
  storeSuspendedNotification,
} from './partnerMessages';
import { APPLICATION_DOC } from './submitPartnerApplication';

export const REVIEW_ROLES: readonly AdminRole[] = ['super', 'ops'];
/** `maxCommissionPercent` in the dashboard. */
export const MAX_COMMISSION_PERCENT = 50;
export const REASON_MIN = 3;
export const REASON_MAX = 500;
export const SELLER_ROLE = 'seller';

export interface PartnerDeps {
  db: Firestore;
  auth: Auth;
  messaging: PushMessaging | null;
  logger?: Pick<typeof functionsLogger, 'warn' | 'info'>;
}

export interface StoreDecision {
  storeId: string;
  status: 'active' | 'suspended' | 'rejected';
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

function parseReason(v: unknown): string {
  const reason = typeof v === 'string' ? v.trim() : '';
  if (graphemeLength(reason) < REASON_MIN || graphemeLength(reason) > REASON_MAX) {
    throw bad(`\`reason\` must be ${REASON_MIN}–${REASON_MAX} characters.`);
  }
  return reason;
}

function parseStoreId(d: Record<string, unknown>): string {
  if (!isDocId(d.storeId)) throw bad('`storeId` is missing or invalid.');
  return d.storeId;
}

function asRecord(data: unknown): Record<string, unknown> {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) throw bad('Expected an object.');
  return data as Record<string, unknown>;
}

export type ReviewRequest =
  | { storeId: string; decision: 'approve'; commissionPercent: number }
  | { storeId: string; decision: 'reject'; reason: string };

export function parseReviewPartnerData(data: unknown): ReviewRequest {
  const d = asRecord(data);
  const storeId = parseStoreId(d);
  if (d.decision === 'approve') {
    const c = d.commissionPercent;
    if (typeof c !== 'number' || !Number.isFinite(c) || c < 0 || c > MAX_COMMISSION_PERCENT) {
      throw bad(`\`commissionPercent\` must be 0–${MAX_COMMISSION_PERCENT}.`);
    }
    return { storeId, decision: 'approve', commissionPercent: c };
  }
  if (d.decision === 'reject') return { storeId, decision: 'reject', reason: parseReason(d.reason) };
  throw bad('`decision` must be approve or reject.');
}

const storeNotFound = () => new HttpsError('not-found', 'Store not found.');

export async function reviewPartnerCore(deps: PartnerDeps, data: unknown, caller: AdminCaller): Promise<StoreDecision> {
  const actor = await requireAdminRole(deps.db, caller, REVIEW_ROLES, 'review partner applications');
  const request = parseReviewPartnerData(data);
  return request.decision === 'approve'
    ? approve(deps, actor.uid, request.storeId, request.commissionPercent)
    : reject(deps, actor.uid, request.storeId, request.reason);
}

async function approve(deps: PartnerDeps, adminUid: string, storeId: string, commissionPercent: number): Promise<StoreDecision> {
  const { db, auth } = deps;
  const storeRef = db.collection(P.stores).doc(storeId);
  const first = (await storeRef.get()).data();
  if (first === undefined) throw storeNotFound();
  const ownerUid = stringOrNull(first.ownerUid);
  if (ownerUid === null || !isDocId(ownerUid)) throw new HttpsError('failed-precondition', 'This store has no owner account.');

  let owner;
  try {
    owner = await auth.getUser(ownerUid);
  } catch (e) {
    if (authErrorCode(e) === 'auth/user-not-found') {
      throw new HttpsError('failed-precondition', "The owner's account no longer exists.");
    }
    throw e;
  }
  if (owner.customClaims?.[ADMIN_CLAIM] === true) {
    throw new HttpsError('failed-precondition', "The owner's account is a Golden Gift admin — a store needs its own account.");
  }

  const { storeName, newlyApproved } = await db.runTransaction(async (tx) => {
    // ── Reads ──
    const adminRef = db.collection(P.admins).doc(ownerUid);
    const userRef = db.collection(P.users).doc(ownerUid);
    const appRef = storeRef.collection(P.storePrivate).doc(APPLICATION_DOC);
    const [storeSnap, adminSnap, userSnap, appSnap] = await tx.getAll(storeRef, adminRef, userRef, appRef);
    const store = storeSnap.data();
    if (store === undefined) throw storeNotFound();
    if (store.ownerUid !== ownerUid) throw new HttpsError('aborted', 'The store changed; try again.');
    const status = string(store.status);
    if (status !== 'pendingApproval' && status !== 'active') {
      throw new HttpsError('failed-precondition', 'Only a pending application can be approved.');
    }
    const existingAdmin = adminSnap.data();
    if (existingAdmin !== undefined && existingAdmin.role !== SELLER_ROLE && isAdminRole(existingAdmin.role)) {
      throw new HttpsError('failed-precondition', "The owner's account is a Golden Gift admin — a store needs its own account.");
    }
    if (existingAdmin?.role === SELLER_ROLE && stringOrNull(existingAdmin.storeId) !== null && existingAdmin.storeId !== storeId) {
      throw new HttpsError('failed-precondition', 'The owner already runs another store.');
    }
    const fresh = status === 'pendingApproval';

    // ── Writes ──
    const ts = FieldValue.serverTimestamp();
    const name = string(store.name);
    if (fresh) {
      tx.update(storeRef, {
        status: 'active',
        commissionPercent,
        statusReason: null,
        approvedAt: ts,
        approvedBy: adminUid,
        updatedAt: ts,
      });
      tx.create(
        db.collection(P.adminAuditLog).doc(),
        auditLogEntry(
          adminUid,
          'store.approve',
          `${P.stores}/${storeId}`,
          { status, commissionPercent: decimal(store.commissionPercent) },
          { status: 'active', commissionPercent, ownerUid },
        ),
      );
    }
    tx.set(
      adminRef,
      {
        name: stringOrNull(appSnap.get('ownerName')) ?? stringOrNull(userSnap.get('name')) ?? owner.displayName ?? name,
        email: owner.email ?? null,
        role: SELLER_ROLE,
        storeId,
        permissions: [],
        updatedAt: ts,
        ...(existingAdmin?.createdAt == null && { createdAt: ts }),
      },
      { merge: true },
    );
    if (userSnap.exists) {
      tx.update(userRef, { role: SELLER_ROLE, storeIds: FieldValue.arrayUnion(storeId), updatedAt: ts });
    }
    return { storeName: name, newlyApproved: fresh };
  });

  // The claim last: re-read, so a claim another writer set meanwhile is kept.
  const claims: Record<string, unknown> = { ...((await auth.getUser(ownerUid)).customClaims ?? {}) };
  if (claims[SELLER_CLAIM] !== storeId) {
    claims[SELLER_CLAIM] = storeId;
    await auth.setCustomUserClaims(ownerUid, claims);
  }

  if (newlyApproved) await notifyOwner(deps, ownerUid, partnerApprovedNotification(storeId, storeName), `${storeId}-approved`);
  return { storeId, status: 'active' };
}

async function reject(deps: PartnerDeps, adminUid: string, storeId: string, reason: string): Promise<StoreDecision> {
  const { db } = deps;
  const storeRef = db.collection(P.stores).doc(storeId);
  const appRef = storeRef.collection(P.storePrivate).doc(APPLICATION_DOC);

  const outcome = await db.runTransaction(async (tx) => {
    // ── Reads ──
    const [storeSnap, appSnap] = await tx.getAll(storeRef, appRef);
    const store = storeSnap.data();
    if (store === undefined) {
      // Already rejected (a retry): the archive says so.
      if (appSnap.get('rejectedAt') != null) return null;
      throw storeNotFound();
    }
    if (store.status !== 'pendingApproval') {
      throw new HttpsError('failed-precondition', 'Only a pending application can be rejected — suspend an active store instead.');
    }

    // ── Writes ──
    const ts = FieldValue.serverTimestamp();
    const { createdAt: _c, updatedAt: _u, ...storeData } = store;
    tx.set(
      appRef,
      {
        ownerUid: stringOrNull(store.ownerUid),
        store: storeData,
        rejectedAt: ts,
        rejectReason: reason,
        rejectedBy: adminUid,
        ...(!appSnap.exists && { submittedAt: store.createdAt ?? ts }),
      },
      { merge: true },
    );
    tx.delete(storeRef);
    tx.create(
      db.collection(P.adminAuditLog).doc(),
      auditLogEntry(adminUid, 'store.reject', `${P.stores}/${storeId}`, { status: 'pendingApproval', name: string(store.name) }, {
        status: 'rejected',
        reason,
      }),
    );
    return { ownerUid: stringOrNull(store.ownerUid), name: string(store.name) };
  });

  if (outcome?.ownerUid) {
    await notifyOwner(deps, outcome.ownerUid, partnerRejectedNotification(storeId, outcome.name, reason), `${storeId}-rejected`);
  }
  return { storeId, status: 'rejected' };
}

export function parseSetStoreStatusData(data: unknown): { storeId: string; status: 'active' | 'suspended'; reason: string } {
  const d = asRecord(data);
  const storeId = parseStoreId(d);
  if (d.status !== 'active' && d.status !== 'suspended') throw bad('`status` must be active or suspended.');
  return { storeId, status: d.status, reason: parseReason(d.reason) };
}

export async function setStoreStatusCore(deps: PartnerDeps, data: unknown, caller: AdminCaller): Promise<StoreDecision> {
  const { db } = deps;
  const actor = await requireAdminRole(db, caller, REVIEW_ROLES, 'suspend or reactivate stores');
  const request = parseSetStoreStatusData(data);
  const storeRef = db.collection(P.stores).doc(request.storeId);

  const changed = await db.runTransaction(async (tx) => {
    const store = (await tx.get(storeRef)).data();
    if (store === undefined) throw storeNotFound();
    const status = string(store.status);
    if (status !== 'active' && status !== 'suspended') {
      throw new HttpsError('failed-precondition', 'Review the application first (Approve / Reject).');
    }
    if (status === request.status) return null;
    const ts = FieldValue.serverTimestamp();
    tx.update(storeRef, {
      status: request.status,
      statusReason: request.reason,
      statusUpdatedAt: ts,
      statusUpdatedBy: actor.uid,
      updatedAt: ts,
    });
    tx.create(
      db.collection(P.adminAuditLog).doc(),
      auditLogEntry(actor.uid, request.status === 'suspended' ? 'store.suspend' : 'store.reactivate', `${P.stores}/${request.storeId}`, { status }, {
        status: request.status,
        reason: request.reason,
      }),
    );
    return { ownerUid: stringOrNull(store.ownerUid), name: string(store.name) } as DocumentData;
  });

  if (changed?.ownerUid) {
    const n =
      request.status === 'suspended'
        ? storeSuspendedNotification(request.storeId, changed.name, request.reason)
        : storeReactivatedNotification(request.storeId, changed.name);
    await notifyOwner(deps, changed.ownerUid, n, `${request.storeId}-${request.status}-${Date.now().toString(36)}`);
  }
  return { storeId: request.storeId, status: request.status };
}

async function notifyOwner(deps: PartnerDeps, uid: string, n: Parameters<typeof notifyUser>[2], id: string): Promise<void> {
  const log = deps.logger ?? functionsLogger;
  try {
    await notifyUser({ db: deps.db, messaging: deps.messaging, logger: log }, uid, n, { notificationId: `store-${id}` });
  } catch (e) {
    log.warn('partner notification failed', { uid, error: e instanceof Error ? e.message : String(e) });
  }
}
