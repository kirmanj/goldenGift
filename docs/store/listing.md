# Golden Gift — Store listings (App Store + Google Play)

Draft texts for App Store Connect and the Google Play Console (SRS §10 Phase 10), in English, Arabic and Kurdish (Sorani). Character counts were checked against each store's limit (shown as `n / limit`). Values in [square brackets] must be confirmed by the owner — launch cities (SRS §12 item 2) and the provisional amounts of §12 items 3 and 6. Kurdish and Arabic copy should get a native read-through before submission (SRS §8).

**Store languages.** Both stores offer Arabic as a listing language. As far as we know neither App Store Connect nor the Play Console offers Kurdish (Sorani) — check the language list when creating the listing. If it is still missing: use English as the primary listing, add the Arabic localization, and paste the short Kurdish paragraph ("Kurdish block" below) at the end of the English and Arabic full descriptions; the rest of the Kurdish copy is ready for the website, social posts and a future listing.

## Common facts

| Field | Value |
|---|---|
| App name | **Golden Gift** (same on both stores, matches the home-screen name) |
| Bundle ID / package | iOS `com.goldengift.goldenGift` · Android `com.goldengift.golden_gift` |
| Primary category | **Shopping** (App Store secondary: Lifestyle) |
| Price | Free (physical goods and gift cards are paid in the app with cash on delivery, the wallet or ZainCash — no in-app purchases of digital content) |
| Support URL | `https://goldengift.app/terms#en-s19` (contact section) until a dedicated support page exists — must show contact details (Apple requirement) |
| Marketing URL | `https://goldengift.app` |
| Privacy policy URL | `https://goldengift.app/privacy` (until goldengift.app is connected: `https://goldengift-iq.web.app/privacy`) |
| Account deletion URL (Play) | `https://goldengift.app/privacy#en-s7` |
| Copyright (App Store) | `© 2026 [legal entity name]` |
| Contact email | support@goldengift.app |
| Age / content | see "Content rating" |

## App Store (iOS)

### Name (≤ 30)

| Language | Text | Count |
|---|---|---|
| English | `Golden Gift` | 11 / 30 |
| Arabic | `Golden Gift` (or `غولدن غيفت`) | 11 / 30 |

### Subtitle (≤ 30)

| Language | Text | Count |
|---|---|---|
| English | `Personalized gifts, delivered` | 29 / 30 |
| Arabic | `هدايا مخصّصة حتى باب البيت` | 26 / 30 |
| Kurdish | `دیاریی تایبەت تا بەردەم دەرگا` | 29 / 30 |

### Promotional text (≤ 170, editable without a new build)

- **English** (156 / 170): Make it personal: add names, dates and photos, pick the delivery day and we'll bring the gift to their door. Gift cards, AI gift ideas and Secret Santa too.
- **Arabic** (140 / 170): اجعلها شخصية: أضف الأسماء والتواريخ والصور، واختر يوم التوصيل، وسنوصل الهدية إلى باب من تحب. وأيضًا بطاقات الهدايا وأفكار ذكية وسانتا السري.
- **Kurdish** (152 / 170): بیکە بە تایبەت: ناو، بەروار و وێنە زیاد بکە، ڕۆژی گەیاندن هەڵبژێرە و ئێمە دیارییەکە دەگەیەنینە بەردەم دەرگا. کارتی دیاری، بیرۆکەی زیرەک و سانتای نهێنیش.

### Keywords (≤ 100, comma-separated, no spaces after commas)

To be safe with non-Latin scripts (an Arabic letter is two bytes in UTF-8 and App Store Connect may count bytes), the Arabic and Kurdish lists are kept under 100 **bytes**.

| Language | Keywords | Count |
|---|---|---|
| English | `gifts,personalized,flowers,engraved,photo frame,gift card,birthday,surprise,Erbil,Baghdad,Iraq` | 94 / 100 |
| Arabic | `هدايا,ورود,هدية مخصصة,صورة,عيد ميلاد,بطاقة هدية,أربيل` | 53 chars / 97 bytes |
| Kurdish | `دیاری,گوڵ,تایبەت,وێنە,لەدایکبوون,کارتی دیاری,هەولێر` | 51 chars / 95 bytes |

The app name and subtitle are indexed already — don't repeat their words in the keywords.

### Description (≤ 4000) — the same text is used for Google Play's full description

See "Full description" below (English 1,732 / Arabic 1,534 / Kurdish 1,800 characters; + 167 with the Kurdish block).

### What's New (first release)

- **English:** First release of Golden Gift — personalized gifts delivered across Iraq and Kurdistan.
- **Arabic:** الإصدار الأول من غولدن غيفت — هدايا مخصّصة تصلك في كل أنحاء العراق وإقليم كوردستان.
- **Kurdish:** یەکەم وەشانی گۆڵدن گیفت — دیاریی تایبەت بۆ هەموو عێراق و هەرێمی کوردستان.

## Google Play

### App name (≤ 30)

| Language | Text | Count |
|---|---|---|
| English | `Golden Gift: Custom Gifts` | 25 / 30 |
| Arabic | `غولدن غيفت: هدايا مخصّصة` | 24 / 30 |
| Kurdish | `گۆڵدن گیفت: دیاریی تایبەت` | 25 / 30 |

### Short description (≤ 80)

| Language | Text | Count |
|---|---|---|
| English | `Personalized gifts, flowers & surprises delivered across Iraq and Kurdistan.` | 76 / 80 |
| Arabic | `هدايا مخصّصة وورود ومفاجآت تصلك في كل أنحاء العراق وإقليم كوردستان.` | 67 / 80 |
| Kurdish | `دیاریی تایبەت، گوڵ و سوپرایز بۆ هەموو عێراق و هەرێمی کوردستان.` | 62 / 80 |

### Graphics

App icon 512 × 512 PNG (32-bit, from the final logo — SRS §12 item 1), feature graphic 1024 × 500 (gold gradient `#9C7A14 → #E3C04A → #C9A227`, logo + "Personalized gifts, delivered" in dark `#1F1A08` text — never white on gold), screenshots as in the plan below.

## Full description (App Store description / Play full description, ≤ 4000)

### English

```text
Golden Gift is the easiest way to send a personal gift in Iraq and the Kurdistan Region. Choose from flowers, photo frames, engraved and printed gifts, handmade pieces, breakfast boxes and more — then make it theirs with names, dates, colours and your own photos.

WHY GOLDEN GIFT
• Personalize everything — add text, dates and photos, choose colours and sizes, and watch the price update as you go.
• Gifts for every occasion — birthdays, anniversaries, new babies, Eid, graduations, Mother's Day, or just because.
• Delivery you can plan — choose the day and time slot. Many gifts go out the same day; others tell you exactly how many days they need.
• AI Gift Search — describe the person ("my sister loves coffee and books, under 30,000 IQD") and get ideas in English, Arabic or Kurdish.
• Gift cards — design a card with your photo and message, then send it now or schedule it.
• Special requests — have an idea you can't find? Send it with photos and we'll quote it.
• Secret Santa — organise gift exchanges with family, friends or colleagues; the app draws names fairly.
• Wallet, credits and promo codes — earn credits by inviting friends and save with promo codes.
• Track every order — from confirmation to the door, with a notification at each step.
• Pay your way — cash on delivery, your Golden Gift wallet, or online payment where available.
• Three languages — English, Arabic and Kurdish (Sorani), in light and dark mode.

DELIVERY
We deliver to [Erbil, Sulaymaniyah, Duhok, Baghdad, Basra, Mosul and Kirkuk]. All prices are in Iraqi dinars (IQD).

SELL ON GOLDEN GIFT
Do you make handmade or personalized gifts? Apply to become a partner from the app.

Questions? Contact us in the app or at support@goldengift.app.
```

### Arabic

```text
غولدن غيفت هو أسهل طريقة لإرسال هدية شخصية في العراق وإقليم كوردستان. اختر من الورود وإطارات الصور والهدايا المحفورة والمطبوعة والمصنوعة يدويًا وصناديق الفطور وغيرها — ثم اجعلها خاصة بمن تحب بالأسماء والتواريخ والألوان وصورك الخاصة.

لماذا غولدن غيفت؟
• خصّص كل شيء — أضف النصوص والتواريخ والصور، واختر الألوان والمقاسات، وشاهد السعر يتحدّث مباشرة.
• هدايا لكل مناسبة — أعياد الميلاد، والذكرى السنوية، والمواليد الجدد، والعيد، والتخرّج، وعيد الأم، أو بلا مناسبة.
• توصيل تخطّط له — اختر اليوم والفترة الزمنية. كثير من الهدايا تُرسل في اليوم نفسه، وغيرها يوضّح لك عدد أيام التحضير.
• البحث الذكي عن الهدايا — صِف الشخص ("أختي تحب القهوة والكتب، بأقل من 30,000 دينار") واحصل على أفكار بالعربية أو الكوردية أو الإنجليزية.
• بطاقات الهدايا — صمّم بطاقة بصورتك ورسالتك، ثم أرسلها الآن أو حدّد موعدها.
• الطلبات الخاصة — لديك فكرة لا تجدها؟ أرسلها مع الصور وسنرسل لك عرض سعر.
• سانتا السري — نظّم تبادل الهدايا مع العائلة أو الأصدقاء أو الزملاء، ويجري التطبيق القرعة بعدل.
• المحفظة والمكافآت ورموز الخصم — اربح مكافآت بدعوة أصدقائك ووفّر برموز الخصم.
• تتبّع كل طلب — من التأكيد حتى الباب، مع إشعار في كل خطوة.
• ادفع كما يناسبك — الدفع عند الاستلام، أو محفظة غولدن غيفت، أو الدفع الإلكتروني حيث يتوفر.
• ثلاث لغات — العربية والكوردية (السورانية) والإنجليزية، بالوضعين الفاتح والداكن.

التوصيل
نوصل إلى [أربيل والسليمانية ودهوك وبغداد والبصرة والموصل وكركوك]. جميع الأسعار بالدينار العراقي (IQD).

بِع عبر غولدن غيفت
هل تصنع هدايا يدوية أو مخصّصة؟ قدّم طلب شراكة من التطبيق.

لديك سؤال؟ تواصل معنا من التطبيق أو عبر support@goldengift.app.
```

### Kurdish (Sorani)

```text
گۆڵدن گیفت ئاسانترین ڕێگایە بۆ ناردنی دیارییەکی تایبەت لە عێراق و هەرێمی کوردستان. لە گوڵ، چوارچێوەی وێنە، دیاریی هەڵکۆڵراو و چاپکراو، کاری دەستی، سندوقی نانی بەیانی و زۆر شتی تر هەڵبژێرە — پاشان بە ناو، بەروار، ڕەنگ و وێنەکانی خۆت بیکە بە هی ئەو کەسەی خۆشت دەوێت.

بۆچی گۆڵدن گیفت؟
• هەموو شتێک تایبەت بکە — دەق، بەروار و وێنە زیاد بکە، ڕەنگ و قەبارە هەڵبژێرە و گۆڕانی نرخەکە ڕاستەوخۆ ببینە.
• دیاری بۆ هەموو بۆنەیەک — ڕۆژی لەدایکبوون، ساڵیادی هاوسەرگیری، منداڵی تازە، جەژن، دەرچوون، ڕۆژی دایکان، یان بێ بۆنە.
• گەیاندنێک کە خۆت پلانی بۆ دادەنێیت — ڕۆژ و کات هەڵبژێرە. زۆرێک لە دیارییەکان هەمان ڕۆژ دەنێردرێن و ئەوانی تر ڕۆژانی ئامادەکردنیان پێت دەڵێن.
• گەڕانی زیرەکی دیاری — کەسەکە وەسف بکە ("خوشکەکەم قاوە و کتێبی خۆش دەوێت، کەمتر لە 30,000 دینار") و بە کوردی، عەرەبی یان ئینگلیزی بیرۆکە وەربگرە.
• کارتی دیاری — کارتێک بە وێنە و نامەی خۆت دیزاین بکە، پاشان ئێستا بینێرە یان کاتەکەی دیاری بکە.
• داواکاریی تایبەت — بیرۆکەیەکت هەیە و نایدۆزیتەوە؟ لەگەڵ وێنە بینێرە و نرخت بۆ دەنێرین.
• سانتای نهێنی — ئاڵوگۆڕی دیاری لەگەڵ خێزان، هاوڕێیان یان هاوکارانت ڕێکبخە؛ ئەپەکە بە دادپەروەری تیروپشک دەکات.
• جزدان، خاڵ و کۆدی داشکاندن — بە بانگهێشتکردنی هاوڕێکانت خاڵ کۆبکەرەوە و بە کۆدی داشکاندن پارە پاشەکەوت بکە.
• هەموو داواکارییەک بەدوادا بچۆ — لە پشتڕاستکردنەوەوە تا بەردەم دەرگا، لەگەڵ ئاگادارکردنەوە لە هەموو هەنگاوێکدا.
• بە شێوازی خۆت پارە بدە — پارەدان لە کاتی وەرگرتن، جزدانی گۆڵدن گیفت، یان پارەدانی ئۆنلاین لە شوێنی بەردەست.
• سێ زمان — کوردی (سۆرانی)، عەرەبی و ئینگلیزی، بە ڕووکاری ڕووناک و تاریک.

گەیاندن
بۆ [هەولێر، سلێمانی، دهۆک، بەغدا، بەسرە، مووسڵ و کەرکووک] دەگەیەنین. هەموو نرخەکان بە دیناری عێراقین (IQD).

لە گۆڵدن گیفت بفرۆشە
دیاریی دەستکرد یان تایبەت دروست دەکەیت؟ لە ئەپەکەوە داوای هاوبەشی بکە.

پرسیارت هەیە؟ لە ئەپەکەوە یان لە ڕێگەی support@goldengift.app پەیوەندیمان پێوە بکە.
```

### Kurdish block (to append to the English / Arabic description while the stores have no Kurdish listing)

```text
بە کوردی: گۆڵدن گیفت دیاریی تایبەت بە ناو، بەروار و وێنەکانی خۆت دروست دەکات و بۆ هەموو عێراق و هەرێمی کوردستان دەیگەیەنێت. ئەپەکە بە تەواوی بە کوردیی سۆرانی بەردەستە.
```

## Content rating

**Apple age rating questionnaire** — suggested answers (expected result: 4+; the questionnaire decides):
- Violence, sexual content, profanity, horror, drugs / alcohol / tobacco, gambling, contests, medical information: **None**. (Secret Santa is a name draw for gift exchanges, not gambling or a contest with prizes.)
- Unrestricted web access: **No** — external links (privacy, terms, WhatsApp, ZainCash pay page) open outside the app.
- User-generated content: product **reviews** with photos are shown to other users only after staff moderation; special-request and support messages go to Golden Gift staff only; there is no user-to-user chat. Answer accordingly (moderated UGC).
- Messaging / chat with other users: **No**.
- Age-assurance / parental controls: none.

**Google Play IARC questionnaire** — category "All other app types" (consumer store); suggested answers:
- No violence, fear, sexuality, gambling, language or controlled substances.
- Users can interact or exchange content: **Yes — reviews (moderated)**; no chat between users; users can't share their location with others.
- Digital purchases: the app sells **physical goods and gift cards** redeemable for those goods (not digital content) — answer per the questionnaire wording [owner to confirm].
- Expected rating: Everyone / PEGI 3 (possibly with the "Users Interact" notice).
- Target audience (Play "Target audience and content"): **18 and over** (not designed for children; avoid the Families policy) [owner to confirm, matches the Terms §2].

## Privacy answers (from docs/legal/privacy_policy.md)

### App Store "App Privacy" (nutrition label)

Tracking: **No** — no data is used to track users across other companies' apps or websites, no advertising SDKs, and the app never shows the App Tracking Transparency prompt.

| Data type | Collected | Linked to the user | Purposes |
|---|---|---|---|
| Contact Info — Name | Yes | Yes | App Functionality |
| Contact Info — Email Address | Yes (optional) | Yes | App Functionality |
| Contact Info — Phone Number | Yes | Yes | App Functionality (sign-in, delivery) |
| Contact Info — Physical Address | Yes | Yes | App Functionality (delivery) |
| User Content — Photos or Videos | Yes (photos for personalization, reviews, special requests, profile) | Yes | App Functionality |
| User Content — Customer Support | Yes (special-request / support messages) | Yes | App Functionality |
| User Content — Other User Content | Yes (reviews, gift messages, personalization text) | Yes | App Functionality |
| Identifiers — User ID | Yes | Yes | App Functionality |
| Identifiers — Device ID | Yes (random install ID for referral-fraud checks, push tokens) | Yes | App Functionality |
| Purchases — Purchase History | Yes (orders) | Yes | App Functionality, Analytics |
| Financial Info — Other Financial Info | Yes (wallet balance and credits) | Yes | App Functionality |
| Location — Precise Location | Only if the user places a map pin on an address (MAPS_ENABLED) | Yes | App Functionality |
| Location — Coarse Location | Yes (Google Analytics derives country / city from the IP address) | No | Analytics |
| Search History | Yes (AI Gift Search queries stored with the user ID; catalogue searches sent to Algolia) | Yes | App Functionality, Analytics |
| Usage Data — Product Interaction | Yes (Analytics events, §4.7) | No | Analytics |
| Diagnostics — Crash Data, Performance Data, Other Diagnostic Data | Yes (Crashlytics) | No | App Functionality, Analytics |
| Payment Info, Health, Fitness, Sensitive Info, Contacts, Emails or Text Messages, Browsing History, Audio, Gameplay, Advertising Data | No | — | — |

Notes: Contacts = **No** (the app never reads the address book; Secret Santa members and gift recipients are typed in by the user and are covered by Name / Phone Number). Payment Info = **No** (ZainCash collects wallet / card details on its own page). Re-check the label whenever a card gateway with saved cards (SRS §5.21) is enabled.

### Google Play "Data safety"

- Data collected: **Yes**. Data shared with third parties: **No** — service providers act on Golden Gift's behalf, and passing order details to the partner seller / courier is a transfer the user initiates by ordering (both are exempt from "sharing" in Google's definitions).
- Encrypted in transit: **Yes**. Users can request deletion: **Yes** — in the app (Profile ▸ Settings ▸ Delete account) and at `https://goldengift.app/privacy#en-s7`. Committed to the Families policy: **No**. Independent security review: **No**.

| Category — data type | Collected | Required / optional | Purposes |
|---|---|---|---|
| Personal info — Name | Yes | Required | App functionality, Account management |
| Personal info — Email address | Yes | Optional | Account management, Developer communications |
| Personal info — User IDs | Yes | Required | App functionality, Account management, Fraud prevention / security |
| Personal info — Address | Yes | Required to order | App functionality |
| Personal info — Phone number | Yes | Required | App functionality, Account management, Fraud prevention / security |
| Personal info — Other info (birthday, gender, city) | Yes | Optional | App functionality |
| Financial info — Purchase history | Yes | Required to order | App functionality, Analytics |
| Financial info — Other financial info (wallet, credits) | Yes | Required | App functionality |
| Location — Approximate location | Yes (Analytics, from IP) | Required | Analytics |
| Location — Precise location | Only with the address map pin | Optional | App functionality |
| Photos and videos — Photos | Yes | Optional | App functionality |
| Messages — Other in-app messages | Yes (special requests / support) | Optional | App functionality, Customer support |
| App activity — App interactions | Yes | Required | Analytics |
| App activity — In-app search history | Yes | Optional | App functionality, Analytics |
| App activity — Other user-generated content | Yes (reviews, gift messages, personalization text) | Optional | App functionality |
| App info and performance — Crash logs, Diagnostics | Yes | Required | Analytics |
| Device or other IDs | Yes (install ID, push tokens, Firebase installation ID) | Required | App functionality, Analytics, Fraud prevention / security |

Not collected: Financial info — payment info / credit score; Health; Contacts; Calendar; Audio; Files and docs; Web browsing; Emails / SMS.

## Screenshot plan

Taken by the owner once the final brand assets (SRS §12 item 1) are in the app, on the release build against production data (no "DRAFT" pages, no placeholder products). Same 8 screens per language; English and Arabic sets for the store listings (Kurdish set for the website / social until a Kurdish listing exists). Status bar clean (full battery, no carrier clutter), light mode unless noted.

| # | Screen | Caption — English | Caption — Arabic | Caption — Kurdish |
|---|---|---|---|---|
| 1 | Home (header card, categories, Popular) | Gifts made personal | هدايا بلمستك الخاصة | دیاری بە دەستی خۆت |
| 2 | Product details with options filled in (photos + text) | Add names, dates & photos | أضف الأسماء والتواريخ والصور | ناو، بەروار و وێنە زیاد بکە |
| 3 | Products list (chips, cards with discounts) | Gifts for every occasion | هدايا لكل مناسبة | دیاری بۆ هەموو بۆنەیەک |
| 4 | AI Gift Search results | Describe them, we find the gift | صِف من تحب ونجد الهدية | وەسفیان بکە، دیارییەکە دەدۆزینەوە |
| 5 | Gift Card Designer | Design a gift card in seconds | صمّم بطاقة هدية في ثوانٍ | لە چەند چرکەیەکدا کارتی دیاری دیزاین بکە |
| 6 | Checkout — delivery date & slot | Pick the day and time | اختر اليوم والوقت | ڕۆژ و کات هەڵبژێرە |
| 7 | Order details timeline | Follow every step | تابع كل خطوة | هەموو هەنگاوێک بەدوادا بچۆ |
| 8 | Home in **dark mode** (or Invite & Earn) | Beautiful in light and dark | جميل بالوضعين الفاتح والداكن | جوان لە ڕووناک و تاریکدا |

Sizes (portrait, PNG or JPEG, no transparency):

| Store / device | Size | Required? |
|---|---|---|
| App Store — iPhone 6.9" (16/17 Pro Max class) | 1320 × 2868 (1290 × 2796 also accepted) | **Yes** — the set Apple scales down for smaller iPhones |
| App Store — iPhone 6.7" | 1290 × 2796 | Covered by the 6.9" slot; upload separately only if it looks different |
| App Store — iPhone 6.5" | 1284 × 2778 or 1242 × 2688 | Optional |
| App Store — iPhone 5.5" | 1242 × 2208 | Optional (only if you want pixel-exact shots for older iPhones) |
| App Store — iPad 13" / 12.9" | 2064 × 2752 or 2048 × 2732 | **Yes** — the app runs on iPad (SRS §8: same layouts, content max 600 px wide) |
| Google Play — phone | 1080 × 1920 to 1080 × 2400 (9:16 – 9:20) | **Yes** — 2 to 8 |
| Google Play — 7" tablet | 1200 × 1920 | Recommended (tablet visibility) |
| Google Play — 10" tablet | 1600 × 2560 | Recommended |
| Google Play — feature graphic | 1024 × 500 | **Yes** |

Tip: simulators / emulators at those resolutions are fine (iPhone 17 Pro Max simulator for 6.9", iPad Pro 13" for iPad, a Pixel 9 Pro emulator for Play phone shots); add captions in a design tool on a gold-gradient band with dark text.

## Review notes (paste into App Review / Play "App access")

- Sign-in is by phone number with a one-time code sent by WhatsApp / SMS to Iraqi numbers, which reviewers cannot receive. Provide a **demo account** before submitting — see docs/RELEASE.md "App Review access" (owner + engineering item).
- Guests can browse the whole catalogue and AI Gift Search without an account; Sign in with Apple is available on iOS.
- Account deletion: Profile ▸ Settings ▸ Delete account.
- Payments are for physical goods delivered in Iraq (cash on delivery, wallet, ZainCash); gift cards are redeemable only for those goods, so no in-app purchase is used.
- Encryption: HTTPS only (exempt) — `ITSAppUsesNonExemptEncryption = NO`.
