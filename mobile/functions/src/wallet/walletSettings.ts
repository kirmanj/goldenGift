/**
 * `app_settings/referral` (SRS §5.19, §6.14) — `ReferralSettings.fromMap` in
 * mobile/lib/models/app_settings_model.dart. Amounts in IQD; negative or
 * malformed values read as 0.
 */
import { integer } from '../shared/firestoreParse';

export interface ReferralSettings {
  /** Credits the NEW user gets when they sign up with a code (0 = none). */
  joinBonus: number;
  /** Credits the referrer gets when the friend's first order is delivered and paid (0 = none). */
  orderBonus: number;
  /** Referrals rewarded per referrer per Iraq-time calendar month (0 = no limit). */
  maxReferralsPerMonth: number;
  /** Days a credit lot stays spendable (0 = credits never expire). */
  creditsExpiryDays: number;
}

export function parseReferralSettings(data: Record<string, unknown> | undefined): ReferralSettings {
  const read = (key: keyof ReferralSettings) => Math.max(0, integer(data?.[key]));
  return {
    joinBonus: read('joinBonus'),
    orderBonus: read('orderBonus'),
    maxReferralsPerMonth: read('maxReferralsPerMonth'),
    creditsExpiryDays: read('creditsExpiryDays'),
  };
}

export const DAY_MS = 24 * 60 * 60 * 1000;

/** When credits received at `nowMs` expire (epoch ms), or null when they never do. */
export function creditExpiryAt(nowMs: number, creditsExpiryDays: number): number | null {
  return creditsExpiryDays > 0 ? nowMs + creditsExpiryDays * DAY_MS : null;
}
