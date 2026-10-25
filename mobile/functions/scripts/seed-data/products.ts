import type { GiftAudience, OptionType, ProductAvailability } from '../../src/shared/enums';
import { same, type Tri } from './helpers';

/**
 * 20 demo products for the in-house store (SRS §10 Phase 1). Together they use
 * every `OptionType` (SRS §5.9) and the pricing / availability cases the UI must
 * handle: discounts (`compareAtPrice > price`), featured, same-day vs N-day
 * preparation (2, 3, 12), out of stock, finite stock, per-value stock (incl. a
 * sold-out value), `preparationDaysOverride`, and a city-restricted product.
 * Every product says who it is a gift for (`giftFor`, SRS §5.8a): him, her and /
 * or companies — several products of each, some for all three.
 *
 * Shapes mirror `ProductModel` / `OptionGroup` / `OptionValue` in
 * mobile/lib/models/product_model.dart. Prices are whole IQD, multiples of 250.
 * Kurdish (Sorani) copy needs a native-speaker review before launch (SRS §8).
 */

export interface OptionValueSeed {
  id: string;
  label: Tri;
  /** Set automatically for `imageVariant` values when omitted. */
  imageUrl?: string;
  hex?: string;
  priceDelta?: number;
  stock?: number;
  preparationDaysOverride?: number;
}

export interface OptionGroupSeed {
  id: string;
  type: OptionType;
  label: Tri;
  required?: boolean;
  maxLength?: number;
  minPhotos?: number;
  maxPhotos?: number;
  values?: OptionValueSeed[];
}

export interface ProductSeed {
  id: string;
  title: Tri;
  description: Tri;
  categoryIds: string[];
  price: number;
  compareAtPrice?: number;
  isFeatured?: boolean;
  availability: ProductAvailability;
  preparationDays: number;
  availableCities?: string[];
  /** Omitted = unlimited (stored as null). */
  stock?: number;
  salesCount: number;
  viewCount: number;
  tags: string[];
  /** Who it is a gift for (SRS §5.8a): at least one. */
  giftFor: GiftAudience[];
  /** sortOrder = position in this array. */
  optionGroups: OptionGroupSeed[];
}

// ── Reusable labels ──────────────────────────────────────────────────────────

const L = {
  size: { en: 'Size', ar: 'الحجم', ku: 'قەبارە' },
  color: { en: 'Color', ar: 'اللون', ku: 'ڕەنگ' },
  textColor: { en: 'Text Color', ar: 'لون النص', ku: 'ڕەنگی نووسین' },
  name: { en: 'Name', ar: 'الاسم', ku: 'ناو' },
  text: { en: 'Text', ar: 'النص', ku: 'نووسین' },
  initials: { en: 'Initials', ar: 'الأحرف الأولى', ku: 'پیتە سەرەتاییەکان' },
  cardMessage: { en: 'Card Message', ar: 'رسالة البطاقة', ku: 'نامەی کارت' },
  notes: { en: 'Notes', ar: 'ملاحظات', ku: 'تێبینی' },
  dateOptional: { en: 'Date (Optional)', ar: 'التاريخ (اختياري)', ku: 'بەروار (ئارەزوومەندانە)' },
  uploadPhotos: { en: 'Upload your photos', ar: 'ارفع صورك', ku: 'وێنەکانت باربکە' },
  uploadPhoto: { en: 'Upload your photo', ar: 'ارفع صورتك', ku: 'وێنەکەت باربکە' },
  quantity: { en: 'Quantity', ar: 'الكمية', ku: 'بڕ' },
} satisfies Record<string, Tri>;

// ── Reusable colour swatch values (`hex` is #RRGGBB) ─────────────────────────

const C = {
  gold: { id: 'gold', label: { en: 'Gold', ar: 'ذهبي', ku: 'زێڕین' }, hex: '#C9A227' },
  silver: { id: 'silver', label: { en: 'Silver', ar: 'فضي', ku: 'زیوی' }, hex: '#C0C0C0' },
  black: { id: 'black', label: { en: 'Black', ar: 'أسود', ku: 'ڕەش' }, hex: '#1A1A1C' },
  white: { id: 'white', label: { en: 'White', ar: 'أبيض', ku: 'سپی' }, hex: '#FFFFFF' },
  red: { id: 'red', label: { en: 'Red', ar: 'أحمر', ku: 'سوور' }, hex: '#C62828' },
  pink: { id: 'pink', label: { en: 'Pink', ar: 'وردي', ku: 'پەمەیی' }, hex: '#F4A7B9' },
  navy: { id: 'navy', label: { en: 'Navy', ar: 'كحلي', ku: 'شینی تاریک' }, hex: '#1F3A5F' },
  roseGold: { id: 'rose-gold', label: { en: 'Rose Gold', ar: 'ذهبي وردي', ku: 'زێڕی پەمەیی' }, hex: '#B76E79' },
  beige: { id: 'beige', label: { en: 'Beige', ar: 'بيج', ku: 'بێژ' }, hex: '#E8D9C0' },
  babyBlue: { id: 'baby-blue', label: { en: 'Baby Blue', ar: 'أزرق فاتح', ku: 'شینی کاڵ' }, hex: '#A7C7E7' },
  brown: { id: 'brown', label: { en: 'Brown', ar: 'بني', ku: 'قاوەیی' }, hex: '#8B5E3C' },
  maroon: { id: 'maroon', label: { en: 'Maroon', ar: 'خمري', ku: 'شەرابی' }, hex: '#7B1E2B' },
  natural: { id: 'natural', label: { en: 'Natural', ar: 'طبيعي', ku: 'سروشتی' }, hex: '#EDE3CF' },
} satisfies Record<string, OptionValueSeed>;

// ── Group builders for the common free-input types ───────────────────────────

const textGroup = (id: string, label: Tri, maxLength: number, required = false): OptionGroupSeed => ({
  id,
  type: 'text',
  label,
  required,
  maxLength,
});
const notesGroup = (): OptionGroupSeed => ({
  id: 'notes',
  type: 'longText',
  label: L.notes,
  required: false,
  maxLength: 500,
});
const dateGroup = (label: Tri = L.dateOptional): OptionGroupSeed => ({
  id: 'date',
  type: 'date',
  label,
  required: false,
});
const photosGroup = (minPhotos: number, maxPhotos: number): OptionGroupSeed => ({
  id: 'photos',
  type: 'photoUpload',
  label: maxPhotos > 1 ? L.uploadPhotos : L.uploadPhoto,
  required: true,
  minPhotos,
  maxPhotos,
});
const quantityGroup = (): OptionGroupSeed => ({
  id: 'quantity',
  type: 'quantity',
  label: L.quantity,
  required: false,
});

// ── Catalogue ────────────────────────────────────────────────────────────────

export const PRODUCTS: readonly ProductSeed[] = [
  {
    id: 'wooden-photo-frame',
    title: {
      en: 'Personalized Wooden Photo Frame',
      ar: 'إطار صور خشبي مخصص',
      ku: 'چوارچێوەی وێنەی دارینی تایبەت',
    },
    description: {
      en: "A solid wood frame with your favourite photo and a short engraved message.\nChoose the frame colour and size, upload up to four photos and we'll design the layout for you. Ready in 2 days.",
      ar: 'إطار من الخشب الطبيعي مع صورتك المفضلة ورسالة قصيرة محفورة.\nاختر لون الإطار وحجمه، وارفع حتى أربع صور وسنصمم التنسيق لك. جاهز خلال يومين.',
      ku: 'چوارچێوەیەکی داری سروشتی لەگەڵ وێنە دڵخوازەکەت و نامەیەکی کورتی هەڵکۆڵراو.\nڕەنگ و قەبارەی چوارچێوەکە هەڵبژێرە، تا چوار وێنە باربکە و ئێمە دیزاینەکەت بۆ دەکەین. لە ماوەی دوو ڕۆژدا ئامادە دەبێت.',
    },
    categoryIds: ['frames', 'engraving', 'golden-gift-home'],
    price: 25000,
    compareAtPrice: 30000,
    isFeatured: true,
    availability: 'preparationDays',
    preparationDays: 2,
    salesCount: 420,
    viewCount: 3150,
    tags: ['frame', 'photo', 'wood', 'personalized', 'gift'],
    giftFor: ['men', 'women'],
    optionGroups: [
      {
        id: 'frame-color',
        type: 'imageVariant',
        label: { en: 'Frame Color', ar: 'لون الإطار', ku: 'ڕەنگی چوارچێوە' },
        required: true,
        values: [
          { id: 'natural-oak', label: { en: 'Natural Oak', ar: 'بلوط طبيعي', ku: 'بەڕووی سروشتی' } },
          { id: 'walnut', label: { en: 'Walnut', ar: 'جوز', ku: 'گوێز' }, priceDelta: 2000 },
          { id: 'black', label: C.black.label, priceDelta: 2000, stock: 8 },
          { id: 'white', label: C.white.label },
        ],
      },
      {
        id: 'size',
        type: 'textVariant',
        label: L.size,
        required: true,
        values: [
          { id: '30x30', label: { en: '30x30cm', ar: '30x30 سم', ku: '30x30 سم' } },
          {
            id: '40x40',
            label: { en: '40x40cm', ar: '40x40 سم', ku: '40x40 سم' },
            priceDelta: 5000,
            preparationDaysOverride: 3,
          },
        ],
      },
      photosGroup(1, 4),
      textGroup('text-1', { en: 'Text 1', ar: 'النص 1', ku: 'نووسینی 1' }, 50),
      notesGroup(),
    ],
  },
  {
    id: 'custom-photo-mug',
    title: { en: 'Custom Photo Mug', ar: 'كوب بصورة مخصصة', ku: 'کوپی وێنەی تایبەت' },
    description: {
      en: 'A glossy ceramic mug printed with your photo and name. The dishwasher-safe print stays bright for years. Order before the cut-off and it ships today.',
      ar: 'كوب سيراميك لامع مطبوع بصورتك واسمك. طباعة آمنة في غسالة الصحون تبقى زاهية لسنوات. اطلب قبل موعد الإغلاق ويُشحن اليوم.',
      ku: 'کوپێکی سیرامیکی بریقەدار کە وێنە و ناوەکەتی لەسەر چاپ دەکرێت. چاپەکەی لە قاپشۆردا ناکاڵێتەوە و بۆ چەندین ساڵ گەش دەمێنێتەوە. پێش کاتی کۆتایی داوا بکە و هەر ئەمڕۆ دەنێردرێت.',
    },
    categoryIds: ['mugs', 'golden-gift-home', 'birthdays'],
    price: 12000,
    availability: 'sameDay',
    preparationDays: 0,
    salesCount: 500,
    viewCount: 4800,
    tags: ['mug', 'cup', 'photo', 'coffee', 'gift'],
    giftFor: ['men', 'women'],
    optionGroups: [
      {
        id: 'mug-type',
        type: 'imageVariant',
        label: { en: 'Mug Type', ar: 'نوع الكوب', ku: 'جۆری کوپ' },
        required: true,
        values: [
          { id: 'classic', label: { en: 'Classic White', ar: 'أبيض كلاسيكي', ku: 'سپی کلاسیک' } },
          {
            id: 'magic',
            label: { en: 'Magic (reveals when hot)', ar: 'سحري (يظهر مع الحرارة)', ku: 'سیحراوی (بە گەرمی دەردەکەوێت)' },
            priceDelta: 3000,
          },
          { id: 'gold-inside', label: { en: 'Gold Inside', ar: 'ذهبي من الداخل', ku: 'ناوەوەی زێڕین' }, priceDelta: 2000 },
        ],
      },
      photosGroup(1, 2),
      textGroup('text', L.text, 50),
      quantityGroup(),
    ],
  },
  {
    id: 'engraved-metal-pen',
    title: { en: 'Engraved Metal Pen', ar: 'قلم معدني محفور', ku: 'پێنووسی کانزایی هەڵکۆڵراو' },
    description: {
      en: 'A weighted metal ballpoint pen laser-engraved with a name of up to 12 characters. A classic thank-you for teachers and graduates. Add a gift box for a ready-to-give present.',
      ar: 'قلم حبر معدني ثقيل محفور بالليزر باسم حتى 12 حرفاً. هدية شكر كلاسيكية للمعلمين والخريجين. أضف علبة هدايا لتصبح جاهزة للإهداء.',
      ku: 'پێنووسێکی کانزایی قورس کە ناوێک تا 12 پیت بە لەیزەر لەسەری هەڵدەکۆڵرێت. دیارییەکی کلاسیکی سوپاسگوزاری بۆ مامۆستایان و دەرچووان. سندوقی دیاری زیاد بکە بۆ ئەوەی ئامادەی پێشکەشکردن بێت.',
    },
    categoryIds: ['engraving', 'teachers-day', 'graduation'],
    price: 15000,
    compareAtPrice: 18000,
    availability: 'sameDay',
    preparationDays: 0,
    stock: 40,
    salesCount: 260,
    viewCount: 1900,
    tags: ['pen', 'engraved', 'teacher', 'office', 'gift'],
    giftFor: ['men', 'companies'],
    optionGroups: [
      {
        id: 'pen-color',
        type: 'colorSwatch',
        label: { en: 'Pen Color', ar: 'لون القلم', ku: 'ڕەنگی پێنووس' },
        required: true,
        values: [C.silver, C.black, C.gold, { ...C.roseGold, priceDelta: 2000, stock: 5 }, C.navy],
      },
      textGroup('name', L.name, 12, true),
      {
        id: 'packaging',
        type: 'textVariant',
        label: { en: 'Packaging', ar: 'التغليف', ku: 'پێچانەوە' },
        required: false,
        values: [
          { id: 'pouch', label: { en: 'Pouch', ar: 'كيس قماشي', ku: 'کیسەی قوماش' } },
          { id: 'gift-box', label: { en: 'Gift Box', ar: 'علبة هدايا', ku: 'سندوقی دیاری' }, priceDelta: 2000 },
        ],
      },
    ],
  },
  {
    // SRS IMG_4494: city restriction overlay + 2-day preparation.
    id: 'birthday-breakfast-box',
    title: {
      en: 'Birthday Breakfast Box',
      ar: 'صندوق فطور عيد الميلاد',
      ku: 'سندوقی نانی بەیانی ڕۆژی لەدایکبوون',
    },
    description: {
      en: 'A wooden tray of fresh pastries, cheeses, fruit, juice and a mini cake, finished with a personalised card.\nPrepared fresh to order and delivered in the morning. Available in Erbil and Duhok only.',
      ar: 'صينية خشبية فيها معجنات طازجة وأجبان وفواكه وعصير وكعكة صغيرة، مع بطاقة باسم من تحب.\nتُحضّر طازجة حسب الطلب وتُوصل صباحاً. متوفرة في أربيل ودهوك فقط.',
      ku: 'سینییەکی دارین پڕ لە شیرینی تازە، پەنیر، میوە، شەربەت و کێکێکی بچووک، لەگەڵ کارتێکی تایبەت.\nبە تازەیی بەپێی داواکاری ئامادە دەکرێت و بەیانی دەگەیەنرێت. تەنها لە هەولێر و دهۆک بەردەستە.',
    },
    categoryIds: ['breakfast', 'birthdays', 'packages'],
    price: 35000,
    compareAtPrice: 40000,
    isFeatured: true,
    availability: 'preparationDays',
    preparationDays: 2,
    availableCities: ['erbil', 'duhok'],
    salesCount: 310,
    viewCount: 2900,
    tags: ['breakfast', 'box', 'birthday', 'food', 'morning'],
    giftFor: ['men', 'women'],
    optionGroups: [
      {
        id: 'size',
        type: 'imageVariant',
        label: L.size,
        required: true,
        values: [
          { id: 'for-two', label: { en: 'For 2 people', ar: 'لشخصين', ku: 'بۆ 2 کەس' } },
          { id: 'for-four', label: { en: 'For 4 people', ar: 'لأربعة أشخاص', ku: 'بۆ 4 کەس' }, priceDelta: 15000 },
          {
            id: 'family',
            label: { en: 'Family (6 people)', ar: 'عائلي (6 أشخاص)', ku: 'خێزانی (6 کەس)' },
            priceDelta: 30000,
            preparationDaysOverride: 3,
          },
        ],
      },
      textGroup('card-message', L.cardMessage, 100),
      dateGroup(),
      notesGroup(),
    ],
  },
  {
    id: 'red-rose-bouquet',
    title: { en: 'Red Rose Bouquet', ar: 'باقة ورد أحمر', ku: 'چەپکە گوڵەباخی سوور' },
    description: {
      en: "Fresh long-stem red roses, hand-tied and wrapped in premium paper. Add a card message and we'll write it by hand. Same-day delivery when ordered before the cut-off.",
      ar: 'ورود حمراء طازجة طويلة الساق مربوطة يدوياً ومغلفة بورق فاخر. أضف رسالة وسنكتبها بخط اليد. توصيل في نفس اليوم عند الطلب قبل موعد الإغلاق.',
      ku: 'گوڵەباخی سووری تازەی قەدبەرز کە بە دەست بەستراون و بە کاغەزی نایاب پێچراونەتەوە. نامەیەک زیاد بکە و ئێمە بە دەست دەینووسین. گەیاندن لە هەمان ڕۆژدا ئەگەر پێش کاتی کۆتایی داوا بکەیت.',
    },
    categoryIds: ['flowers', 'love', 'valentine'],
    price: 45000,
    isFeatured: true,
    availability: 'sameDay',
    preparationDays: 0,
    salesCount: 380,
    viewCount: 3600,
    tags: ['flowers', 'roses', 'bouquet', 'love', 'romantic'],
    giftFor: ['women'],
    optionGroups: [
      {
        id: 'size',
        type: 'imageVariant',
        label: L.size,
        required: true,
        values: [
          { id: 'roses-12', label: { en: '12 Roses', ar: '12 وردة', ku: '12 گوڵەباخ' } },
          { id: 'roses-24', label: { en: '24 Roses', ar: '24 وردة', ku: '24 گوڵەباخ' }, priceDelta: 20000 },
          { id: 'roses-50', label: { en: '50 Roses', ar: '50 وردة', ku: '50 گوڵەباخ' }, priceDelta: 55000, stock: 5 },
        ],
      },
      {
        id: 'wrapping-color',
        type: 'colorSwatch',
        label: { en: 'Wrapping Color', ar: 'لون التغليف', ku: 'ڕەنگی پێچانەوە' },
        required: true,
        values: [C.black, C.pink, C.white, C.gold],
      },
      textGroup('card-message', L.cardMessage, 100),
    ],
  },
  {
    id: 'gold-name-necklace',
    title: {
      en: 'Gold-Plated Name Necklace',
      ar: 'قلادة اسم مطلية بالذهب',
      ku: 'ملوانکەی ناو بە ئاوی زێڕ',
    },
    description: {
      en: 'A delicate stainless-steel necklace with the name of your choice, plated in 18K gold. Hypoallergenic and water-resistant. Arrives in a gift box with a polishing cloth.',
      ar: 'قلادة رقيقة من الستانلس ستيل بالاسم الذي تختاره، مطلية بذهب عيار 18. مضادة للحساسية ومقاومة للماء. تصل في علبة هدايا مع قطعة قماش للتلميع.',
      ku: 'ملوانکەیەکی ناسک لە پۆڵای ژەنگنەگر بە ناوی دڵخوازی خۆت، بە ئاوی زێڕی 18 قیرات. هەستیاری دروست ناکات و بەرگەی ئاو دەگرێت. لە سندوقی دیاریدا لەگەڵ پارچە قوماشێکی پاککردنەوە دەگات.',
    },
    categoryIds: ['jewelry-and-watches', 'mothers-day', 'love'],
    price: 55000,
    availability: 'preparationDays',
    preparationDays: 3,
    stock: 15,
    salesCount: 190,
    viewCount: 2400,
    tags: ['necklace', 'name', 'jewelry', 'gold', 'mother'],
    giftFor: ['women'],
    optionGroups: [
      {
        id: 'metal',
        type: 'imageVariant',
        label: { en: 'Metal', ar: 'المعدن', ku: 'کانزا' },
        required: true,
        values: [
          { id: 'gold', label: C.gold.label },
          { id: 'silver', label: C.silver.label },
          { id: 'rose-gold', label: C.roseGold.label, priceDelta: 2000, stock: 4 },
        ],
      },
      textGroup('name', L.name, 12, true),
      {
        id: 'chain-length',
        type: 'textVariant',
        label: { en: 'Chain Length', ar: 'طول السلسلة', ku: 'درێژی زنجیر' },
        required: true,
        values: [
          { id: '40cm', label: { en: '40 cm', ar: '40 سم', ku: '40 سم' } },
          { id: '45cm', label: { en: '45 cm', ar: '45 سم', ku: '45 سم' } },
          { id: '50cm', label: { en: '50 cm', ar: '50 سم', ku: '50 سم' }, priceDelta: 2000 },
        ],
      },
    ],
  },
  {
    id: '3d-photo-moon-lamp',
    title: {
      en: '3D Photo Moon Lamp',
      ar: 'مصباح القمر ثلاثي الأبعاد بالصورة',
      ku: 'چرای مانگی سێ ڕەهەندی بە وێنە',
    },
    description: {
      en: 'A 3D-printed moon lamp that reveals your photo when the light is on. Touch control with warm white or 16 colours and a rechargeable battery. Made to order in 3 days.',
      ar: 'مصباح قمر مطبوع بتقنية ثلاثية الأبعاد تظهر صورتك عند تشغيله. تحكم باللمس بإضاءة بيضاء دافئة أو 16 لوناً وبطارية قابلة للشحن. يُصنع حسب الطلب خلال 3 أيام.',
      ku: 'چرایەکی مانگی چاپکراوی سێ ڕەهەندی کە کاتێک دادەگیرسێت وێنەکەت دەردەکەوێت. کۆنترۆڵی دەستلێدان بە ڕووناکی سپی گەرم یان 16 ڕەنگ و پاتریی دووبارە بارگاوی. لە ماوەی 3 ڕۆژدا بەپێی داواکاری دروست دەکرێت.',
    },
    categoryIds: ['3d', 'golden-gift-home', 'anniversary'],
    price: 38000,
    isFeatured: true,
    availability: 'preparationDays',
    preparationDays: 3,
    salesCount: 150,
    viewCount: 2100,
    tags: ['lamp', 'moon', '3d', 'photo', 'night light'],
    giftFor: ['men', 'women'],
    optionGroups: [
      {
        id: 'size',
        type: 'imageVariant',
        label: L.size,
        required: true,
        values: [
          { id: '12cm', label: { en: '12 cm', ar: '12 سم', ku: '12 سم' } },
          { id: '15cm', label: { en: '15 cm', ar: '15 سم', ku: '15 سم' }, priceDelta: 5000 },
          { id: '18cm', label: { en: '18 cm', ar: '18 سم', ku: '18 سم' }, priceDelta: 9000, preparationDaysOverride: 5 },
        ],
      },
      photosGroup(1, 1),
      {
        id: 'light-color',
        type: 'colorSwatch',
        label: { en: 'Light Color', ar: 'لون الإضاءة', ku: 'ڕەنگی ڕووناکی' },
        required: true,
        values: [
          { id: 'warm-white', label: { en: 'Warm White', ar: 'أبيض دافئ', ku: 'سپی گەرم' }, hex: '#FFE7B0' },
          { id: 'multicolor', label: { en: '16 Colours', ar: '16 لوناً', ku: '16 ڕەنگ' }, hex: '#8E7CC3', priceDelta: 2000 },
        ],
      },
      textGroup('text', L.text, 50),
    ],
  },
  {
    id: 'custom-printed-t-shirt',
    title: { en: 'Custom Printed T-Shirt', ar: 'تيشيرت مطبوع حسب الطلب', ku: 'تیشێرتی چاپکراوی تایبەت' },
    description: {
      en: 'A soft 100% cotton T-shirt printed with your own text in the colour you pick. Perfect for birthdays, teams and matching family outfits. Printed and shipped the same day.',
      ar: 'تيشيرت ناعم من القطن 100% مطبوع بالنص الذي تختاره وباللون الذي تريده. مثالي لأعياد الميلاد والفرق والملابس العائلية المتطابقة. يُطبع ويُشحن في نفس اليوم.',
      ku: 'تیشێرتێکی نەرمی لۆکەی 100% کە نووسینی خۆتی بە ڕەنگی دڵخوازت لەسەر چاپ دەکرێت. گونجاوە بۆ ڕۆژی لەدایکبوون، تیمەکان و جلی هاوشێوەی خێزان. لە هەمان ڕۆژدا چاپ دەکرێت و دەنێردرێت.',
    },
    categoryIds: ['printed-t-shirts', 'custom-clothing', 'matching-sets'],
    price: 18000,
    availability: 'sameDay',
    preparationDays: 0,
    salesCount: 230,
    viewCount: 2000,
    tags: ['t-shirt', 'shirt', 'print', 'clothing', 'custom'],
    giftFor: ['men', 'women', 'companies'],
    optionGroups: [
      {
        id: 'shirt-color',
        type: 'colorSwatch',
        label: { en: 'Shirt Color', ar: 'لون التيشيرت', ku: 'ڕەنگی تیشێرت' },
        required: true,
        values: [C.white, C.black, C.navy, C.red, C.beige],
      },
      {
        id: 'size',
        type: 'textVariant',
        label: L.size,
        required: true,
        values: [
          { id: 's', label: same('S'), stock: 12 },
          { id: 'm', label: same('M'), stock: 20 },
          { id: 'l', label: same('L'), stock: 18 },
          { id: 'xl', label: same('XL'), stock: 9 },
          { id: 'xxl', label: same('XXL'), priceDelta: 2000, stock: 4 },
        ],
      },
      textGroup('front-text', { en: 'Front Text', ar: 'نص الواجهة الأمامية', ku: 'نووسینی پێشەوە' }, 50, true),
      {
        id: 'text-color',
        type: 'colorSwatch',
        label: L.textColor,
        required: true,
        values: [C.gold, C.black, C.white, C.red],
      },
    ],
  },
  {
    id: 'photo-jigsaw-puzzle',
    title: { en: 'Photo Jigsaw Puzzle', ar: 'بازل بالصورة', ku: 'پەزڵی وێنە' },
    description: {
      en: 'Turn a favourite memory into a jigsaw puzzle in a printed gift box. Thick matte pieces with no glare. A fun gift for kids and families.',
      ar: 'حوّل ذكرى مفضلة إلى بازل داخل علبة هدايا مطبوعة. قطع سميكة بلمسة مطفية بلا انعكاس. هدية ممتعة للأطفال والعائلات.',
      ku: 'یادەوەرییەکی خۆشەویست بکە بە پەزڵ لە ناو سندوقێکی دیاری چاپکراودا. پارچەی ئەستوور و مات بێ درەوشانەوە. دیارییەکی خۆش بۆ منداڵان و خێزانەکان.',
    },
    categoryIds: ['puzzles', 'kids', 'golden-gift-home'],
    price: 22000,
    availability: 'preparationDays',
    preparationDays: 2,
    salesCount: 95,
    viewCount: 1300,
    tags: ['puzzle', 'jigsaw', 'photo', 'kids', 'game'],
    giftFor: ['men', 'women'],
    optionGroups: [
      {
        id: 'pieces',
        type: 'textVariant',
        label: { en: 'Pieces', ar: 'عدد القطع', ku: 'ژمارەی پارچە' },
        required: true,
        values: [
          { id: '120', label: { en: '120 pieces', ar: '120 قطعة', ku: '120 پارچە' } },
          { id: '300', label: { en: '300 pieces', ar: '300 قطعة', ku: '300 پارچە' }, priceDelta: 3000 },
          {
            id: '500',
            label: { en: '500 pieces', ar: '500 قطعة', ku: '500 پارچە' },
            priceDelta: 5000,
            preparationDaysOverride: 3,
          },
        ],
      },
      photosGroup(1, 1),
      textGroup('box-text', { en: 'Box Text', ar: 'نص العلبة', ku: 'نووسینی سەر سندوق' }, 50),
    ],
  },
  {
    id: 'scented-candle-set',
    title: { en: 'Scented Candle Gift Set', ar: 'طقم شموع معطرة', ku: 'سێتی مۆمی بۆنخۆش' },
    description: {
      en: 'Three hand-poured soy wax candles in glass jars with a personalised label. Each candle burns for about 30 hours. Packed in a kraft gift box.',
      ar: 'ثلاث شموع من شمع الصويا مصبوبة يدوياً في جرار زجاجية مع ملصق مخصص. تشتعل كل شمعة نحو 30 ساعة. مغلفة في علبة هدايا من الورق المقوى.',
      ku: 'سێ مۆمی سۆیا کە بە دەست لە شووشەدا ڕێژراون لەگەڵ لەیبڵێکی تایبەت. هەر مۆمێک نزیکەی 30 کاتژمێر دەسووتێت. لە سندوقێکی دیاریی کاغەزیدا پێچراوە.',
    },
    categoryIds: ['candles', 'home-fragrance', 'mothers-day'],
    price: 28000,
    availability: 'sameDay',
    preparationDays: 0,
    stock: 25,
    salesCount: 140,
    viewCount: 1600,
    tags: ['candle', 'scented', 'soy', 'home', 'relax'],
    giftFor: ['women'],
    optionGroups: [
      {
        id: 'scent',
        type: 'imageVariant',
        label: { en: 'Scent', ar: 'الرائحة', ku: 'بۆن' },
        required: true,
        values: [
          { id: 'vanilla', label: { en: 'Vanilla', ar: 'فانيلا', ku: 'ڤانێلا' } },
          { id: 'lavender', label: { en: 'Lavender', ar: 'لافندر', ku: 'لاڤەندەر' } },
          { id: 'oud', label: { en: 'Oud', ar: 'عود', ku: 'عود' }, priceDelta: 5000, stock: 6 },
        ],
      },
      textGroup('name', L.name, 12),
    ],
  },
  {
    id: 'personalized-chocolate-box',
    title: { en: 'Personalized Chocolate Box', ar: 'علبة شوكولاتة مخصصة', ku: 'سندوقی چوکلێتی تایبەت' },
    description: {
      en: 'Assorted Belgian chocolates in a gold box with your message printed on the lid. Choose the box size and ribbon colour. Kept chilled and delivered the same day.',
      ar: 'تشكيلة شوكولاتة بلجيكية في علبة ذهبية مع رسالتك مطبوعة على الغطاء. اختر حجم العلبة ولون الشريطة. تُحفظ مبردة وتُوصل في نفس اليوم.',
      ku: 'چوکلێتی بەلجیکی جۆراوجۆر لە سندوقێکی زێڕیندا و نامەکەت لەسەر سەرپۆشەکەی چاپ دەکرێت. قەبارەی سندوق و ڕەنگی شریتەکە هەڵبژێرە. بە ساردی هەڵدەگیرێت و لە هەمان ڕۆژدا دەگەیەنرێت.',
    },
    categoryIds: ['chocolate', 'valentine', 'birthdays'],
    price: 30000,
    compareAtPrice: 35000,
    isFeatured: true,
    availability: 'sameDay',
    preparationDays: 0,
    salesCount: 450,
    viewCount: 3900,
    tags: ['chocolate', 'box', 'sweets', 'valentine', 'gift'],
    giftFor: ['men', 'women', 'companies'],
    optionGroups: [
      {
        id: 'box-size',
        type: 'textVariant',
        label: { en: 'Box Size', ar: 'حجم العلبة', ku: 'قەبارەی سندوق' },
        required: true,
        values: [
          { id: '9', label: { en: '9 pieces', ar: '9 قطع', ku: '9 دانە' } },
          { id: '16', label: { en: '16 pieces', ar: '16 قطعة', ku: '16 دانە' }, priceDelta: 8000 },
          { id: '25', label: { en: '25 pieces', ar: '25 قطعة', ku: '25 دانە' }, priceDelta: 15000 },
        ],
      },
      textGroup('lid-text', { en: 'Lid Text', ar: 'نص الغطاء', ku: 'نووسینی سەرپۆش' }, 50),
      {
        id: 'ribbon-color',
        type: 'colorSwatch',
        label: { en: 'Ribbon Color', ar: 'لون الشريطة', ku: 'ڕەنگی شریت' },
        required: true,
        values: [C.gold, C.red, C.white],
      },
      quantityGroup(),
    ],
  },
  {
    // SRS IMG_4506/4507: Name (12), Date (optional), colour swatches, 12-day preparation.
    id: 'crochet-teddy-bear',
    title: { en: 'Handmade Crochet Teddy Bear', ar: 'دبدوب كروشيه مصنوع يدوياً', ku: 'ورچی کرۆشێی دەستکرد' },
    description: {
      en: 'A soft teddy bear crocheted by hand from baby-safe cotton yarn, with a name embroidered on its bib. Each bear takes about 12 days to make. Tell us the date you need it by and any special wishes.',
      ar: 'دبدوب ناعم محاك يدوياً بالكروشيه من خيوط قطنية آمنة للأطفال، مع اسم مطرز على مريلته. يستغرق صنع كل دبدوب نحو 12 يوماً. أخبرنا بالتاريخ الذي تحتاجه فيه وأي طلبات خاصة.',
      ku: 'ورچێکی نەرم کە بە دەست لە دەزووی لۆکەی سەلامەت بۆ منداڵ کرۆشێ کراوە، ناوێکی لەسەر بەرسینگەکەی دەدوورێت. دروستکردنی هەر ورچێک نزیکەی 12 ڕۆژ دەخایەنێت. ئەو بەروارەی پێویستتە و هەر داوایەکی تایبەتمان پێ بڵێ.',
    },
    categoryIds: ['crochet', 'handmade', 'kids'],
    price: 20000,
    availability: 'preparationDays',
    preparationDays: 12,
    stock: 6,
    salesCount: 35,
    viewCount: 700,
    tags: ['crochet', 'teddy', 'handmade', 'toy', 'baby'],
    giftFor: ['women'],
    optionGroups: [
      {
        id: 'color',
        type: 'colorSwatch',
        label: L.color,
        required: true,
        values: [C.beige, C.pink, C.babyBlue, C.brown],
      },
      textGroup('name', L.name, 12),
      dateGroup(),
      notesGroup(),
    ],
  },
  {
    id: 'resin-name-keychain',
    title: { en: 'Resin Name Keychain', ar: 'ميدالية مفاتيح ريزن بالاسم', ku: 'کلیلدانی ڕێزن بە ناو' },
    description: {
      en: 'A clear resin keychain with real dried flowers and a name in the colour of your choice. Light, durable and made by hand. Order a few as party favours.',
      ar: 'ميدالية مفاتيح من الريزن الشفاف مع زهور مجففة حقيقية واسم باللون الذي تختاره. خفيفة ومتينة ومصنوعة يدوياً. اطلب عدة قطع كتذكارات للحفلات.',
      ku: 'کلیلدانێکی ڕێزنی ڕوون لەگەڵ گوڵی وشککراوەی ڕاستەقینە و ناوێک بە ڕەنگی دڵخوازت. سووک و بەهێز و دەستکردە. چەند دانەیەک وەک یادگاری ئاهەنگ داوا بکە.',
    },
    categoryIds: ['resin', 'keychains', 'handmade'],
    price: 12000,
    availability: 'preparationDays',
    preparationDays: 2,
    salesCount: 210,
    viewCount: 1500,
    tags: ['keychain', 'resin', 'name', 'flowers', 'handmade'],
    giftFor: ['men', 'women'],
    optionGroups: [
      {
        id: 'inclusion',
        type: 'imageVariant',
        label: { en: 'Inclusion', ar: 'الزينة الداخلية', ku: 'ناوەڕۆک' },
        required: true,
        values: [
          { id: 'dried-rose', label: { en: 'Dried Rose', ar: 'ورد مجفف', ku: 'گوڵەباخی وشک' } },
          { id: 'daisy', label: { en: 'Daisy', ar: 'أقحوان', ku: 'گوڵەبەیبوون' } },
          { id: 'gold-flakes', label: { en: 'Gold Flakes', ar: 'رقائق ذهبية', ku: 'پەڕەی زێڕ' }, priceDelta: 2000 },
        ],
      },
      textGroup('name', L.name, 12, true),
      {
        id: 'text-color',
        type: 'colorSwatch',
        label: L.textColor,
        required: true,
        values: [C.gold, C.silver, C.black, C.white],
      },
      quantityGroup(),
    ],
  },
  {
    id: 'custom-photo-phone-case',
    title: { en: 'Custom Photo Phone Case', ar: 'غطاء هاتف بصورة مخصصة', ku: 'بەرگی مۆبایلی وێنەی تایبەت' },
    description: {
      en: 'A slim, shock-absorbing phone case printed with one photo or a collage of up to four. Scratch-resistant print with raised edges to protect the screen and camera.',
      ar: 'غطاء هاتف نحيف ماص للصدمات مطبوع بصورة واحدة أو مجموعة حتى أربع صور. طباعة مقاومة للخدوش مع حواف مرتفعة لحماية الشاشة والكاميرا.',
      ku: 'بەرگێکی مۆبایلی باریک و بەرگری لێدان کە یەک وێنە یان کۆلاژێک تا چوار وێنەی لەسەر چاپ دەکرێت. چاپی بەرگری خەدش لەگەڵ لێواری بەرز بۆ پاراستنی شاشە و کامێرا.',
    },
    categoryIds: ['phone-cases', 'accessories'],
    price: 15000,
    availability: 'sameDay',
    preparationDays: 0,
    salesCount: 270,
    viewCount: 2300,
    tags: ['phone', 'case', 'cover', 'photo', 'iphone', 'samsung'],
    giftFor: ['men', 'women'],
    optionGroups: [
      {
        id: 'phone-model',
        type: 'textVariant',
        label: { en: 'Phone Model', ar: 'طراز الهاتف', ku: 'مۆدێلی مۆبایل' },
        required: true,
        values: [
          { id: 'iphone-15', label: same('iPhone 15'), stock: 10 },
          { id: 'iphone-15-pro', label: same('iPhone 15 Pro'), stock: 6 },
          { id: 'iphone-16', label: same('iPhone 16'), stock: 12 },
          { id: 'iphone-16-pro-max', label: same('iPhone 16 Pro Max'), priceDelta: 2000, stock: 3 },
          // Sold-out value: the UI must disable it.
          { id: 'galaxy-s24', label: same('Galaxy S24'), stock: 0 },
        ],
      },
      {
        id: 'case-type',
        type: 'imageVariant',
        label: { en: 'Case Type', ar: 'نوع الغطاء', ku: 'جۆری بەرگ' },
        required: true,
        values: [
          { id: 'clear', label: { en: 'Clear', ar: 'شفاف', ku: 'ڕوون' } },
          { id: 'matte-black', label: { en: 'Matte Black', ar: 'أسود مطفي', ku: 'ڕەشی مات' } },
          { id: 'magsafe', label: same('MagSafe'), priceDelta: 5000, preparationDaysOverride: 2 },
        ],
      },
      photosGroup(1, 4),
      textGroup('text', L.text, 50),
    ],
  },
  {
    id: 'printed-canvas-tote-bag',
    title: { en: 'Printed Canvas Tote Bag', ar: 'حقيبة قماشية مطبوعة', ku: 'جانتای قوماشی چاپکراو' },
    description: {
      en: 'A sturdy cotton canvas tote with your name or a short quote printed on the front. Big enough for books, groceries or a day at the beach.',
      ar: 'حقيبة قماشية متينة من القطن مطبوع عليها اسمك أو عبارة قصيرة. واسعة بما يكفي للكتب أو التسوق أو يوم على البحر.',
      ku: 'جانتایەکی قوماشی لۆکەی بەهێز کە ناوەکەت یان وتەیەکی کورتی لەسەر چاپ دەکرێت. ئەوەندە گەورەیە کە کتێب، کەلوپەلی بازاڕ یان پێداویستی ڕۆژێکی دەریای تێدا جێگەی ببێتەوە.',
    },
    categoryIds: ['tote-bags', 'custom-clothing', 'accessories'],
    price: 14000,
    availability: 'sameDay',
    preparationDays: 0,
    salesCount: 120,
    viewCount: 1100,
    tags: ['tote', 'bag', 'canvas', 'print', 'eco'],
    giftFor: ['women', 'companies'],
    optionGroups: [
      {
        id: 'bag-color',
        type: 'colorSwatch',
        label: { en: 'Bag Color', ar: 'لون الحقيبة', ku: 'ڕەنگی جانتا' },
        required: true,
        values: [C.natural, C.black],
      },
      textGroup('print-text', { en: 'Print Text', ar: 'النص المطبوع', ku: 'نووسینی چاپکراو' }, 50, true),
      {
        id: 'text-color',
        type: 'colorSwatch',
        label: L.textColor,
        required: true,
        values: [C.black, C.gold, C.white],
      },
    ],
  },
  {
    id: 'name-string-art',
    title: { en: 'Name String Art Board', ar: 'لوحة فن الخيوط بالاسم', ku: 'تابلۆی هونەری دەزوو بە ناو' },
    description: {
      en: 'A wooden board with nails and thread forming a name or word of up to 12 letters. Handmade wall art for bedrooms, nurseries and offices. Ready in 3 days, or 5 days for the large size.',
      ar: 'لوحة خشبية بمسامير وخيوط تشكّل اسماً أو كلمة حتى 12 حرفاً. فن جداري يدوي لغرف النوم وغرف الأطفال والمكاتب. جاهزة خلال 3 أيام، أو 5 أيام للحجم الكبير.',
      ku: 'تابلۆیەکی دارین بە بزمار و دەزوو کە ناوێک یان وشەیەک تا 12 پیت پێک دەهێنێت. هونەری دیواریی دەستکرد بۆ ژووری نووستن، ژووری منداڵ و نووسینگە. لە 3 ڕۆژدا ئامادە دەبێت، یان 5 ڕۆژ بۆ قەبارەی گەورە.',
    },
    categoryIds: ['string-art', 'wall-decorations', 'handmade'],
    price: 32000,
    availability: 'preparationDays',
    preparationDays: 3,
    salesCount: 60,
    viewCount: 900,
    tags: ['string art', 'wall', 'decor', 'name', 'handmade'],
    giftFor: ['women'],
    optionGroups: [
      {
        id: 'size',
        type: 'textVariant',
        label: L.size,
        required: true,
        values: [
          { id: '30x30', label: { en: '30x30cm', ar: '30x30 سم', ku: '30x30 سم' } },
          {
            id: '40x40',
            label: { en: '40x40cm', ar: '40x40 سم', ku: '40x40 سم' },
            priceDelta: 5000,
            preparationDaysOverride: 5,
          },
        ],
      },
      {
        id: 'thread-color',
        type: 'colorSwatch',
        label: { en: 'Thread Color', ar: 'لون الخيط', ku: 'ڕەنگی دەزوو' },
        required: true,
        values: [C.gold, C.red, C.white, C.black],
      },
      textGroup('name', L.name, 12, true),
    ],
  },
  {
    id: 'oud-perfume-gift-set',
    title: { en: 'Oud Perfume Gift Set', ar: 'طقم عطر العود', ku: 'سێتی بۆنی عود' },
    description: {
      en: 'A rich oud eau de parfum with a matching body mist, presented in a black-and-gold box. Add initials to be engraved on the bottle cap.',
      ar: 'عطر عود فاخر مع رذاذ للجسم متناسق، في علبة سوداء وذهبية. أضف الأحرف الأولى لتُحفر على غطاء الزجاجة.',
      ku: 'بۆنێکی عودی نایاب لەگەڵ سپرەی جەستەی هاوتا، لە سندوقێکی ڕەش و زێڕیندا. پیتە سەرەتاییەکانی ناو زیاد بکە بۆ هەڵکۆڵین لەسەر سەرپۆشی شووشەکە.',
    },
    categoryIds: ['perfume', 'fathers-day', 'skin-and-body-care'],
    price: 75000,
    availability: 'outOfStock',
    preparationDays: 0,
    stock: 0,
    salesCount: 80,
    viewCount: 1700,
    tags: ['perfume', 'oud', 'fragrance', 'men', 'luxury'],
    giftFor: ['men'],
    optionGroups: [
      {
        id: 'size',
        type: 'textVariant',
        label: L.size,
        required: true,
        values: [
          { id: '50ml', label: { en: '50 ml', ar: '50 مل', ku: '50 مل' } },
          { id: '100ml', label: { en: '100 ml', ar: '100 مل', ku: '100 مل' }, priceDelta: 20000 },
        ],
      },
      textGroup('initials', L.initials, 12),
    ],
  },
  {
    // SRS IMG_4504: "Color Brown/Black" image variants.
    id: 'engraved-leather-wallet',
    title: { en: 'Engraved Leather Wallet', ar: 'محفظة جلدية محفورة', ku: 'جزدانی چەرمی هەڵکۆڵراو' },
    description: {
      en: 'A genuine leather bifold wallet with your initials engraved on the front and a hidden message inside. Slim design with six card slots. Ready in 2 days.',
      ar: 'محفظة من الجلد الطبيعي تُطوى نصفين مع الأحرف الأولى محفورة على الواجهة ورسالة مخفية في الداخل. تصميم نحيف بستة جيوب للبطاقات. جاهزة خلال يومين.',
      ku: 'جزدانێکی چەرمی ڕەسەن کە پیتە سەرەتاییەکانی ناوت لەسەر ڕووەکەی هەڵدەکۆڵرێت و نامەیەکی شاراوەش لە ناوەوە. دیزاینی باریک بە شەش شوێنی کارت. لە ماوەی دوو ڕۆژدا ئامادە دەبێت.',
    },
    categoryIds: ['leather', 'engraving', 'fathers-day'],
    price: 40000,
    compareAtPrice: 48000,
    availability: 'preparationDays',
    preparationDays: 2,
    stock: 20,
    salesCount: 175,
    viewCount: 1800,
    tags: ['wallet', 'leather', 'engraved', 'men', 'father'],
    giftFor: ['men'],
    optionGroups: [
      {
        id: 'color',
        type: 'imageVariant',
        label: L.color,
        required: true,
        values: [
          { id: 'brown', label: C.brown.label },
          { id: 'black', label: C.black.label },
          { id: 'tan', label: { en: 'Tan', ar: 'عسلي', ku: 'هەنگوینی' }, priceDelta: 2000, stock: 5 },
        ],
      },
      textGroup('initials', L.initials, 12, true),
      textGroup('inside-message', { en: 'Inside Message', ar: 'رسالة داخلية', ku: 'نامەی ناوەوە' }, 100),
      {
        id: 'gift-wrap',
        type: 'textVariant',
        label: { en: 'Gift Wrap', ar: 'تغليف الهدية', ku: 'پێچانەوەی دیاری' },
        required: false,
        values: [
          { id: 'none', label: { en: 'No wrap', ar: 'بدون تغليف', ku: 'بێ پێچانەوە' } },
          { id: 'wrapped', label: { en: 'Gift wrap', ar: 'تغليف هدية', ku: 'پێچانەوەی دیاری' }, priceDelta: 2000 },
        ],
      },
    ],
  },
  {
    id: 'newborn-baby-gift-set',
    title: {
      en: 'Newborn Baby Gift Set',
      ar: 'طقم هدايا للمولود الجديد',
      ku: 'سێتی دیاری بۆ منداڵی تازە لەدایکبوو',
    },
    description: {
      en: "A keepsake box with an embroidered blanket, bodysuit, bib and a birth-details plaque for the new arrival.\nPick a theme colour and give us the baby's name and birth date. Prepared in 3 days.",
      ar: 'صندوق تذكاري فيه بطانية مطرزة وبدلة وصدرية ولوحة بتفاصيل الولادة للمولود الجديد.\nاختر لون الطقم وأعطنا اسم الطفل وتاريخ ولادته. يُحضّر خلال 3 أيام.',
      ku: 'سندوقێکی یادگاری کە بەتانییەکی چنراو، جلی منداڵ، بەرسینگ و تابلۆیەکی زانیاریی لەدایکبوونی تێدایە بۆ منداڵە تازەکە.\nڕەنگی سێتەکە هەڵبژێرە و ناو و بەرواری لەدایکبوونی منداڵەکەمان پێ بدە. لە ماوەی 3 ڕۆژدا ئامادە دەکرێت.',
    },
    categoryIds: ['new-borns', 'packages', 'kids'],
    price: 65000,
    availability: 'preparationDays',
    preparationDays: 3,
    stock: 10,
    salesCount: 45,
    viewCount: 950,
    tags: ['baby', 'newborn', 'gift set', 'blanket', 'birth'],
    giftFor: ['women'],
    optionGroups: [
      {
        id: 'theme',
        type: 'imageVariant',
        label: { en: 'Theme', ar: 'الطابع', ku: 'شێواز' },
        required: true,
        values: [
          { id: 'boy', label: { en: 'Boy (Blue)', ar: 'ولد (أزرق)', ku: 'کوڕ (شین)' } },
          { id: 'girl', label: { en: 'Girl (Pink)', ar: 'بنت (وردي)', ku: 'کچ (پەمەیی)' } },
          { id: 'neutral', label: { en: 'Neutral (Beige)', ar: 'محايد (بيج)', ku: 'بێلایەن (بێژ)' } },
        ],
      },
      textGroup('baby-name', { en: 'Baby Name', ar: 'اسم الطفل', ku: 'ناوی منداڵ' }, 12, true),
      dateGroup({
        en: 'Birth Date (Optional)',
        ar: 'تاريخ الولادة (اختياري)',
        ku: 'بەرواری لەدایکبوون (ئارەزوومەندانە)',
      }),
      notesGroup(),
    ],
  },
  {
    id: 'graduation-gift-set',
    title: { en: 'Graduation Gift Set', ar: 'طقم هدايا التخرج', ku: 'سێتی دیاری دەرچوون' },
    description: {
      en: "A graduation sash, an engraved pen and a framed photo of the graduate in one gold gift box. Add the graduate's name, a message and up to four photos for the frame.",
      ar: 'وشاح تخرج وقلم محفور وصورة مؤطرة للخريج في علبة هدايا ذهبية واحدة. أضف اسم الخريج ورسالة وحتى أربع صور للإطار.',
      ku: 'پشتێنی دەرچوون، پێنووسێکی هەڵکۆڵراو و وێنەیەکی چوارچێوەکراوی دەرچوو لە یەک سندوقی دیاریی زێڕیندا. ناوی دەرچوو، نامەیەک و تا چوار وێنە بۆ چوارچێوەکە زیاد بکە.',
    },
    categoryIds: ['graduation', 'packages', 'engraving'],
    price: 50000,
    compareAtPrice: 60000,
    availability: 'preparationDays',
    preparationDays: 2,
    salesCount: 110,
    viewCount: 1400,
    tags: ['graduation', 'graduate', 'sash', 'university', 'gift set'],
    giftFor: ['men', 'women'],
    optionGroups: [
      {
        id: 'sash-color',
        type: 'colorSwatch',
        label: { en: 'Sash Color', ar: 'لون الوشاح', ku: 'ڕەنگی پشتێن' },
        required: true,
        values: [C.black, C.navy, C.maroon, C.gold],
      },
      textGroup('graduate-name', { en: 'Graduate Name', ar: 'اسم الخريج', ku: 'ناوی دەرچوو' }, 50, true),
      textGroup('message', { en: 'Message', ar: 'الرسالة', ku: 'نامە' }, 100),
      photosGroup(1, 4),
      dateGroup({
        en: 'Graduation Date (Optional)',
        ar: 'تاريخ التخرج (اختياري)',
        ku: 'بەرواری دەرچوون (ئارەزوومەندانە)',
      }),
    ],
  },
];
