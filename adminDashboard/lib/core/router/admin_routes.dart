/// Dashboard paths (SRS §9). Flat list, same convention as the app.
class AdminRoutes {
  AdminRoutes._();
  static const dashboard = '/';
  static const login = '/login';
  static const orders = '/orders';
  static const products = '/products';
  static const productNew = '/products/new';

  /// Bulk CSV import (SRS §9 Products). Registered before [productEdit].
  static const productImport = '/products/import';
  static const productEdit = '/products/:id';
  static const categories = '/categories';
  static const stores = '/stores';
  static const storeDetail = '/stores/:id';

  /// A seller's own store profile (SRS §9 "Seller view").
  static const storeProfile = '/store-profile';
  static const users = '/users';
  static const userDetail = '/users/:id';
  static const banners = '/banners';

  /// Product videos of the app's Reels tab (SRS §9 Reels, Phase 11).
  static const reels = '/reels';
  static const promoCodes = '/promo-codes';
  static const giftCards = '/gift-cards';
  static const specialRequests = '/special-requests';
  static const specialRequestDetail = '/special-requests/:id';
  static const referrals = '/referrals';
  static const reviews = '/reviews';
  static const secretSanta = '/secret-santa';
  static const secretSantaDetail = '/secret-santa/:id';
  static const notifications = '/notifications';
  static const settings = '/settings';
  static const auditLog = '/audit-log';

  static String product(String id) => '/products/$id';
  static String user(String uid) => '/users/$uid';
  static String store(String id) => '/stores/$id';
  static String specialRequest(String id) => '/special-requests/$id';
  static String secretSantaGroup(String id) => '/secret-santa/$id';
}
