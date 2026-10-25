import { FieldValue } from 'firebase-admin/firestore';

/** `notifications.type` of the notice sent when an entered referral code is rejected. */
export const REFERRAL_NOT_APPLIED = 'referralNotApplied';

/**
 * Deliberately says nothing about why (unknown code, own code, same device,
 * inactive referrer) — the reason would leak facts about other accounts.
 * Arabic and Kurdish use the app's terms (app_ar.arb "رمز الإحالة",
 * app_ckb.arb "کۆدی بانگهێشت"); the Kurdish copy needs the same native-speaker
 * review as the rest of the app (SRS §8).
 */
export const REFERRAL_NOT_APPLIED_TEXT = {
  title: 'Referral code not applied',
  titleAr: 'لم يتم تطبيق رمز الإحالة',
  titleKu: 'کۆدی بانگهێشت جێبەجێ نەکرا',
  body: "We couldn't apply the referral code you entered, but your account is ready to use. Happy gifting!",
  bodyAr: 'تعذّر تطبيق رمز الإحالة الذي أدخلته، لكن حسابك جاهز للاستخدام. نتمنى لك إهداءً سعيداً!',
  bodyKu: 'نەمانتوانی ئەو کۆدی بانگهێشتەی نووسیت جێبەجێ بکەین، بەڵام هەژمارەکەت ئامادەی بەکارهێنانە. دیاریی خۆش!',
} as const;

/** `notifications/{id}` document (SRS §6.13) telling `userId` their code was not applied. */
export function referralNotAppliedNotification(userId: string): Record<string, unknown> {
  return {
    userId,
    ...REFERRAL_NOT_APPLIED_TEXT,
    type: REFERRAL_NOT_APPLIED,
    data: { route: null, id: null },
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}
