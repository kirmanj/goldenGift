/**
 * `adminIssueGiftCard` (SRS §9 Gift cards "manual issue"): super | ops | finance.
 *
 * Data `{ templateId, amount, recipientName, recipientPhone?, recipientEmail?,
 * message?, expiresAt? (ISO) }` → `{ giftCardId, code }`. No order: the card is
 * created `sent` (purchaserUid null, `issuedBy` = the admin), expiring at
 * `expiresAt` or 365 days from now, linked to the recipient's account when the
 * phone / email matches one (who is notified), with a `giftCard.issue`
 * `admin_audit_log` entry in the same transaction (the code itself is not logged).
 *
 * Amount: the template's presets / custom range (`GiftCardTemplateModel.accepts`);
 * a super admin may issue any amount from 1,000 to 10,000,000 IQD.
 *
 * Errors: unauthenticated, permission-denied, invalid-argument, not-found
 * ("Gift card template not found.").
 */
import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { auditLogEntry, requireAdminRole } from '../admin/adminCaller';
import type { AdminCaller, AdminRole } from '../admin/setAdminClaim';
import type { NotifyDeps } from '../notifications/notifyUser';
import { isDocId } from '../orders/createOrderDoc';
import { stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import {
  GIFT_CARD_MAX_AMOUNT,
  GIFT_CARD_MIN_FREE_AMOUNT,
  parseAmount,
  parseMessage,
  parseOptionalInstant,
  parseRecipient,
  parseTemplate,
  templateAccepts,
  type Recipient,
} from './giftCardRules';
import { expiryFrom, notifyIssued, prepareGiftCard } from './issueGiftCard';
import type { RecipientLookup } from './recipients';

export const ISSUE_ROLES: readonly AdminRole[] = ['super', 'ops', 'finance'];
/** Manual cards may be valid for at most five years. */
export const MAX_MANUAL_VALIDITY_MS = 5 * 366 * 24 * 60 * 60 * 1000;

export interface AdminIssueRequest extends Recipient {
  templateId: string;
  amount: number;
  message: string;
  expiresAtMs: number | null;
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

export function parseAdminIssueData(data: unknown, nowMs: number): AdminIssueRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw bad('Expected { templateId, amount, recipientName, … }.');
  }
  const d = data as Record<string, unknown>;
  if (!isDocId(d.templateId)) throw bad('`templateId` is missing or invalid.');
  const expiresAtMs = parseOptionalInstant(d.expiresAt, 'expiresAt');
  if (expiresAtMs !== null && (expiresAtMs <= nowMs || expiresAtMs > nowMs + MAX_MANUAL_VALIDITY_MS)) {
    throw bad('`expiresAt` must be in the future (at most five years ahead).');
  }
  return {
    templateId: d.templateId,
    amount: parseAmount(d.amount),
    // ManualGiftCardIssue.validate: a name of at least 2 characters; contact optional.
    ...parseRecipient(d, { requireContact: false, minName: 2 }),
    message: parseMessage(d.message),
    expiresAtMs,
  };
}

export interface AdminIssueDeps extends NotifyDeps {
  now?: () => number;
  random?: (n: number) => Buffer;
  /** Verified-identity recipient matching (recipients.ts); absent = nobody is matched. */
  recipients?: RecipientLookup;
}

export async function adminIssueGiftCardCore(
  deps: AdminIssueDeps,
  data: unknown,
  caller: AdminCaller,
): Promise<{ giftCardId: string; code: string }> {
  const { db } = deps;
  const actor = await requireAdminRole(db, caller, ISSUE_ROLES, 'issue gift cards');
  const nowMs = (deps.now ?? Date.now)();
  const request = parseAdminIssueData(data, nowMs);

  const result = await issueInTransaction(db, actor, request, nowMs, deps.random, deps.recipients);
  await notifyIssued(deps, {
    id: result.giftCardId,
    amount: request.amount,
    status: 'sent',
    recipientUid: result.recipientUid,
    purchaserUid: null,
    recipientName: request.recipientName,
    purchaserName: 'Golden Gift',
    scheduledAtMs: null,
  });
  return { giftCardId: result.giftCardId, code: result.code };
}

async function issueInTransaction(
  db: Firestore,
  actor: { uid: string; role: AdminRole },
  request: AdminIssueRequest,
  nowMs: number,
  random: ((n: number) => Buffer) | undefined,
  recipients: RecipientLookup | undefined,
): Promise<{ giftCardId: string; code: string; recipientUid: string | null }> {
  return db.runTransaction(async (tx) => {
    // ── Reads ──
    const snap = await tx.get(db.collection(P.giftCardTemplates).doc(request.templateId));
    if (!snap.exists) throw new HttpsError('not-found', 'Gift card template not found.');
    const template = parseTemplate(snap.id, snap.data()!);
    const freeAmount = actor.role === 'super' && request.amount >= GIFT_CARD_MIN_FREE_AMOUNT && request.amount <= GIFT_CARD_MAX_AMOUNT;
    if (!freeAmount && !templateAccepts(template, request.amount)) {
      throw bad(
        actor.role === 'super'
          ? `Amounts outside the template must be ${GIFT_CARD_MIN_FREE_AMOUNT}–${GIFT_CARD_MAX_AMOUNT} IQD.`
          : 'This template does not offer that amount.',
      );
    }
    const prepared = await prepareGiftCard(
      db,
      tx,
      {
        templateId: template.id,
        amount: request.amount,
        purchaserUid: null,
        recipientName: request.recipientName,
        recipientPhone: request.recipientPhone,
        recipientEmail: request.recipientEmail,
        message: request.message,
        photoUrl: null,
        scheduledAtMs: null,
        expiresAtMs: request.expiresAtMs ?? expiryFrom(nowMs),
        orderId: null,
        issuedBy: actor.uid,
      },
      template,
      nowMs,
      random,
      recipients,
    );

    // ── Writes ──
    prepared.write();
    tx.create(
      db.collection(P.adminAuditLog).doc(),
      auditLogEntry(actor.uid, 'giftCard.issue', `${P.giftCards}/${prepared.ref.id}`, null, {
        templateId: template.id,
        amount: request.amount,
        recipientName: request.recipientName,
        recipientPhone: request.recipientPhone,
        recipientEmail: request.recipientEmail,
        recipientUid: prepared.recipientUid,
        expiresAt: new Date(request.expiresAtMs ?? expiryFrom(nowMs)).toISOString(),
        offTemplate: !templateAccepts(template, request.amount),
      }),
    );
    return { giftCardId: prepared.ref.id, code: prepared.code, recipientUid: stringOrNull(prepared.recipientUid) };
  });
}
