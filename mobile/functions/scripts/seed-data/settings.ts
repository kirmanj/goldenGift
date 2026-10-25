import type { StoreStatus } from '../../src/shared/enums';
import { HOME_STORE_ID, type Tri } from './helpers';

/**
 * `app_settings/*` (SRS §6.14) and the in-house store (SRS §6.2).
 * Every amount here is a PLACEHOLDER until the owner confirms it (SRS §12).
 */

export const GENERAL_SETTINGS = {
  supportPhone: '+964 750 000 0000', // placeholder
  whatsapp: '+964 750 000 0000', // placeholder
  email: 'support@goldengift.app',
  instagram: 'goldengift',
  sameDayCutoff: '14:00',
  minOrder: 0,
  maintenanceMode: false,
  minAppVersion: { ios: '1.0.0', android: '1.0.0' },
  /** Force-update button targets (SRS §6.14). iOS stays empty until the App Store listing exists. */
  storeUrls: {
    ios: '',
    android: 'https://play.google.com/store/apps/details?id=com.goldengift.golden_gift',
  },
};

export interface CitySeed {
  id: string;
  name: Tri;
  deliveryFee: number;
}

/**
 * The 7 default cities (SRS §4.3). Delivery fees are placeholders — the real
 * launch cities and fees are SRS §12 item 2 (confirm with the owner in Phase 6).
 */
export const CITIES: readonly CitySeed[] = [
  { id: 'erbil', name: { en: 'Erbil', ar: 'أربيل', ku: 'هەولێر' }, deliveryFee: 3000 },
  { id: 'sulaymaniyah', name: { en: 'Sulaymaniyah', ar: 'السليمانية', ku: 'سلێمانی' }, deliveryFee: 4000 },
  { id: 'duhok', name: { en: 'Duhok', ar: 'دهوك', ku: 'دهۆک' }, deliveryFee: 4000 },
  { id: 'baghdad', name: { en: 'Baghdad', ar: 'بغداد', ku: 'بەغدا' }, deliveryFee: 6000 },
  { id: 'basra', name: { en: 'Basra', ar: 'البصرة', ku: 'بەسرە' }, deliveryFee: 6000 },
  { id: 'mosul', name: { en: 'Mosul', ar: 'الموصل', ku: 'مووسڵ' }, deliveryFee: 5000 },
  { id: 'kirkuk', name: { en: 'Kirkuk', ar: 'كركوك', ku: 'کەرکووک' }, deliveryFee: 5000 },
];

/** Provisional (SRS §12 item 3, owner to confirm): referral amounts in IQD, monthly cap, credit expiry in days. */
export const REFERRAL_SETTINGS = {
  joinBonus: 5000,
  orderBonus: 5000,
  maxReferralsPerMonth: 10,
  creditsExpiryDays: 90,
};

/** Only cash on delivery and wallet until a gateway is chosen (SRS §12 item 4). */
export const PAYMENT_SETTINGS = {
  cashOnDelivery: true,
  wallet: true,
  card: false,
  fastPay: false,
  zainCash: false,
};

export const HOME_STORE = {
  id: HOME_STORE_ID,
  name: { en: 'Golden Gift Home', ar: 'غولدن غيفت هوم', ku: 'گۆڵدن گیفت هۆم' } satisfies Tri,
  description: {
    en: "Golden Gift's own collection of personalised gifts, made and delivered by our team.",
    ar: 'مجموعة غولدن غيفت الخاصة من الهدايا المخصصة، يصنعها ويوصلها فريقنا.',
    ku: 'کۆمەڵەی تایبەتی گۆڵدن گیفت لە دیارییە تایبەتەکان، لەلایەن تیمەکەمانەوە دروست دەکرێن و دەگەیەنرێن.',
  } satisfies Tri,
  city: 'erbil',
  phone: GENERAL_SETTINGS.supportPhone,
  status: 'active' satisfies StoreStatus,
};
