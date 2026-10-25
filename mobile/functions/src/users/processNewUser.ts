import {
  FieldValue,
  type DocumentData,
  type Firestore,
  type Transaction,
} from 'firebase-admin/firestore';
import { applyJoinBonus, type JoinBonusOutcome } from '../referrals/joinBonus';
import type { ReferralStatus, UserRole } from '../shared/enums';
import { runOnce } from '../shared/idempotency';
import { FirestorePaths } from '../shared/paths';
import { generateReferralCode, isReferralCode, normalizeEnteredCode } from './referralCode';
import { referralNotAppliedNotification } from './referralNotice';

export type ReferralOutcome =
  | 'none' // no code entered
  | 'accepted'
  | 'notFound' // unknown or malformed code
  | 'ownCode'
  | 'referrerInactive' // referrer deleted or blocked
  | 'sameDevice';

export interface NewUserResult {
  /** false when this uid was already processed, or its doc is gone / deleted. */
  processed: boolean;
  referralCode?: string;
  referral?: ReferralOutcome;
  /** The join bonus step (only when a referral exists): paid, capped, no bonus, already decided. */
  joinBonus?: JoinBonusOutcome;
}

export interface ProcessNewUserOptions {
  /** Code source; tests inject collisions. Default: crypto-random. */
  generateCode?: () => string;
  /** Epoch ms; tests pin the clock (credit expiry). */
  now?: () => number;
}

/** First name for the referrer's list (`referrals.referredName`), ≤ 40 characters. */
export function firstName(name: unknown): string | null {
  if (typeof name !== 'string') return null;
  const first = name.trim().split(/\s+/)[0] ?? '';
  return first.length > 0 ? Array.from(first).slice(0, 40).join('') : null;
}

/** Fresh codes tried before giving up (a collision is ~1 in 10^9 per existing user). */
export const MAX_CODE_ATTEMPTS = 5;

/** Server-owned fields set when the app's doc does not have them yet (SRS §6.1). */
const SERVER_DEFAULTS = {
  role: 'customer' satisfies UserRole,
  storeIds: [],
  totalOrders: 0,
  totalSpent: 0,
  isBlocked: false,
  isDeleted: false,
  referredBy: null,
} as const;

type Decision =
  | { outcome: Exclude<ReferralOutcome, 'accepted'> }
  | { outcome: 'accepted'; referrerUid: string };

/**
 * Server half of sign-up (SRS AUTH-3, AUTH-8, §5.19, §7 `onUserCreate`): runs
 * after the app created `users/{uid}`.
 *
 *  - gives the user a unique `referralCode` and the server-owned defaults;
 *  - creates `wallets/{uid}` (0 / 0 IQD) unless it already exists;
 *  - resolves `referralCodeEntered`: accepted → `referredBy` + `referrals/{uid}`
 *    (status pending, `referredName` = first name); rejected → an in-app
 *    `referralNotApplied` notification.
 *
 * Once per uid (`function_runs/onUserCreate:{uid}`), in one transaction, so a
 * replayed or retried trigger never creates a second code, wallet or referral.
 *
 * Then, in its own once-only transaction (`joinBonus:{referralId}`), the join
 * bonus / monthly cap of the referral (referrals/joinBonus.ts). It also runs on a
 * replay, so a crash between the two steps is completed by the retry.
 */
export async function processNewUser(
  db: Firestore,
  uid: string,
  options: ProcessNewUserOptions = {},
): Promise<NewUserResult> {
  const generateCode = options.generateCode ?? generateReferralCode;
  let result: NewUserResult = { processed: false };

  const ran = await runOnce(db, `onUserCreate:${uid}`, async (tx) => {
    result = { processed: false }; // the transaction may run more than once
    const userRef = db.collection(FirestorePaths.users).doc(uid);
    const walletRef = db.collection(FirestorePaths.wallets).doc(uid);
    const referralRef = db.collection(FirestorePaths.referrals).doc(uid);

    // ── Reads (all before the first write) ──
    const [userSnap, walletSnap] = await tx.getAll(userRef, walletRef);
    const user = userSnap.data();
    if (user === undefined || user.isDeleted === true) return;

    const referralCode = isReferralCode(user.referralCode)
      ? user.referralCode
      : await uniqueReferralCode(db, tx, generateCode);
    const entered = normalizeEnteredCode(user.referralCodeEntered);
    const decision: Decision =
      entered === null ? { outcome: 'none' } : await resolveReferrer(db, tx, uid, user, entered);
    const referralExists =
      decision.outcome === 'accepted' ? (await tx.get(referralRef)).exists : false;

    // ── Writes ──
    const now = FieldValue.serverTimestamp();
    const userUpdate: DocumentData = { referralCode, updatedAt: now };
    for (const [key, value] of Object.entries(SERVER_DEFAULTS)) {
      if (!(key in user)) userUpdate[key] = value;
    }

    if (!walletSnap.exists) {
      tx.create(walletRef, { balance: 0, credits: 0, currency: 'IQD', createdAt: now, updatedAt: now });
    }

    if (decision.outcome === 'accepted') {
      userUpdate.referredBy = decision.referrerUid;
      if (!referralExists) {
        tx.create(referralRef, {
          referrerUid: decision.referrerUid,
          referredUid: uid,
          code: entered,
          referredName: firstName(user.name),
          status: 'pending' satisfies ReferralStatus,
          joinBonusPaid: false,
          orderBonusPaid: false,
          flags: [],
          createdAt: now,
          updatedAt: now,
        });
      }
    } else if (decision.outcome !== 'none') {
      tx.create(db.collection(FirestorePaths.notifications).doc(), referralNotAppliedNotification(uid));
    }

    tx.update(userRef, userUpdate);
    result = { processed: true, referralCode, referral: decision.outcome };
  });

  const joinBonus =
    !ran || result.referral === 'accepted' ? await applyJoinBonus(db, uid, { now: options.now }) : undefined;
  const outcome: NewUserResult = ran ? result : { processed: false };
  return joinBonus === undefined || joinBonus.status === 'skipped' ? outcome : { ...outcome, joinBonus };
}

/** A code no user has yet (transactional query, so it is checked at commit time). */
async function uniqueReferralCode(
  db: Firestore,
  tx: Transaction,
  generateCode: () => string,
): Promise<string> {
  for (let attempt = 0; attempt < MAX_CODE_ATTEMPTS; attempt++) {
    const code = generateCode();
    const taken = await tx.get(
      db.collection(FirestorePaths.users).where('referralCode', '==', code).limit(1),
    );
    if (taken.empty) return code;
  }
  throw new Error(`processNewUser: no free referral code after ${MAX_CODE_ATTEMPTS} attempts`);
}

/** SRS AUTH-8 / §5.19: unknown, own, same-device and inactive-referrer codes are rejected. */
async function resolveReferrer(
  db: Firestore,
  tx: Transaction,
  uid: string,
  user: DocumentData,
  code: string,
): Promise<Decision> {
  if (!isReferralCode(code)) return { outcome: 'notFound' };
  const match = await tx.get(
    db.collection(FirestorePaths.users).where('referralCode', '==', code).limit(1),
  );
  const referrer = match.docs[0];
  if (referrer === undefined) return { outcome: 'notFound' };
  if (referrer.id === uid) return { outcome: 'ownCode' };

  const data = referrer.data();
  if (data.isDeleted === true || data.isBlocked === true) return { outcome: 'referrerInactive' };

  const ownDevice = deviceIdOf(user);
  if (ownDevice !== null && ownDevice === deviceIdOf(data)) return { outcome: 'sameDevice' };

  // The monthly cap is applied right after, with the join bonus (referrals/joinBonus.ts).
  return { outcome: 'accepted', referrerUid: referrer.id };
}

function deviceIdOf(data: DocumentData): string | null {
  const id = data.deviceId;
  return typeof id === 'string' && id.trim().length > 0 ? id.trim() : null;
}
