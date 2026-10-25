/// Centralized Firestore collection and document path helpers.
/// Keep in sync with adminDashboard/lib/core/constants/firestore_paths.dart
/// and SRS §6.
class FirestorePaths {
  FirestorePaths._();

  // ── Top-level collections ──
  static const String users = 'users';
  static const String stores = 'stores';
  static const String products = 'products';
  static const String categories = 'categories';
  static const String orders = 'orders';
  static const String carts = 'carts';
  static const String wishlists = 'wishlists';
  static const String banners = 'banners';
  static const String promoCodes = 'promo_codes';
  static const String giftCardTemplates = 'gift_card_templates';
  static const String giftCards = 'gift_cards';
  static const String wallets = 'wallets';
  static const String referrals = 'referrals';
  static const String specialRequests = 'special_requests';
  static const String secretSantaGroups = 'secret_santa_groups';
  static const String notifications = 'notifications';
  static const String reviews = 'reviews';
  static const String aiSearches = 'ai_searches';
  static const String appSettings = 'app_settings';
  /// Product videos of the Reels tab (SRS §5.27, §6.4a, Phase 11).
  static const String reels = 'reels';

  // ── Admin / functions only ──
  static const String admins = 'admins';
  static const String adminAuditLog = 'admin_audit_log';
  /// Idempotency markers written by Cloud Functions (one doc per processed event key).
  static const String functionRuns = 'function_runs';
  /// One active phone code per phone and purpose (`sendOtp` / `verifyOtp`).
  static const String otpCodes = 'otp_codes';
  /// Rate-limit windows for OTP sending.
  static const String otpThrottle = 'otp_throttle';
  /// Monthly order-number sequences (`counters/orders-{YYMM}`, functions only).
  static const String counters = 'counters';
  /// Online-payment sessions (`createPaymentSession`, Phase 9): functions write,
  /// the owner reads their own (SRS §6.14).
  static const String paymentSessions = 'payment_sessions';

  // ── Subcollections ──
  static const String addresses = 'addresses';
  static const String savedCards = 'saved_cards';
  static const String items = 'items';
  static const String transactions = 'transactions';
  static const String statusHistory = 'status_history';
  static const String members = 'members';
  static const String messages = 'messages';
  static const String subcategories = 'subcategories';
  /// `promo_codes/{code}/usages/{uid}` = `{count}` (placeOrder only).
  static const String usages = 'usages';
  /// `wallets/{uid}/credit_lots/{id}` — credits with their own expiry (functions only).
  static const String creditLots = 'credit_lots';
  /// `secret_santa_groups/{id}/assignments/{giverUid}` (drawSecretSanta only).
  static const String assignments = 'assignments';
  /// `stores/{id}/private/{doc}` — application + payout details.
  static const String storePrivate = 'private';

  // ── Document paths ──
  static String userDoc(String uid) => '$users/$uid';
  static String userAddresses(String uid) => '$users/$uid/$addresses';
  static String userSavedCards(String uid) => '$users/$uid/$savedCards';
  static String cartItems(String uid) => '$carts/$uid/$items';
  static String wishlistItems(String uid) => '$wishlists/$uid/$items';
  static String walletDoc(String uid) => '$wallets/$uid';
  static String walletTxns(String uid) => '$wallets/$uid/$transactions';
  static String storeDoc(String id) => '$stores/$id';
  static String productDoc(String id) => '$products/$id';
  static String productReviews(String id) => '$products/$id/$reviews';
  static String categoryDoc(String id) => '$categories/$id';
  static String categorySubs(String id) => '$categories/$id/$subcategories';
  static String orderDoc(String id) => '$orders/$id';
  static String orderHistory(String id) => '$orders/$id/$statusHistory';
  static String giftCardDoc(String id) => '$giftCards/$id';
  static String specialRequestDoc(String id) => '$specialRequests/$id';
  static String specialRequestMessages(String id) =>
      '$specialRequests/$id/$messages';
  static String secretSantaDoc(String id) => '$secretSantaGroups/$id';
  static String secretSantaMembers(String id) =>
      '$secretSantaGroups/$id/$members';
  static String settingsDoc(String id) => '$appSettings/$id';
  static String promoUsageDoc(String code, String uid) => '$promoCodes/$code/$usages/$uid';
  static String secretSantaAssignment(String groupId, String giverUid) =>
      '$secretSantaGroups/$groupId/$assignments/$giverUid';
  static String storeApplication(String storeId) => '$stores/$storeId/$storePrivate/application';
  static String paymentSessionDoc(String id) => '$paymentSessions/$id';
  static String reelDoc(String id) => '$reels/$id';
}
