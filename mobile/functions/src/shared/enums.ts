/**
 * Shared enums — the string values Firestore stores (SRS §6.15).
 *
 * MUST stay identical (same names, same values, same order) to the Dart enums in
 * `mobile/lib/core/constants/app_constants.dart`, which
 * `adminDashboard/lib/core/constants/admin_constants.dart` re-exports.
 * `test/enums.test.ts` fails when they diverge.
 *
 * Each enum is a readonly tuple (iterate / validate at runtime) plus a union
 * type of the same name: `OrderStatus` the value, `OrderStatus` the type.
 */

export const OrderStatus = [
  'pending',
  'confirmed',
  'preparing',
  'readyForDelivery',
  'outForDelivery',
  'delivered',
  'cancelledByBuyer',
  'cancelledBySeller',
  'returned',
  'refunded',
] as const;
export type OrderStatus = (typeof OrderStatus)[number];

export const PaymentMethod = ['cashOnDelivery', 'wallet', 'card', 'fastPay', 'zainCash'] as const;
export type PaymentMethod = (typeof PaymentMethod)[number];

export const PaymentStatus = ['pending', 'paid', 'failed', 'refunded'] as const;
export type PaymentStatus = (typeof PaymentStatus)[number];

/** Product customization option types (SRS §5.9). */
export const OptionType = [
  'imageVariant',
  'textVariant',
  'colorSwatch',
  'text',
  'longText',
  'date',
  'photoUpload',
  'quantity',
] as const;
export type OptionType = (typeof OptionType)[number];

export const ProductAvailability = ['sameDay', 'preparationDays', 'outOfStock'] as const;
export type ProductAvailability = (typeof ProductAvailability)[number];

export const ReferralStatus = ['pending', 'completed', 'cancelled'] as const;
export type ReferralStatus = (typeof ReferralStatus)[number];

export const SpecialRequestStatus = [
  'submitted',
  'inReview',
  'quoted',
  'accepted',
  'rejected',
  'completed',
] as const;
export type SpecialRequestStatus = (typeof SpecialRequestStatus)[number];

export const WalletTxnType = [
  'topUp',
  'orderPayment',
  'refund',
  'referralCredit',
  'giftCardRedeem',
  'adminAdjustment',
  'creditExpiry',
] as const;
export type WalletTxnType = (typeof WalletTxnType)[number];

export const UserRole = ['customer', 'seller', 'admin'] as const;
export type UserRole = (typeof UserRole)[number];

/** Category kind (SRS §6.3). */
export const CategoryType = ['occasion', 'productType'] as const;
export type CategoryType = (typeof CategoryType)[number];

/** Where a banner is shown on Home (SRS §5.4, §6.8). */
export const BannerPlacement = ['homeTop', 'homeMid1', 'homeMid2', 'homeBottom'] as const;
export type BannerPlacement = (typeof BannerPlacement)[number];

/** What tapping a banner does (SRS §6.8). */
export const BannerActionType = ['category', 'product', 'url', 'route'] as const;
export type BannerActionType = (typeof BannerActionType)[number];

/** Partner store lifecycle (SRS §6.2, §5.25). */
export const StoreStatus = ['pendingApproval', 'active', 'suspended'] as const;
export type StoreStatus = (typeof StoreStatus)[number];

/** Who a product is a gift for (SRS §5.8a, `products.giftFor[]`): him, her, companies & organizations. */
export const GiftAudience = ['men', 'women', 'companies'] as const;
export type GiftAudience = (typeof GiftAudience)[number];
