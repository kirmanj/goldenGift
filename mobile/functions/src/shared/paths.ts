/**
 * Firestore collection names (SRS §6).
 *
 * MUST mirror `FirestorePaths` in `mobile/lib/core/constants/firestore_paths.dart`
 * (same keys, same values); the admin dashboard re-exports that Dart file
 * (`adminDashboard/lib/core/constants/firestore_paths.dart`), so it cannot diverge.
 * `test/paths.test.ts` fails when they do. If you add a collection, update the
 * Dart file, this file and the SRS data model.
 */
export const FirestorePaths = {
  // ── Top-level collections ──
  users: 'users',
  stores: 'stores',
  products: 'products',
  categories: 'categories',
  orders: 'orders',
  carts: 'carts',
  wishlists: 'wishlists',
  banners: 'banners',
  promoCodes: 'promo_codes',
  giftCardTemplates: 'gift_card_templates',
  giftCards: 'gift_cards',
  wallets: 'wallets',
  referrals: 'referrals',
  specialRequests: 'special_requests',
  secretSantaGroups: 'secret_santa_groups',
  notifications: 'notifications',
  reviews: 'reviews',
  aiSearches: 'ai_searches',
  appSettings: 'app_settings',
  /** Product videos of the Reels tab (SRS §5.27, §6.4a, Phase 11). */
  reels: 'reels',

  // ── Admin / functions only ──
  admins: 'admins',
  adminAuditLog: 'admin_audit_log',
  /** Idempotency markers written by Cloud Functions (one doc per processed event key). */
  functionRuns: 'function_runs',
  /** One active phone code per phone and purpose (`sendOtp` / `verifyOtp`). */
  otpCodes: 'otp_codes',
  /** Rate-limit windows for OTP sending. */
  otpThrottle: 'otp_throttle',
  /** Monthly order-number sequences (`counters/orders-{YYMM}`, functions only — placeOrder, Phase 6). */
  counters: 'counters',
  /**
   * `payment_sessions/{id}` — one online payment (an order or a wallet top-up) at a
   * gateway (`createPaymentSession`, `zainCashReturn`, `expirePaymentSessions`).
   * Functions write; the owner reads their own.
   */
  paymentSessions: 'payment_sessions',

  // ── Subcollections ──
  addresses: 'addresses',
  savedCards: 'saved_cards',
  items: 'items',
  transactions: 'transactions',
  statusHistory: 'status_history',
  members: 'members',
  messages: 'messages',
  subcategories: 'subcategories',
  /** `promo_codes/{code}/usages/{uid}` = `{ count }` (placeOrder only). */
  usages: 'usages',
  /**
   * `wallets/{uid}/credit_lots/{id}` — one per credits top-up (referral, gift card,
   * refund, admin) with its own expiry; spent FIFO, expired by `expireCredits`.
   * Functions only (owner / admin read).
   */
  creditLots: 'credit_lots',
  /** `secret_santa_groups/{id}/assignments/{giverUid}` (drawSecretSanta only; readable by that giver). */
  assignments: 'assignments',
  /** `stores/{id}/private/{doc}` — application + payout details (owner + admins). */
  storePrivate: 'private',
} as const;

export type CollectionKey = keyof typeof FirestorePaths;

/**
 * EMULATOR ONLY — must never exist in production.
 *
 * `otp_debug/{phoneDigits}` = `{ code, purpose, at }`: the plain one-time code,
 * written by `sendOtp` only when it runs on the Functions emulator with the `log`
 * messaging driver AND the Admin SDK points at the Firestore emulator, so
 * automated end-to-end tests can read the code back (see `auth/messaging.ts`).
 *
 * Deliberately NOT in `FirestorePaths` and NOT in the Dart `FirestorePaths`:
 * no app or dashboard code may ever read it. Production rules deny it outright.
 */
export const OTP_DEBUG_COLLECTION_EMULATOR_ONLY = 'otp_debug';
