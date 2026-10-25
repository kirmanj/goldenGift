/// Shared enums & constants. The string values are what Firestore stores.
/// MUST stay identical to adminDashboard/lib/core/constants/admin_constants.dart.
class AppConstants {
  AppConstants._();

  static const String appName = 'Golden Gift';
  static const String currencyCode = 'IQD';
  static const String defaultCountryCode = '+964';
  static const String defaultLocale = 'en';
  static const List<String> supportedLocales = ['en', 'ar', 'ckb'];

  /// Cities served (SRS §4.3). Admin can extend via app_settings/cities.
  static const List<String> defaultCities = [
    'Erbil', 'Sulaymaniyah', 'Duhok', 'Baghdad', 'Basra', 'Mosul', 'Kirkuk',
  ];
}

enum OrderStatus {
  pending, confirmed, preparing, readyForDelivery, outForDelivery,
  delivered, cancelledByBuyer, cancelledBySeller, returned, refunded;
}

enum PaymentMethod { cashOnDelivery, wallet, card, fastPay, zainCash }

enum PaymentStatus { pending, paid, failed, refunded }

/// Product customization option types (SRS §5.9).
enum OptionType {
  imageVariant,   // tiles with an image + label (Frame Color, Size)
  textVariant,    // pill chips (30x30cm)
  colorSwatch,    // round color dots (Text Color)
  text,           // free text with max length (Text 1, Name)
  longText,       // multi-line (Notes)
  date,           // date picker
  photoUpload,    // 1..N photo slots
  quantity,
}

enum ProductAvailability { sameDay, preparationDays, outOfStock }

enum ReferralStatus { pending, completed, cancelled }

enum SpecialRequestStatus { submitted, inReview, quoted, accepted, rejected, completed }

enum WalletTxnType { topUp, orderPayment, refund, referralCredit, giftCardRedeem, adminAdjustment, creditExpiry }

enum UserRole { customer, seller, admin }

/// Category kind (SRS §6.3): occasions can be promoted around holidays.
enum CategoryType { occasion, productType }

/// Where a banner is shown on Home (SRS §5.4, §6.8).
enum BannerPlacement { homeTop, homeMid1, homeMid2, homeBottom }

/// What tapping a banner does (SRS §6.8).
enum BannerActionType { category, product, url, route }

/// Partner store lifecycle (SRS §6.2, §5.25).
enum StoreStatus { pendingApproval, active, suspended }

/// Who a product is a gift for (SRS §5.8a, `products.giftFor[]`): him, her,
/// companies & organizations.
enum GiftAudience { men, women, companies }
