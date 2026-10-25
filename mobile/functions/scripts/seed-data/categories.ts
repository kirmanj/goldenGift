import type { CategoryType } from '../../src/shared/enums';
import type { Tri } from './helpers';

/**
 * The 50 initial categories of SRS §5.7, in that order (sortOrder = index).
 * Ids are kebab-case slugs and are referenced by products and banners.
 *
 * Kurdish (Sorani, Arabic script) titles are best-effort and MUST be reviewed by a
 * native speaker before launch (SRS §8, Localization). `iconUrl` is seeded as null;
 * the real 3D icons are uploaded with `npm run icons:categories` and a re-seed keeps them.
 */
export interface CategorySeed {
  id: string;
  title: Tri;
  type: CategoryType;
}

const occasion = (id: string, en: string, ar: string, ku: string): CategorySeed => ({
  id,
  title: { en, ar, ku },
  type: 'occasion',
});
const product = (id: string, en: string, ar: string, ku: string): CategorySeed => ({
  id,
  title: { en, ar, ku },
  type: 'productType',
});

export const CATEGORIES: readonly CategorySeed[] = [
  product('golden-gift-home', 'Golden Gift Home', 'غولدن غيفت هوم', 'گۆڵدن گیفت هۆم'),
  product('packages', 'Packages', 'باقات', 'پاکێجەکان'),
  occasion('easter-day', 'Easter Day', 'عيد الفصح', 'جەژنی پاک'),
  occasion('mothers-day', "Mother's Day", 'عيد الأم', 'ڕۆژی دایک'),
  occasion('teachers-day', "Teacher's Day", 'عيد المعلم', 'ڕۆژی مامۆستا'),
  product('mugs', 'Mugs', 'أكواب', 'کوپ'),
  product('skin-and-body-care', 'Skin and Body Care', 'العناية بالبشرة والجسم', 'چاودێری پێست و جەستە'),
  product('tote-bags', 'Tote Bags', 'حقائب قماشية', 'جانتای قوماش'),
  product('makeup', 'Makeup', 'مكياج', 'مەکیاج'),
  product('jewelry-and-watches', 'Jewelry and Watches', 'مجوهرات وساعات', 'خشڵ و کاتژمێر'),
  product('handmade', 'Handmade', 'صناعة يدوية', 'دەستکرد'),
  product('flowers', 'Flowers', 'زهور', 'گوڵ'),
  product('magnets', 'Magnets', 'مغناطيسات', 'موگناتیس'),
  product('breakfast', 'Breakfast', 'فطور', 'نانی بەیانی'),
  product('winter-essentials', 'Winter Essentials', 'مستلزمات الشتاء', 'پێداویستییەکانی زستان'),
  product('phone-cases', 'Phone Cases', 'أغطية الهاتف', 'بەرگی مۆبایل'),
  product('new-borns', 'New Borns', 'المواليد الجدد', 'منداڵی تازە لەدایکبوو'),
  product('button-badge', 'Button Badge', 'دبابيس وشارات', 'باج'),
  product('caps', 'Caps', 'قبعات', 'کڵاو'),
  product('custom-clothing', 'Custom Clothing', 'ملابس مخصصة', 'جلی تایبەت'),
  product('puzzles', 'Puzzles', 'بازل', 'پەزڵ'),
  product('string-art', 'String Art', 'فن الخيوط', 'هونەری دەزوو'),
  product('printed-t-shirts', 'Printed T-Shirts', 'تيشيرتات مطبوعة', 'تیشێرتی چاپکراو'),
  product('rocks', 'Rocks', 'أحجار مزخرفة', 'بەردی نەخشێنراو'),
  product('resin', 'Resin', 'ريزن', 'ڕێزن'),
  occasion('love', 'Love', 'حب', 'خۆشەویستی'),
  product('kids', 'Kids', 'أطفال', 'منداڵان'),
  occasion('birthdays', 'Birthdays', 'أعياد الميلاد', 'ڕۆژی لەدایکبوون'),
  occasion('anniversary', 'Anniversary', 'ذكرى سنوية', 'یادی ساڵانە'),
  product('keychains', 'Keychains', 'ميداليات مفاتيح', 'کلیلدان'),
  // SRS: "Kurdistan (local souvenirs)" — short title for the tile.
  product('kurdistan', 'Kurdistan', 'كردستان', 'کوردستان'),
  product('gift-cards', 'Gift Cards', 'بطاقات الهدايا', 'کارتی دیاری'),
  product('frames', 'Frames', 'إطارات', 'چوارچێوە'),
  product('leather', 'Leather', 'جلديات', 'چەرم'),
  occasion('graduation', 'Graduation', 'تخرج', 'دەرچوون'),
  product('engraving', 'Engraving', 'حفر ونقش', 'هەڵکۆڵین'),
  product('candles', 'Candles', 'شموع', 'مۆم'),
  product('perfume', 'Perfume', 'عطور', 'بۆن'),
  product('3d', '3D', 'ثلاثي الأبعاد', 'سێ ڕەهەندی'),
  product('chocolate', 'Chocolate', 'شوكولاتة', 'چوکلێت'),
  product('crochet', 'Crochet', 'كروشيه', 'کرۆشێ'),
  product('artificial-flowers', 'Artificial Flowers', 'زهور صناعية', 'گوڵی دەستکرد'),
  product('accessories', 'Accessories', 'إكسسوارات', 'ئێکسسوار'),
  product('wall-decorations', 'Wall Decorations', 'ديكورات جدارية', 'ڕازاندنەوەی دیوار'),
  occasion('fathers-day', "Father's Day", 'عيد الأب', 'ڕۆژی باوک'),
  occasion('valentine', 'Valentine', 'عيد الحب', 'ڤالێنتاین'),
  product('matching-sets', 'Matching Sets', 'أطقم متطابقة', 'سێتی هاوشێوە'),
  occasion('new-year', 'New Year', 'رأس السنة', 'سەری ساڵ'),
  occasion('christmas', 'Christmas', 'الكريسماس', 'کریسمس'),
  product('home-fragrance', 'Home Fragrance', 'معطرات المنزل', 'بۆنی ماڵ'),
];
