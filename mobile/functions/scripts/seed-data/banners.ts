import type { BannerActionType, BannerPlacement } from '../../src/shared/enums';

/**
 * Home banners for every placement (SRS §5.4, §6.8). Actions point at seeded
 * category / product ids or app routes.
 *
 * Artwork is gold placeholder art from placehold.co (16:7, 1600x700). placehold.co
 * renders Arabic-script text as empty boxes (checked 2026-10), so the `imageUrlAr` /
 * `imageUrlKu` variants reuse the English text plus an "AR" / "KU" marker line —
 * enough to see that the app picks the right per-language image. Real trilingual
 * artwork replaces these from the admin dashboard (Phase 5).
 */
export interface BannerSeed {
  id: string;
  placement: BannerPlacement;
  /** Lines of the placeholder artwork (English). */
  text: string[];
  action: { type: BannerActionType; value: string };
  sortOrder: number;
}

export const BANNERS: readonly BannerSeed[] = [
  {
    id: 'home-top-mothers-day',
    placement: 'homeTop',
    text: ["Mother's Day Gifts", 'Personalized with love'],
    action: { type: 'category', value: 'mothers-day' },
    sortOrder: 0,
  },
  {
    id: 'home-top-breakfast-box',
    placement: 'homeTop',
    text: ['Birthday Breakfast Box', 'Fresh to the door in Erbil & Duhok'],
    action: { type: 'product', value: 'birthday-breakfast-box' },
    sortOrder: 1,
  },
  {
    id: 'home-top-gift-cards',
    placement: 'homeTop',
    text: ['Gift Cards', 'The perfect gift, every time'],
    action: { type: 'route', value: '/gift-cards' },
    sortOrder: 2,
  },
  {
    id: 'home-mid1-special-requests',
    placement: 'homeMid1',
    text: ['Request Any Gift', "We'll find it for you"],
    action: { type: 'route', value: '/special-requests' },
    sortOrder: 0,
  },
  {
    id: 'home-mid2-become-partner',
    placement: 'homeMid2',
    text: ['Sell on Golden Gift', 'Become a partner'],
    action: { type: 'route', value: '/become-partner' },
    sortOrder: 0,
  },
  {
    id: 'home-bottom-gift-card-designer',
    placement: 'homeBottom',
    text: ['Design Your Gift Card', 'Make it personal'],
    action: { type: 'route', value: '/gift-cards' },
    sortOrder: 0,
  },
];

/** Gold placeholder image (`\n` is placehold.co's line break). */
export function placeholderImage(lines: string[], width = 1600, height = 700): string {
  const text = encodeURIComponent(lines.join('\\n'));
  return `https://placehold.co/${width}x${height}/C9A227/1F1A08/png?text=${text}`;
}
