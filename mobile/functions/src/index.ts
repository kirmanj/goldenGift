/**
 * Golden Gift Cloud Functions (SRS §7). Node 20, TypeScript, region europe-west1.
 *
 * Every function must be idempotent — use `runOnce` from ./shared/idempotency —
 * and every callable passes `enforceAppCheck: ENFORCE_APP_CHECK` (./shared/runtime).
 * Business logic lives in plain functions taking their dependencies (testable
 * against the emulators); this file only wires triggers to them.
 */
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { getStorage } from 'firebase-admin/storage';
import { defineInt, defineSecret, defineString } from 'firebase-functions/params';
import { logger, setGlobalOptions } from 'firebase-functions/v2';
import { onDocumentCreated, onDocumentUpdated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { adjustWalletCore } from './admin/adjustWallet';
import { aiGiftSearchCore, cachedCategories } from './ai/aiGiftSearch';
import { DEFAULT_GEMINI_MODEL, geminiModel, type GiftSearchModel } from './ai/giftModel';
import type { AdminCaller } from './admin/setAdminClaim';
import { setAdminClaimCore } from './admin/setAdminClaim';
import { setUserBlockedCore } from './admin/setUserBlocked';
import { changePhoneCore } from './auth/changePhone';
import { adminIssueGiftCardCore } from './giftCards/adminIssueGiftCard';
import { handleGiftCardOrderWrite, linkGiftCardsToNewUser } from './giftCards/issueGiftCard';
import { purchaseGiftCardCore } from './giftCards/purchaseGiftCard';
import { authRecipientLookup } from './giftCards/recipients';
import { redeemGiftCardCore } from './giftCards/redeemGiftCard';
import { expireGiftCards, sendDueGiftCards } from './giftCards/scheduledGiftCards';
import { resolveReviewLogin, type ReviewLogin } from './auth/reviewLogin';
import { sendOtpCore } from './auth/sendOtp';
import { verifyOtpAndSignInCore } from './auth/signIn';
import { sendBroadcastCore } from './notifications/sendBroadcast';
import { cancelOrderCore } from './orders/cancelOrder';
import { handleOrderStatusChange } from './orders/onOrderStatusChange';
import { placeOrderCore } from './orders/placeOrder';
import { updateOrderItemsCore } from './orders/updateOrderItems';
import { reviewPartnerCore, setStoreStatusCore } from './partners/reviewPartner';
import { submitPartnerApplicationCore } from './partners/submitPartnerApplication';
import { checkPaymentStatusCore } from './payments/checkPaymentStatus';
import { expirePaymentSessions as expirePaymentSessionsCore } from './payments/expirePayments';
import { createPaymentSessionCore } from './payments/paymentSessions';
import { resolveZainCashConfig, zainCashGateway, type PaymentGateway } from './payments/zainCash';
import { handleZainCashReturn } from './payments/zainCashReturn';
import { syncProduct } from './products/onProductWrite';
import { syncReel } from './reels/onReelWrite';
import { handleReviewWrite } from './reviews/onReviewWrite';
import { DEFAULT_ALGOLIA_INDEX, resolveAlgolia, type AlgoliaIndex } from './search/algolia';
import { FirestorePaths } from './shared/paths';
import { ENFORCE_APP_CHECK } from './shared/runtime';
import { acceptQuoteCore } from './specialRequests/acceptQuote';
import { drawSecretSantaCore, joinSecretSantaCore } from './secretSanta/secretSanta';
import { syncWishNoteToAssignment } from './secretSanta/wishNoteSync';
import { handleSpecialRequestMessage, handleSpecialRequestUpdate } from './specialRequests/onSpecialRequestEvents';
import { deleteUserAccount } from './users/deleteAccount';
import { processNewUser } from './users/processNewUser';
import { expireCredits as expireCreditLots } from './wallet/expireCredits';

/**
 * Performance defaults (SRS §8). Every function: europe-west1, 256 MiB, 60 s, at
 * most 10 instances (each serves up to 80 concurrent requests — Cloud Functions
 * 2nd gen with 1 vCPU), scale to zero. Heavier functions override below; the
 * heavy SDKs (Gemini, Algolia, Cloud Storage) load only inside the functions that
 * use them, so they never slow the other cold starts.
 */
setGlobalOptions({ region: 'europe-west1', maxInstances: 10, memory: '256MiB', timeoutSeconds: 60 });

/**
 * Warm instances for the checkout path (placeOrder, createPaymentSession).
 * 0 = scale to zero (no idle cost). At launch set `CHECKOUT_MIN_INSTANCES=1` in
 * functions/.env and redeploy those two functions: one warm instance each removes
 * the 1–2 s cold start from "Place order" (billed while idle).
 */
const CHECKOUT_MIN_INSTANCES = defineInt('CHECKOUT_MIN_INSTANCES', {
  default: 0,
  description: 'Warm instances of placeOrder and createPaymentSession (0 = scale to zero; 1 at launch)',
});

if (getApps().length === 0) initializeApp();

/** Retried trigger events older than this are dropped (logged) instead of retried again. */
const MAX_EVENT_AGE_MS = 24 * 60 * 60 * 1000;

/** Secret / param value, or undefined when it is not bound or not set. */
function paramValue(param: { value(): string }): string | undefined {
  try {
    return param.value() || undefined;
  } catch {
    return undefined;
  }
}

/** Liveness probe: GET (or HEAD) → `{ ok, service, time }`; any other method → 405. */
export const health = onRequest({ timeoutSeconds: 10 }, (req, res) => {
  res.set('Cache-Control', 'no-store').set('X-Content-Type-Options', 'nosniff');
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.status(405).set('Allow', 'GET, HEAD').send('Method not allowed');
    return;
  }
  res.json({ ok: true, service: 'golden-gift-functions', time: new Date().toISOString() });
});

/**
 * SRS AUTH-3, §5.19: after the app creates `users/{uid}` — referral code, wallet,
 * referral, then the referral's monthly cap and the new user's `joinBonus`
 * credits. Retried on failure (a user without a wallet never self-heals); both
 * steps run once (per uid / per referral), so retries are safe.
 */
export const onUserCreate = onDocumentCreated(
  { document: `${FirestorePaths.users}/{uid}`, retry: true },
  async (event) => {
    const uid = event.params.uid;
    const ageMs = Date.now() - Date.parse(event.time);
    if (ageMs > MAX_EVENT_AGE_MS) {
      logger.error('onUserCreate: event too old, dropped', { uid, eventId: event.id, ageMs });
      return;
    }
    const result = await processNewUser(getFirestore(), uid);
    logger.info('onUserCreate', { uid, ...result });
  },
);

/**
 * SRS AUTH-7: the signed-in user deletes their own account. Returns `{ ok: true }`.
 * Errors: `unauthenticated` (no signed-in user), `internal` (a step failed —
 * nothing is lost, calling again resumes).
 */
export const deleteAccount = onCall({ enforceAppCheck: ENFORCE_APP_CHECK, memory: '512MiB', timeoutSeconds: 300 }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to delete your account.');
  try {
    const result = await deleteUserAccount(
      { db: getFirestore(), auth: getAuth(), bucket: () => getStorage().bucket() },
      uid,
    );
    logger.info('deleteAccount', { uid, ...result });
  } catch (e) {
    logger.error('deleteAccount failed', { uid, error: e instanceof Error ? e.message : String(e) });
    throw new HttpsError('internal', 'Could not delete the account. Please try again.');
  }
  return { ok: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// Phone sign-in (OTPIQ WhatsApp / SMS → Firebase custom token). See auth/otp.ts.
//
// sendOtp and verifyOtp are callable by anyone on the internet — they exist to
// create the session every other guard checks for — so their protection comes from
// the rate limits, a hashed short-lived code and the attempt ceiling.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Secret Manager (`firebase functions:secrets:set OTPIQ_API_KEY`), never the repo.
 * Bound to sendOtp only. The emulator reads it from functions/.secret.local but
 * still never sends unless OTP_REAL_SMS=true (auth/messaging.ts `selectDriver`).
 */
const OTPIQ_API_KEY = defineSecret('OTPIQ_API_KEY');

/**
 * Store-review demo account (SRS AUTH-2, auth/reviewLogin.ts): App Store / Play
 * reviewers sign in with `REVIEW_PHONE` (functions/.env, E.164; empty = off) and
 * the fixed code `REVIEW_OTP_CODE` (Secret Manager: `firebase functions:secrets:set
 * REVIEW_OTP_CODE` — it must exist before deploying sendOtp / verifyOtp; on the
 * emulator it is read from functions/.secret.local). Either empty → off.
 */
const REVIEW_PHONE = defineString('REVIEW_PHONE', {
  default: '',
  description: 'Store-review demo phone number (E.164); empty = no demo login',
});
const REVIEW_OTP_CODE = defineSecret('REVIEW_OTP_CODE');

/** The demo login, or null when it is off. */
function reviewLogin(): ReviewLogin | null {
  return resolveReviewLogin(paramValue(REVIEW_PHONE), paramValue(REVIEW_OTP_CODE));
}

/** Logs unexpected failures and answers `internal`; HttpsErrors pass through. */
async function callable<T>(name: string, uid: string | undefined, fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    logger.error(`${name} failed`, { uid, error: e instanceof Error ? e.message : String(e) });
    throw new HttpsError('internal', 'Something went wrong. Please try again.');
  }
}

/**
 * Data `{ phone, purpose?: 'login' | 'changePhone' }` → `{ expiresInSeconds, phone }` (phone masked, e.g. `+964 750 ••• 4567`).
 * Errors: invalid-argument, unauthenticated (changePhone signed out), already-exists
 * (changePhone to another account's number), resource-exhausted, unavailable.
 */
export const sendOtp = onCall({ enforceAppCheck: ENFORCE_APP_CHECK, secrets: [OTPIQ_API_KEY, REVIEW_OTP_CODE] }, (request) =>
  callable('sendOtp', request.auth?.uid, () =>
    sendOtpCore({ db: getFirestore(), auth: getAuth(), apiKey: paramValue(OTPIQ_API_KEY), review: reviewLogin() }, request.data, {
      uid: request.auth?.uid,
      ip: request.rawRequest?.ip,
    }),
  ),
);

/**
 * Data `{ phone, code }` → `{ token, isNewUser }` (custom token for signInWithCustomToken).
 * The store-review demo number accepts only `REVIEW_OTP_CODE`.
 * Errors: invalid-argument, unauthenticated (wrong / expired code), resource-exhausted
 * (too many wrong codes), permission-denied (disabled account).
 */
export const verifyOtp = onCall({ enforceAppCheck: ENFORCE_APP_CHECK, secrets: [REVIEW_OTP_CODE] }, (request) =>
  callable('verifyOtp', undefined, () =>
    verifyOtpAndSignInCore({ db: getFirestore(), auth: getAuth(), review: reviewLogin() }, request.data),
  ),
);

/**
 * Signed-in user. Data `{ phone, code }` (a `changePhone` code) → `{ phone, countryCode }`.
 * Errors: unauthenticated, invalid-argument, resource-exhausted, already-exists.
 */
export const changePhone = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('changePhone', request.auth?.uid, () =>
    changePhoneCore({ db: getFirestore(), auth: getAuth() }, request.data, request.auth?.uid),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Catalogue (SRS §5.8, §6.4): derived query fields + Algolia search index.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Algolia Application ID — public, so a param (functions/.env), not a secret.
 * Empty until the owner provides it: the trigger then still maintains the
 * derived fields and simply skips Algolia.
 */
const ALGOLIA_APP_ID = defineString('ALGOLIA_APP_ID', {
  default: '',
  description: 'Algolia Application ID (empty = search index sync off)',
});
const ALGOLIA_INDEX_NAME = defineString('ALGOLIA_INDEX_NAME', {
  default: DEFAULT_ALGOLIA_INDEX,
  description: 'Algolia primary index for products (replicas are {name}_newest, _popular, _price_asc, _price_desc)',
});
/** Algolia ADMIN key: Secret Manager (`firebase functions:secrets:set ALGOLIA_ADMIN_KEY`), bound to onProductWrite only. */
const ALGOLIA_ADMIN_KEY = defineSecret('ALGOLIA_ADMIN_KEY');

let algoliaOffLogged = false;

/** The products index, or null (logged once per instance) while Algolia is not configured. */
function productSearchIndex(): AlgoliaIndex | null {
  const resolution = resolveAlgolia({
    appId: paramValue(ALGOLIA_APP_ID),
    adminKey: paramValue(ALGOLIA_ADMIN_KEY),
    indexName: paramValue(ALGOLIA_INDEX_NAME),
  });
  if (resolution.index === null && !algoliaOffLogged) {
    algoliaOffLogged = true;
    logger.debug(`onProductWrite: Algolia not configured (${resolution.reason}) — search index not synced`);
  }
  return resolution.index;
}

/**
 * SRS §7 `onProductWrite`: recompute the derived query fields and
 * `searchKeywords` (written back only when they changed), re-derive the
 * product's reels when something they show changed (Phase 11), then upsert or
 * delete the Algolia record. Retried on failure (a missed sync never
 * self-heals); `syncProduct` is idempotent and its own write-back is a no-op
 * second run.
 */
export const onProductWrite = onDocumentWritten(
  { document: `${FirestorePaths.products}/{id}`, retry: true, secrets: [ALGOLIA_ADMIN_KEY] },
  async (event) => {
    const id = event.params.id;
    const ageMs = Date.now() - Date.parse(event.time);
    if (ageMs > MAX_EVENT_AGE_MS) {
      logger.error('onProductWrite: event too old, dropped', { id, eventId: event.id, ageMs });
      return;
    }
    const result = await syncProduct(
      getFirestore(),
      id,
      event.data?.before.data(),
      event.data?.after.data(),
      productSearchIndex(),
    );
    if (
      result.derivedWritten.length > 0 ||
      result.reelsUpdated > 0 ||
      result.algolia === 'saved' ||
      result.algolia === 'deleted'
    ) {
      logger.info('onProductWrite', { id, ...result });
    } else {
      logger.debug('onProductWrite: nothing to sync', { id, ...result });
    }
  },
);

/**
 * SRS §7 `onReelWrite` (Phase 11): an existing reel gets the derived fields of
 * its product (§6.4a) that differ — none → no write, so its own write-back ends
 * the loop; a deleted reel's video and poster (`reels/{id}.mp4` / `.jpg`) are
 * deleted from Storage (missing files ignored; the Cloud Storage SDK loads only
 * then). Retried; events older than 24 h are dropped. Idempotent.
 */
export const onReelWrite = onDocumentWritten(
  { document: `${FirestorePaths.reels}/{reelId}`, retry: true },
  async (event) => {
    const reelId = event.params.reelId;
    if (!freshEvent('onReelWrite', event, { reelId })) return;
    const result = await syncReel(
      { db: getFirestore(), bucket: () => getStorage().bucket() },
      reelId,
      event.data?.after.data(),
    );
    if (result.derivedWritten.length > 0 || result.filesDeleted === null || result.filesDeleted.length > 0) {
      logger.info('onReelWrite', { reelId, ...result });
    } else {
      logger.debug('onReelWrite: nothing to sync', { reelId });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Admin access (SRS §6.14, §9). See admin/setAdminClaim.ts.
// The very first super admin is created with scripts/create-admin.ts.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Super admin only (claim `admin == true` AND `admins/{caller}.role == 'super'`).
 * Data `{ uid? | email?, grant: boolean, role?: 'super'|'ops'|'content'|'finance', name? }`
 * → `{ uid, email, admin, role, changed }`. Grant merges `admin: true` into the
 * account's claims and upserts `admins/{uid}`; revoke removes the claim (other claims
 * kept) and deletes the doc; both write `admin_audit_log`. The target sees the change
 * after signing out and in (or within the hour, when its ID token refreshes).
 * Errors: unauthenticated, permission-denied, invalid-argument, not-found,
 * failed-precondition (revoking yourself; revoking / demoting the last super admin).
 */
export const setAdminClaim = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('setAdminClaim', request.auth?.uid, () =>
    setAdminClaimCore({ db: getFirestore(), auth: getAuth() }, request.data, {
      uid: request.auth?.uid,
      claims: request.auth?.token,
    }),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Orders & notifications (SRS §4.5, §5.11, §5.12, Phase 6). See orders/*, notifications/*.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Signed-in customer. Data = the app's `PlaceOrderRequest.toMap()`:
 * `{ clientRequestId, addressId, deliveryDate: 'yyyy-MM-dd', deliverySlot, isGift,
 * giftMessage?, hidePrices, paymentMethod, promoCode?, useCredits, useWallet }`
 * → `{ orderId, orderNumber, total, deliveryDate }`. The cart is read from
 * `carts/{uid}/items` and re-priced; one transaction applies the promo code,
 * credits (FIFO) and — for `paymentMethod: 'wallet'` — the balance, creates the
 * order, reserves stock, counts the promo usage, writes the wallet transactions
 * and empties the cart. Same `clientRequestId` again → the same order.
 * Errors: unauthenticated; invalid-argument (data, address, delivery date / slot,
 * payment method); permission-denied (blocked / deleted account);
 * failed-precondition with `details.reason` = cart_changed | city_not_allowed |
 * out_of_stock (+ `productIds`) | min_order | empty_cart | promo_invalid
 * (+ `promoReason`: a PromoRejection name) | insufficient_funds.
 */
export const placeOrder = onCall(
  { enforceAppCheck: ENFORCE_APP_CHECK, memory: '512MiB', timeoutSeconds: 120, minInstances: CHECKOUT_MIN_INSTANCES },
  (request) =>
  callable('placeOrder', request.auth?.uid, async () => {
    const placed = await placeOrderCore(
      { db: getFirestore(), messaging: getMessaging(), bucket: () => getStorage().bucket() },
      request.data,
      request.auth?.uid,
    );
    logger.info('placeOrder', { uid: request.auth?.uid, ...placed });
    return placed;
  }),
);

/**
 * The order's owner, while it is pending / confirmed. Data `{ orderId, reason? }`
 * (reason ≤ 300 characters) → `{ ok: true }`. Sets `cancelledByBuyer` on the order
 * and every line, releases the reserved stock, returns the credits / wallet
 * balance it used and releases its promo usage; the timeline entry and the
 * notification come from onOrderStatusChange.
 * Errors: unauthenticated, invalid-argument, not-found, permission-denied (not the
 * owner), failed-precondition `{ reason: 'not_cancellable' }`.
 */
export const cancelOrder = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('cancelOrder', request.auth?.uid, async () => {
    const result = await cancelOrderCore(getFirestore(), request.data, request.auth?.uid);
    logger.info('cancelOrder', { uid: request.auth?.uid, orderId: (request.data as { orderId?: unknown })?.orderId });
    return result;
  }),
);

/**
 * SRS §7: every `orders/{id}` update whose `status` changed → one
 * `status_history` entry (from statusNote / statusUpdatedBy / statusUpdatedByRole),
 * delivered: COD paid + users.totalSpent, then the referrer's orderBonus (once per
 * referral); cancelledBySeller: stock released; any cancellation: credits / wallet
 * back + promo usage released; refunded: also the paid amount to the balance;
 * then the customer notification. Retried on failure; once per event id
 * (runOnce), so retries are safe. Events older than 24 h are dropped.
 */
export const onOrderStatusChange = onDocumentUpdated(
  { document: `${FirestorePaths.orders}/{id}`, retry: true, timeoutSeconds: 120 },
  async (event) => {
    const orderId = event.params.id;
    const ageMs = Date.now() - Date.parse(event.time);
    if (ageMs > MAX_EVENT_AGE_MS) {
      logger.error('onOrderStatusChange: event too old, dropped', { orderId, eventId: event.id, ageMs });
      return;
    }
    const result = await handleOrderStatusChange(
      { db: getFirestore(), messaging: getMessaging() },
      { eventId: event.id, orderId, before: event.data?.before.data(), after: event.data?.after.data() },
    );
    if (result.handled) logger.info('onOrderStatusChange', { orderId, ...result });
  },
);

/**
 * Admin (claim `admin == true` AND `admins/{uid}.role` ∈ super | ops | content).
 * Data `{ title: { en, ar?, ku? } (≤ 60), body: { en, ar?, ku? } (≤ 180), route?
 * ('/…'), imageUrl? }` → `{ notificationId, sent }`. Writes `notifications/{id}`
 * (userId 'all', sentBy, sentCount), pushes to every opted-in device in its
 * language and logs `notification.broadcast` to admin_audit_log.
 * Errors: unauthenticated, permission-denied, invalid-argument, resource-exhausted
 * (one broadcast per minute).
 */
export const sendBroadcast = onCall(
  // Pages through every user and multicasts: long-running, one at a time per instance.
  { enforceAppCheck: ENFORCE_APP_CHECK, timeoutSeconds: 540, memory: '512MiB', concurrency: 1 },
  (request) =>
  callable('sendBroadcast', request.auth?.uid, async () => {
    const result = await sendBroadcastCore({ db: getFirestore(), messaging: getMessaging() }, request.data, {
      uid: request.auth?.uid,
      claims: request.auth?.token,
    });
    logger.info('sendBroadcast', { uid: request.auth?.uid, ...result });
    return result;
  }),
);

// ─────────────────────────────────────────────────────────────────────────────
// Wallet, credits & users admin (SRS §5.18, §5.19, §9 Users, Phase 7). See wallet/*, admin/*.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Daily 03:00 Iraq time: closes the credit lots whose `expiresAt` has passed and
 * debits what was left of them (`creditExpiry` transactions). Idempotent; a run
 * that stops half-way is finished by the next one. Needs Cloud Scheduler (Blaze).
 */
export const expireCredits = onSchedule(
  { schedule: '0 3 * * *', timeZone: 'Asia/Baghdad', retryCount: 3, timeoutSeconds: 540 },
  async () => {
    const result = await expireCreditLots({ db: getFirestore() }, Date.now());
    logger.info('expireCredits', result);
  },
);

/**
 * Admin (claim `admin == true` AND `admins/{uid}.role` ∈ super | finance).
 * Data `{ uid, bucket: 'balance' | 'credits', amount (signed whole IQD ≠ 0,
 * |amount| ≤ 10,000,000), reason (3–300), requestId? }` → `{ balance, credits, txnId }`.
 * One transaction: wallet, `adminAdjustment` transaction, `wallet.adjust` audit entry.
 * Errors: unauthenticated, permission-denied, invalid-argument, not-found ("No user
 * with that uid."), failed-precondition `{ reason: 'insufficient_funds' }`.
 */
export const adjustWallet = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('adjustWallet', request.auth?.uid, async () => {
    const result = await adjustWalletCore({ db: getFirestore() }, request.data, {
      uid: request.auth?.uid,
      claims: request.auth?.token,
    });
    logger.info('adjustWallet', { by: request.auth?.uid, txnId: result.txnId });
    return result;
  }),
);

/**
 * Admin (claim `admin == true` AND `admins/{uid}.role` ∈ super | ops).
 * Data `{ uid, blocked: boolean, reason? (≤ 300) }` → `{ uid, blocked }`. Sets
 * `users.isBlocked` + a `user.block` / `user.unblock` audit entry, then disables
 * (or re-enables) the Auth account and revokes its refresh tokens.
 * Errors: unauthenticated, permission-denied, invalid-argument, not-found ("No user
 * with that uid."), failed-precondition (own account; an admin account).
 */
export const setUserBlocked = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('setUserBlocked', request.auth?.uid, async () => {
    const result = await setUserBlockedCore({ db: getFirestore(), auth: getAuth() }, request.data, {
      uid: request.auth?.uid,
      claims: request.auth?.token,
    });
    logger.info('setUserBlocked', { by: request.auth?.uid, ...result });
    return result;
  }),
);

// ─────────────────────────────────────────────────────────────────────────────
// Gift cards, special requests, partners & seller orders (SRS §5.17, §5.22,
// §5.25, §9, Phase 8). See giftCards/*, specialRequests/*, partners/*,
// orders/createOrderDoc.ts, orders/updateOrderItems.ts.
// ─────────────────────────────────────────────────────────────────────────────

/** The decoded caller of a dashboard callable (claims included). */
function dashboardCaller(request: { auth?: { uid: string; token: Readonly<Record<string, unknown>> } }): AdminCaller {
  return { uid: request.auth?.uid, claims: request.auth?.token };
}

/** Drops (and logs) retried trigger events older than MAX_EVENT_AGE_MS; true = handle it. */
function freshEvent(name: string, event: { id: string; time: string }, ids: Record<string, string>): boolean {
  const ageMs = Date.now() - Date.parse(event.time);
  if (ageMs <= MAX_EVENT_AGE_MS) return true;
  logger.error(`${name}: event too old, dropped`, { ...ids, eventId: event.id, ageMs });
  return false;
}

/**
 * Signed-in customer. Data = the app's `GiftCardPurchase.toMap()`: `{ clientRequestId,
 * templateId, amount, recipientName, recipientPhone?, recipientEmail?, message (≤ 200),
 * photoUrl?, scheduledAt? (ISO), paymentMethod: 'cashOnDelivery' | 'wallet',
 * addressId? (cash on delivery) }` → `{ orderId, orderNumber, total, deliveryDate }`.
 * One order (`orderType: 'giftCard'`, idempotent per clientRequestId); the card is
 * issued by onGiftCardOrderPaid. Errors: unauthenticated; invalid-argument (data,
 * template / amount, address, payment method); permission-denied (blocked account);
 * failed-precondition `{ reason }` = city_not_allowed | insufficient_funds.
 */
export const purchaseGiftCard = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('purchaseGiftCard', request.auth?.uid, async () => {
    const placed = await purchaseGiftCardCore({ db: getFirestore(), messaging: getMessaging() }, request.data, request.auth?.uid);
    logger.info('purchaseGiftCard', { uid: request.auth?.uid, ...placed });
    return placed;
  }),
);

/**
 * SRS §7 `issueGiftCard`: every write of `orders/{id}` — a `giftCard` order that is
 * paid (created paid, or marked paid on delivery) and has no `giftCardId` → the
 * `gift_cards` doc (unique code, 365-day validity, sent or scheduled), `giftCardId`
 * + `delivered` on the order, notifications; a reversed order (cancelled / returned
 * / refunded) disables its unredeemed card. Retried; once per order (runOnceIf).
 */
export const onGiftCardOrderPaid = onDocumentWritten(
  { document: `${FirestorePaths.orders}/{id}`, retry: true },
  async (event) => {
    const orderId = event.params.id;
    if (!freshEvent('onGiftCardOrderPaid', event, { orderId })) return;
    const after = event.data?.after.data();
    if (after?.orderType !== 'giftCard') return;
    const result = await handleGiftCardOrderWrite(
      { db: getFirestore(), messaging: getMessaging(), recipients: authRecipientLookup(getAuth()) },
      { eventId: event.id, orderId, before: event.data?.before.data(), after },
    );
    if (result.action !== 'skipped') logger.info('onGiftCardOrderPaid', { orderId, ...result });
  },
);

/**
 * Every 30 minutes: scheduled cards whose day has come are sent (+ notifications);
 * cards past `expiresAt` become `expired`. Idempotent. Needs Cloud Scheduler (Blaze).
 */
export const sendScheduledGiftCards = onSchedule(
  { schedule: 'every 30 minutes', timeZone: 'Asia/Baghdad', retryCount: 3, timeoutSeconds: 540 },
  async () => {
    const deps = { db: getFirestore(), messaging: getMessaging(), recipients: authRecipientLookup(getAuth()) };
    const now = Date.now();
    const sent = await sendDueGiftCards(deps, now);
    const expired = await expireGiftCards(deps, now);
    if (sent.sent.length + expired.expired.length > 0) {
      logger.info('sendScheduledGiftCards', { sent: sent.sent.length, expired: expired.expired.length });
    }
  },
);

/**
 * After the app creates `users/{uid}`: gift cards sent to that phone / email before
 * the account existed get `recipientUid` (they appear in My Gift Cards) and the
 * recipient is notified. Retried; linking re-checks `recipientUid == null`.
 */
export const linkReceivedGiftCards = onDocumentCreated(
  { document: `${FirestorePaths.users}/{uid}`, retry: true },
  async (event) => {
    const uid = event.params.uid;
    if (!freshEvent('linkReceivedGiftCards', event, { uid })) return;
    const result = await linkGiftCardsToNewUser(
      { db: getFirestore(), messaging: getMessaging(), recipients: authRecipientLookup(getAuth()) },
      uid,
      event.data?.data(),
    );
    if (result.linked.length > 0) logger.info('linkReceivedGiftCards', { uid, linked: result.linked });
  },
);

/**
 * Signed-in user. Data `{ code }` (12 characters) → `{ giftCardId, amount, credits }`:
 * the card's balance becomes wallet credits (giftCardRedeem transaction + credit lot
 * expiring with the card), the card `redeemed`. Errors: unauthenticated,
 * invalid-argument, not-found ("No gift card matches this code."), failed-precondition
 * `{ reason: expired | redeemed | disabled | not_sent }`, resource-exhausted (10 wrong
 * codes / user / hour).
 */
export const redeemGiftCard = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('redeemGiftCard', request.auth?.uid, async () => {
    const result = await redeemGiftCardCore({ db: getFirestore() }, request.data, request.auth?.uid);
    logger.info('redeemGiftCard', { uid: request.auth?.uid, giftCardId: result.giftCardId, amount: result.amount });
    return result;
  }),
);

/**
 * Admin (claim + `admins` role super | ops | finance). Data `{ templateId, amount,
 * recipientName, recipientPhone?, recipientEmail?, message?, expiresAt? (ISO) }` →
 * `{ giftCardId, code }`. A `sent` card without an order + `giftCard.issue` audit entry.
 * Amount by the template; super admins any 1,000–10,000,000 IQD. Errors:
 * unauthenticated, permission-denied, invalid-argument, not-found ("Gift card template not found.").
 */
export const adminIssueGiftCard = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('adminIssueGiftCard', request.auth?.uid, async () => {
    const result = await adminIssueGiftCardCore(
      { db: getFirestore(), messaging: getMessaging(), recipients: authRecipientLookup(getAuth()) },
      request.data,
      dashboardCaller(request),
    );
    logger.info('adminIssueGiftCard', { by: request.auth?.uid, giftCardId: result.giftCardId });
    return result;
  }),
);

/**
 * Signed-in customer. Data = `AcceptQuoteRequest.toMap()`: `{ requestId, clientRequestId,
 * addressId, deliveryDate: 'yyyy-MM-dd', deliverySlot, paymentMethod }` →
 * `{ orderId, orderNumber, total, deliveryDate }`. One transaction: the order
 * (`orderType: 'specialRequest'`, quoteAmount + the city's delivery fee), the request
 * `accepted` + `orderId`, a "Quote accepted" thread message. Errors: unauthenticated;
 * invalid-argument; not-found ("Special request not found."); permission-denied;
 * failed-precondition `{ reason }` = quote_unavailable | city_not_allowed | insufficient_funds.
 */
export const acceptQuote = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('acceptQuote', request.auth?.uid, async () => {
    const placed = await acceptQuoteCore({ db: getFirestore(), messaging: getMessaging() }, request.data, request.auth?.uid);
    logger.info('acceptQuote', { uid: request.auth?.uid, ...placed });
    return placed;
  }),
);

/** A new admin message in a special-request thread → the customer is notified (system / quote messages skipped). */
export const onSpecialRequestMessage = onDocumentCreated(
  { document: `${FirestorePaths.specialRequests}/{id}/${FirestorePaths.messages}/{messageId}`, retry: true },
  async (event) => {
    const requestId = event.params.id;
    if (!freshEvent('onSpecialRequestMessage', event, { requestId })) return;
    const result = await handleSpecialRequestMessage(
      { db: getFirestore(), messaging: getMessaging() },
      { requestId, messageId: event.params.messageId, message: event.data?.data() },
    );
    if (result.notified) logger.info('onSpecialRequestMessage', { requestId, ...result });
  },
);

/** A special request became `quoted` → "Your quote is ready" to the customer. */
export const onSpecialRequestUpdate = onDocumentUpdated(
  { document: `${FirestorePaths.specialRequests}/{id}`, retry: true },
  async (event) => {
    const requestId = event.params.id;
    if (!freshEvent('onSpecialRequestUpdate', event, { requestId })) return;
    const result = await handleSpecialRequestUpdate(
      { db: getFirestore(), messaging: getMessaging() },
      { eventId: event.id, requestId, before: event.data?.before.data(), after: event.data?.after.data() },
    );
    if (result.notified) logger.info('onSpecialRequestUpdate', { requestId, ...result });
  },
);

/**
 * Signed-in customer. Data = `PartnerApplication.toMap()`: `{ storeName, ownerName,
 * phone (E.164), city, category, instagram?, samplePhotos (≤ 5) }` → `{ storeId }`.
 * Creates `stores/{id}` (pendingApproval) + `stores/{id}/private/application`.
 * Errors: unauthenticated, invalid-argument, already-exists (one store per owner),
 * permission-denied (blocked account).
 */
export const submitPartnerApplication = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('submitPartnerApplication', request.auth?.uid, async () => {
    const result = await submitPartnerApplicationCore(getFirestore(), request.data, request.auth?.uid);
    logger.info('submitPartnerApplication', { uid: request.auth?.uid, ...result });
    return result;
  }),
);

/**
 * Admin (super | ops). Data `{ storeId, decision: 'approve' | 'reject',
 * commissionPercent? (0–50, approve), reason? (3–500, reject) }` → `{ storeId, status }`.
 * Approve: store active + commission, `admins/{owner}` role seller, claim
 * `seller: storeId` (never `admin`). Reject: application archived, store doc deleted.
 * Audit + owner notification. Errors: unauthenticated, permission-denied,
 * invalid-argument, not-found ("Store not found."), failed-precondition.
 */
export const reviewPartner = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('reviewPartner', request.auth?.uid, async () => {
    const result = await reviewPartnerCore(
      { db: getFirestore(), auth: getAuth(), messaging: getMessaging() },
      request.data,
      dashboardCaller(request),
    );
    logger.info('reviewPartner', { by: request.auth?.uid, ...result });
    return result;
  }),
);

/**
 * Admin (super | ops). Data `{ storeId, status: 'active' | 'suspended', reason (3–500) }`
 * → `{ storeId, status }`. Audit + owner notification. Errors: unauthenticated,
 * permission-denied, invalid-argument, not-found ("Store not found."), failed-precondition
 * (a pending application).
 */
export const setStoreStatus = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('setStoreStatus', request.auth?.uid, async () => {
    const result = await setStoreStatusCore(
      { db: getFirestore(), auth: getAuth(), messaging: getMessaging() },
      request.data,
      dashboardCaller(request),
    );
    logger.info('setStoreStatus', { by: request.auth?.uid, ...result });
    return result;
  }),
);

/**
 * Seller (claim `seller == storeId`, store active). Data `{ orderId, status, note? }`
 * → `{ status }` (the order's derived status). Moves the seller's own lines that may
 * go to `status`; the order becomes the least advanced line status, which
 * onOrderStatusChange records and notifies. Errors: unauthenticated,
 * permission-denied, invalid-argument (incl. `refunded`), not-found ("Order not
 * found."), failed-precondition `{ reason: 'not_allowed' }`.
 */
export const updateOrderItems = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('updateOrderItems', request.auth?.uid, async () => {
    const result = await updateOrderItemsCore({ db: getFirestore(), messaging: getMessaging() }, request.data, dashboardCaller(request));
    logger.info('updateOrderItems', { by: request.auth?.uid, status: result.status, moved: result.moved, cancelledLines: result.cancelledLines });
    return { status: result.status };
  }),
);

// ─────────────────────────────────────────────────────────────────────────────
// AI gift search, Secret Santa, reviews & online payments (SRS §5.6, §5.16,
// §5.18, §5.26, Phase 9). See ai/*, secretSanta/*, reviews/*, payments/*.
// ─────────────────────────────────────────────────────────────────────────────

/** Gemini model of aiGiftSearch (functions/.env). */
const GEMINI_MODEL = defineString('GEMINI_MODEL', {
  default: DEFAULT_GEMINI_MODEL,
  description: 'Gemini model for AI gift search (Vertex AI, location global)',
});

let giftModel: { name: string; model: GiftSearchModel } | null = null;

/**
 * Vertex AI with the function's service account (enable the Vertex AI API on the
 * project) — or the Gemini Developer API when a `GEMINI_API_KEY` secret is bound:
 * create it (`firebase functions:secrets:set GEMINI_API_KEY`) and add
 * `secrets: ['GEMINI_API_KEY']` to aiGiftSearch's options.
 */
function aiGiftModel(): GiftSearchModel {
  const model = paramValue(GEMINI_MODEL) ?? DEFAULT_GEMINI_MODEL;
  const apiKey = process.env.GEMINI_API_KEY || undefined;
  const name = `${apiKey === undefined ? 'vertex' : 'key'}:${model}`;
  if (giftModel === null || giftModel.name !== name) giftModel = { name, model: geminiModel({ model, apiKey }) };
  return giftModel.model;
}

let categories: (() => Promise<import('./ai/giftSearchPrompts').CategoryInfo[]>) | null = null;

/**
 * Guests and customers. Data `{ query (1–300), locale: 'en' | 'ar' | 'ckb', budgetMax? }`
 * → `{ searchId, results: [{ productId, reason }] }` (≤ 12, best first, reason = one
 * line in the customer's language). Logs `ai_searches/{searchId}`. Errors:
 * invalid-argument; resource-exhausted (20 / user / day, 10 / IP / day for guests,
 * Iraq day); unavailable (Gemini failed or gave nothing usable — the app falls back
 * to keyword search).
 */
export const aiGiftSearch = onCall(
  // Waits on two Gemini calls; fewer requests per instance keeps memory in check.
  { enforceAppCheck: ENFORCE_APP_CHECK, timeoutSeconds: 60, memory: '512MiB', concurrency: 20 },
  (request) =>
    callable('aiGiftSearch', request.auth?.uid, async () => {
      categories ??= cachedCategories(getFirestore());
      const result = await aiGiftSearchCore(
        { db: getFirestore(), model: aiGiftModel(), categories },
        request.data,
        { uid: request.auth?.uid, ip: request.rawRequest?.ip },
      );
      logger.info('aiGiftSearch', { uid: request.auth?.uid, searchId: result.searchId, results: result.results.length });
      return result;
    }),
);

/**
 * Signed-in user. Data `{ inviteCode (8), name (1–60), wishlistNote? (≤ 300) }` →
 * `{ groupId }`; already a member → the same answer. Errors: unauthenticated,
 * invalid-argument, not-found ("No Secret Santa group matches this invite code."),
 * permission-denied (blocked account), failed-precondition `{ reason: drawn | full }`,
 * resource-exhausted (10 wrong codes per user per rolling hour).
 */
export const joinSecretSanta = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('joinSecretSanta', request.auth?.uid, async () => {
    const result = await joinSecretSantaCore(getFirestore(), request.data, request.auth?.uid);
    logger.info('joinSecretSanta', { uid: request.auth?.uid, ...result });
    return result;
  }),
);

/**
 * The group's organiser. Data `{ groupId }` → `{ ok: true }`. One transaction: a
 * random draw with nobody drawing themselves or someone on their `exclusions`,
 * `assignments/{giverUid}` for every member, group `drawn` + `drawnAt`; then every
 * member is notified (`secretSantaDraw`, `/secret-santa/{id}`). Errors:
 * unauthenticated, invalid-argument, not-found ("Secret Santa group not found."),
 * permission-denied (not the organiser), failed-precondition
 * `{ reason: drawn | too_few | full | impossible }`.
 */
export const drawSecretSanta = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, (request) =>
  callable('drawSecretSanta', request.auth?.uid, async () => {
    const data = request.data as { groupId?: unknown } | undefined;
    const result = await drawSecretSantaCore({ db: getFirestore(), messaging: getMessaging() }, request.data, request.auth?.uid);
    logger.info('drawSecretSanta', { uid: request.auth?.uid, groupId: data?.groupId });
    return result;
  }),
);

/**
 * A member edited their wish note after the draw → the assignment of whoever drew
 * them (`assigneeUid == member`) gets the current note (secretSanta/wishNoteSync.ts).
 * Retried; idempotent (re-reads the member, writes only a difference).
 */
export const onSecretSantaMemberUpdate = onDocumentUpdated(
  { document: `${FirestorePaths.secretSantaGroups}/{groupId}/${FirestorePaths.members}/{memberUid}`, retry: true },
  async (event) => {
    const { groupId, memberUid } = event.params;
    if (!freshEvent('onSecretSantaMemberUpdate', event, { groupId, memberUid })) return;
    const result = await syncWishNoteToAssignment(getFirestore(), {
      groupId,
      memberUid,
      before: event.data?.before.data(),
      after: event.data?.after.data(),
    });
    if (result.synced) logger.info('onSecretSantaMemberUpdate', { groupId, memberUid, giverUid: result.giverUid });
  },
);

/**
 * SRS §7 `onReviewWrite`: a review appeared / disappeared or its approval, rating or
 * store changed → the product's and the store's `ratingAvg` / `ratingCount` are
 * recomputed from approved reviews (aggregate queries; idempotent). Retried;
 * events older than 24 h are dropped.
 */
export const onReviewWrite = onDocumentWritten(
  { document: `${FirestorePaths.products}/{productId}/${FirestorePaths.reviews}/{reviewId}`, retry: true },
  async (event) => {
    const { productId, reviewId } = event.params;
    if (!freshEvent('onReviewWrite', event, { productId, reviewId })) return;
    const result = await handleReviewWrite(getFirestore(), {
      productId,
      reviewId,
      before: event.data?.before.data(),
      after: event.data?.after.data(),
    });
    if (result.recomputed) logger.info('onReviewWrite', { productId, reviewId, ...result });
  },
);

/**
 * ZainCash (PROVISIONAL first gateway, SRS §12 item 4). Params in functions/.env:
 * `ZAINCASH_ENV` (test | prod), `ZAINCASH_MERCHANT_ID`, `ZAINCASH_MSISDN` (the
 * merchant wallet), `ZAINCASH_RETURN_URL` (optional, default this project's
 * zainCashReturn URL); secret `ZAINCASH_SECRET` (Secret Manager). `test` with no
 * merchant id uses ZainCash's public sandbox merchant (payments/zainCash.ts).
 */
const ZAINCASH_ENV = defineString('ZAINCASH_ENV', { default: 'test', description: 'ZainCash environment: test | prod' });
const ZAINCASH_MERCHANT_ID = defineString('ZAINCASH_MERCHANT_ID', {
  default: '',
  description: 'ZainCash merchant id (empty + test = the public sandbox merchant)',
});
const ZAINCASH_MSISDN = defineString('ZAINCASH_MSISDN', { default: '', description: 'ZainCash merchant wallet number, e.g. 9647…' });
const ZAINCASH_RETURN_URL = defineString('ZAINCASH_RETURN_URL', {
  default: '',
  description: 'Public URL of zainCashReturn (empty = derived from the project)',
});
/** Merchant secret: Secret Manager (`firebase functions:secrets:set ZAINCASH_SECRET`). */
const ZAINCASH_SECRET = defineSecret('ZAINCASH_SECRET');

let gatewayOffLogged = false;
let gatewayTestLogged = false;

/** The configured gateway, or null (logged once per instance). */
function paymentGateway(): PaymentGateway | null {
  const resolved = resolveZainCashConfig({
    env: paramValue(ZAINCASH_ENV),
    merchantId: paramValue(ZAINCASH_MERCHANT_ID),
    msisdn: paramValue(ZAINCASH_MSISDN),
    secret: paramValue(ZAINCASH_SECRET),
  });
  if (resolved.config === null) {
    if (!gatewayOffLogged) logger.error(`ZainCash not configured: ${resolved.reason}`);
    gatewayOffLogged = true;
    return null;
  }
  if (resolved.config.env === 'test' && process.env.FUNCTIONS_EMULATOR !== 'true' && !gatewayTestLogged) {
    // Sandbox payments mark REAL orders paid: fine while testing, never at launch.
    gatewayTestLogged = true;
    logger.error('ZainCash is in TEST mode (sandbox money): set ZAINCASH_ENV=prod with the merchant credentials before launch');
  }
  return zainCashGateway(resolved.config);
}

function zainCashReturnUrl(): string {
  const configured = paramValue(ZAINCASH_RETURN_URL);
  if (configured) return configured.replace(/\/+$/, '');
  const project = process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? 'goldengift-iq';
  if (process.env.FUNCTIONS_EMULATOR === 'true') return `http://127.0.0.1:5001/${project}/europe-west1/zainCashReturn`;
  return `https://europe-west1-${project}.cloudfunctions.net/zainCashReturn`;
}

/**
 * Signed-in customer. Data `{ purpose: 'order', orderId }` (a pending ZainCash order
 * before its `paymentDueBy`) or `{ purpose: 'topUp', amount }` (5,000–1,000,000 IQD)
 * → `{ sessionId, payUrl, expiresAt }`. Errors: unauthenticated, invalid-argument,
 * not-found, permission-denied, failed-precondition `{ reason: gateway_disabled |
 * not_payable | already_paid | expired }`, unavailable (gateway not configured / down).
 */
export const createPaymentSession = onCall(
  { enforceAppCheck: ENFORCE_APP_CHECK, secrets: [ZAINCASH_SECRET], minInstances: CHECKOUT_MIN_INSTANCES },
  (request) =>
  callable('createPaymentSession', request.auth?.uid, async () => {
    const result = await createPaymentSessionCore(
      { db: getFirestore(), gateway: paymentGateway(), returnUrl: zainCashReturnUrl() },
      request.data,
      request.auth?.uid,
    );
    logger.info('createPaymentSession', { uid: request.auth?.uid, sessionId: result.sessionId });
    return result;
  }),
);

/**
 * The session's owner ("I've paid — check status"). Data `{ sessionId }` →
 * `{ status: pending | paid | failed | expired }`: a pending session is checked with
 * ZainCash (server to server) and a final answer settled exactly like the redirect /
 * expiry job (payments/checkPaymentStatus.ts). 6 checks per session per 5 minutes.
 * Errors: unauthenticated, invalid-argument, not-found ("Payment session not found."),
 * permission-denied, resource-exhausted, unavailable (gateway not configured / down).
 */
export const checkPaymentStatus = onCall({ enforceAppCheck: ENFORCE_APP_CHECK, secrets: [ZAINCASH_SECRET] }, (request) =>
  callable('checkPaymentStatus', request.auth?.uid, async () => {
    const result = await checkPaymentStatusCore(
      { db: getFirestore(), messaging: getMessaging(), gateway: paymentGateway() },
      request.data,
      request.auth?.uid,
    );
    logger.info('checkPaymentStatus', { uid: request.auth?.uid, status: result.status });
    return result;
  }),
);

/**
 * GET `?sid=&token=` — where ZainCash's redirect sends the customer's browser after
 * paying (HEAD answers without settling; any other method → 405). Verifies the
 * token, settles the session (order paid / cancelled, top-up credited — once) and
 * answers a page that opens `goldengift://payment?sid=…&status=paid|failed|pending|expired|error`.
 * Nothing from the request is echoed unescaped and the page links nowhere else
 * (no open redirect); it cannot be framed, sniffed or cached.
 */
export const zainCashReturn = onRequest({ secrets: [ZAINCASH_SECRET], timeoutSeconds: 30 }, async (req, res) => {
  res
    .set('Cache-Control', 'no-store')
    .set('Referrer-Policy', 'no-referrer')
    .set('X-Content-Type-Options', 'nosniff')
    .set('X-Frame-Options', 'DENY');
  if (req.method === 'HEAD') {
    res.status(200).end();
    return;
  }
  if (req.method !== 'GET') {
    res.status(405).set('Allow', 'GET, HEAD').set('Content-Type', 'text/plain; charset=utf-8').send('Method not allowed');
    return;
  }
  try {
    const out = await handleZainCashReturn(
      { db: getFirestore(), messaging: getMessaging(), gateway: paymentGateway() },
      req.query as Record<string, unknown>,
    );
    res
      .status(out.httpStatus)
      .set('Content-Type', 'text/html; charset=utf-8')
      .set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
      .send(out.html);
  } catch (e) {
    logger.error('zainCashReturn failed', { error: e instanceof Error ? e.message : String(e) });
    res.status(500).set('Content-Type', 'text/plain; charset=utf-8').send('Please go back to the Golden Gift app.');
  }
});

/**
 * Every 15 minutes: pending payment sessions past `expiresAt` are checked with the
 * gateway (paid → settled) or expired; unpaid ZainCash orders past `paymentDueBy`
 * are cancelled (`payment_expired`: stock, promo and credits back). Idempotent.
 * Needs Cloud Scheduler (Blaze).
 */
export const expirePaymentSessions = onSchedule(
  { schedule: 'every 15 minutes', timeZone: 'Asia/Baghdad', retryCount: 3, timeoutSeconds: 540, secrets: [ZAINCASH_SECRET] },
  async () => {
    const result = await expirePaymentSessionsCore(
      { db: getFirestore(), messaging: getMessaging(), gateway: paymentGateway() },
      Date.now(),
    );
    const total = Object.values(result).reduce((n, list) => n + list.length, 0);
    if (total > 0) logger.info('expirePaymentSessions', result);
  },
);
