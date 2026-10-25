# Golden Gift Mobile App

Package name: `golden_gift` (imports use `package:golden_gift/...`).
Flutter 3.x, Dart SDK >=3.0.0 <4.0.0. Scope: `../docs/GOLDENGIFT_SRS.md`.

## Tech Stack

- **State management:** Riverpod (`flutter_riverpod`) — NOT Bloc, NOT Provider
- **Navigation:** GoRouter — flat route list in `lib/core/router/app_router.dart`, no ShellRoute, no `refreshListenable`
- **Bottom nav:** `core/widgets/main_shell.dart` (IndexedStack: Home · Cart · Profile)
- **Backend:** Firebase Auth, Firestore, Storage, Messaging, Analytics, Functions, App Check
- **Localization:** ARB files in `assets/lang/` → `flutter gen-l10n` → `lib/l10n/` (never edit generated files)

## Architecture (feature-first)

```
lib/
  core/        constants, providers, router, services, theme, utils, widgets
  features/    {feature}/data/datasources · presentation/{providers,screens,widgets}
  models/      shared data models (ProductModel, OrderModel, …) — fromMap/toMap, trilingual fields
  l10n/        generated
```

Feature folders (one per SRS §5 section): auth, home, categories, products, product_details, search, ai_search, cart, checkout, orders, wishlist, profile, addresses, wallet, referrals, gift_cards, special_requests, secret_santa, promo_codes, notifications, support, partners (Become a Partner), reviews. (Seller features live only in the admin dashboard — SRS §1.3.)

## Design System — Gold & White / Gold & Black (mandatory)

| What | File |
|------|------|
| Colors | `core/theme/app_colors.dart` — `AppColors.primary` (#C9A227 gold), `accent`, `primarySoft`, `headerGradient`, theme-aware helpers `AppColors.card/text/textMuted/field/line/soft/gold(context)`; gold **text** (prices, links) uses `AppColors.goldText(context)` |
| Spacing / radii / shadows | `core/theme/app_spacing.dart` — `AppSpacing.md`, `AppRadius.pill`, `AppElevation.card` |
| Typography | `core/theme/app_text_styles.dart` |
| Theme | `core/theme/app_theme.dart` |

- Buttons, inputs, chips and the search bar are **pill-shaped** (`AppRadius.pill`). Cards use `AppRadius.lg`.
- Gold = CTA buttons, active nav, Home header gradient, prices, discount/featured badges, links, selected chip border. Never gold page backgrounds.
- Light mode: gold on white. Dark mode: gold on black (`ThemeMode` from `themeModeProvider`, default system). Every new screen is reviewed in BOTH modes; use the `AppColors.*(context)` helpers instead of light-only constants.
- Text on gold surfaces is dark (`AppColors.textOnPrimary`, full strength — no alpha), never white (contrast).
- Tap targets ≥ `AppSpacing.minTapTarget` (48 dp, Android; covers Apple's 44 pt): icon buttons keep their visual size and pad the hit area (`GGCircleButton`); pills and text buttons are 48 tall. Icon-only controls need a `tooltip` / semantics label; decorative tappables (page dots, "tap outside" detectors) are excluded from semantics.
- `Color.withValues(alpha: x)`, not `withOpacity`.
- Screen padding `AppSpacing.screenPadding`. Product grid = 2 columns, gap `AppSpacing.gridGap`.
- Currency: `CurrencyFormatter.format()` (IQD, 0 decimals).
- Fonts: Nunito (en), Vazirmatn (ar/ckb) via `AppTextStyles.fontFamily(locale)`.

## Reusable widgets (built in Phase 1) — always reuse
`GGAppBar` (back circle + centered title + optional cart icon), `PrimaryButton`, `OutlineButton`, `GGInput`, `GGSearchBar`, `CategoryChip`, `CategoryTile`, `ProductCard`, `SectionHeader` (title + "View All"), `BannerCarousel`, `InfoBanner` (warning/success), `EmptyState`, `ErrorState`, `SkeletonLoader`, `WishlistHeart`, `PriceText`, `DiscountBadge`, `FeaturedBadge`, `GGLogo` (placeholder until final brand assets). Import them all via `core/widgets/widgets.dart`. In debug builds, `/dev/gallery` shows every widget with light/dark and en/ar/ckb toggles (button on any placeholder screen) — check new widgets there in all six combinations.

## Models & shared logic
- `lib/models/` — `ProductModel` (+ `OptionGroup`, `OptionValue`), `CartItemModel` (+ `CartSelection`; unit price = price + Σ priceDelta, line total = unit × qty), `CategoryModel`, `BannerModel`, `UserModel`, `app_settings_model.dart`. Parse with `fromMap(id, map)`; numbers/dates/enums are read tolerantly via `core/utils/firestore_parse.dart`.
- Trilingual fields are `LocalizedText` (stored as `title` / `titleAr` / `titleKu`); show them with `text.of(context)` (`core/utils/localized_text_ext.dart`).
- `UserModel.toProfileMap()` is the only map the app writes to `users/{uid}` — it excludes server-owned fields (SRS AUTH-3, §6.17).
- Search keywords: `core/utils/search_tokenizer.dart` — must stay identical to `functions/src/shared/searchTokenizer.ts`; both are tested against `test/fixtures/search_tokenizer_cases.json`.
- Analytics: log only through `analyticsServiceProvider` with `AnalyticsEvents.*` (SRS §4.7).
- Cloud Functions from repositories: take a `CallableInvoker` (`core/services/callable.dart`, `callableInvokerProvider`) so tests pass a fake; map `FirebaseFunctionsException` to a feature failure enum (`OrderFailure`, `RedeemFailure`, …) where `not-found` / `unavailable` / `internal` = "function not deployed" and the UI degrades gracefully.
- Picked photos are uploaded with `core/services/image_upload_service.dart` (`{folder}/{n}.jpg`); pick them with `photoServiceProvider.pick`.
- Shared business rules with a TS twin are checked against one JSON fixture in `test/fixtures/` (search tokenizer, product query keys, promo rules `promo_cases.json`, checkout rules) — change both sides together.

## Auth & session (Phase 2)
- Startup: `features/onboarding/.../startup_decider.dart` → maintenance → forced update → signed in (profile? main : complete profile) → onboarding → guest → Sign In / Sign Up. The router starts at `/` (splash); no `refreshListenable` — screens navigate explicitly with `context.go`.
- Phone codes: OTPIQ (WhatsApp first, SMS fallback) via the `sendOtp` / `verifyOtp` / `changePhone` functions — `verifyOtp` returns a custom token the app signs in with (`AuthRepository.confirmCode`). No Firebase Phone Auth, no reCAPTCHA. On the emulator the functions never send anything: the code is logged and mirrored to `otp_debug/{digits}` (set `OTP_REAL_SMS=true` on the emulator to test real delivery with the key in `functions/.secret.local`). Production key: `firebase functions:secrets:set OTPIQ_API_KEY` (needs Blaze).
- Sign-in data path: `AuthRepository` (phone OTP functions, Google, Apple-on-iOS) → `AuthFlow.afterSignIn` → returning user → Main; new user → `UserRepository.create` (`UserModel.toCreateMap`, exactly the keys the production rules allow) → `onUserCreate` adds wallet, referral code, `referredBy`. The app never writes server-owned user fields.
- Guard account-only actions with `if (!await requireSignIn(context, ref)) return;` (shows "Sign in to continue", SRS AUTH-5).
- Logout = `authFlowProvider.signOut()` (clears `cart_*` prefs + guest flag, keeps language/theme). Account deletion = `UserRepository.deleteAccount()` → `deleteAccount` callable.
- Validation before any Firebase call: `core/utils/validators.dart` (AUTH-8); messages via the `AuthMessages` extension on `AppLocalizations`.
- Tests: fakes in `test/helpers/auth_fakes.dart`, router harness `test/helpers/auth_test_app.dart`. Real end-to-end sign-up (all 3 languages) against the emulators: `integration_test/auth_e2e_test.dart` (instructions at the top of the file).
- Google sign-in needs the Google provider enabled in the Firebase console, then `flutterfire configure` re-run (adds the iOS client id / Android OAuth client). Sign in with Apple needs the capability on an Apple Developer team.

## Catalogue & search (Phase 3)
- A products list is a `ProductQuery` (value equality; round-trips through `/products?…` via `AppRoutes.productsFor`) watched through `productListControllerProvider(query)` (20 per page, `loadMore`, `refresh`).
- Engine choice lives in `ProductSearchRepository`: no text → ONE Firestore query (`FirestoreProductSource.buildQuery`); text → Algolia when `app_settings/search` has an app id + search-only key, otherwise (or when Algolia fails) Firestore `searchKeywords` — which can't also apply category/city, flagged by `ignoredFilters`.
- Firestore allows one array filter per query, so products carry derived fields maintained by the `onProductWrite` function: `cityKeys` (`all` when unrestricted), `catCityKeys` (`category|city`), `priceBand` (0–4), `hasDiscount`. Key formats: `ProductKeys`, `PriceBands` — checked against `test/fixtures/product_query_keys.json` on both the Dart and TS side. Every new query shape needs its composite index in `firestore.indexes.json`.
- Home sections are separate live providers (`home_providers.dart`), cache-first; keep Home ≤ 60 document reads (SRS §8): every section query has a `limit` (banners 8, categories 10, 3 × 6 products, gift cards 4, Discover 20); the bell reads the newest 20 notifications. `test/qa/home_reads_test.dart` counts the reads.
- Offline: `isOfflineProvider`; show the `OfflineChip`.
- Coming soon categories (SRS §5.7a): `categories/{id}.comingSoon` (+ trilingual `comingSoonNote`); a child of a coming-soon parent counts too. Helpers `comingSoonCategoryIn` / `comingSoonIdsIn` / `availableCategoriesIn` (`categories_providers.dart`). The gate lives in `ProductsScreen` (so tiles, chips, banners and deep links all land on `ComingSoonCategoryPage`); Discover shows `ComingSoonInlineCard`; `CategoryTile` / `CategoryChip` take `comingSoon:` ("Soon" pill). The page's hero loops unless `MediaQuery.disableAnimations` — widget tests that `pumpAndSettle` on it pass `disableAnimations: true` to `pumpCatalogueApp`.

## Localization notes
Flutter has no Material/Widgets localizations for Kurdish (`ckb`): `core/localization/kurdish_fallback_localizations.dart` serves Arabic system strings + RTL for `ckb`. Keep those delegates before the `Global*` ones in `main.dart`. `intl` has no `ckb` date data either — format dates for Kurdish through a helper, never `DateFormat(…, 'ckb')`.

## Gift types & Reels (Phase 11)
- Gift types (SRS §5.8a): `GiftAudience { men, women, companies }`, `products.giftFor[]`. Labels / icons via the `GiftAudienceUi` extension (`features/products/presentation/gift_audience_ui.dart`). `ProductQuery.giftFor` (URL `for=`) filters through the derived `forKeys` (`ProductKeys.forKey/forAnyOf`; gift type × category × city in one array filter). Home "Shop for" row = `HomeShopForSection` (no reads); Product Details pills = `GiftForPills`.
- Reels (SRS §5.27): the 4th MainShell tab. Tab ids are stable `MainTab` constants (`app_router.dart`: 0 Home, 1 Cart, 2 Profile, 3 Reels) while the visual order is Home · Reels · Cart · Profile — never use a raw index. `ReelsScreen` (dark theme in both modes) is built on first open; `ReelsFeed` owns the `VideoPlayerController`s (current ± 1, released after the frame) and plays only while the tab is active, the app is resumed and the Main route is current. Feed query: `ReelsRepository.buildQuery` (`visible == true` + `filterKeys` + `priceBand in`, `createdAt desc`, 8 per page). Reel docs carry product-derived fields (`ReelDerived`, shared fixture `reelKeys` in `test/fixtures/product_query_keys.json`).
- Tests: install `FakeVideoPlayerPlatform` (`test/helpers/fake_video_player.dart`) before pumping anything that shows Reels — the QA harness does it in `pumpQaApp`.

## Running against the emulators
`flutter run --dart-define=USE_EMULATOR=true` connects Auth, Firestore, Storage and Functions to the local Emulator Suite (`firebase emulators:start` from the repo root). On a physical device add `--dart-define=EMULATOR_HOST=<your Mac's LAN IP>`. Functions are always called in `europe-west1` (`functionsProvider`).

## QA guards (Phase 10)
`test/qa/` keeps the Phase 10 QA pass from regressing — run them alone with `flutter test test/qa` (≈ 2½ min, ~1,560 tests; part of the normal `flutter test`):
- `route_sweep_test.dart` — every route of the real router (`buildAppRouter`, `GoldenGiftApp`, `MaxWidthFrame`) on a seeded world (`qa_harness.dart` → `seedQaWorld`, real Nunito / Vazirmatn fonts) in {en, ar, ckb} × {light, dark} × {390×844, 320×640 @130 %}, plus guest mode, an empty world (every empty state) and a 1024×1366 tablet pass; scrolls every list to the end and fails on any FlutterError (overflow, exception, missing l10n) or on text showing a raw key / "null" / `{placeholder}`. A new route must be added to `sweepRoutes` (a coverage test checks).
- `sheets_sweep_test.dart` — every bottom sheet, dialog and popup menu in the same matrix, plus 48 dp / labelled tap targets.
- `accessibility_test.dart` — Android 48 dp + iOS 44 pt tap targets, labelled tap targets and WCAG AA text contrast on the main screens (en/ar × light/dark, scrolled), tap targets + labels on every route. Uses flutter_test's square-glyph font on purpose (accurate contrast sampling).
- `l10n_completeness_test.dart` — every en key in ar/ckb with the same placeholders, valid ICU plural/select, nothing left in English / mostly Latin, no Arabic letters in Kurdish (ك ي) or Kurdish letters in Arabic, no duplicate keys, `untranslated.txt` empty.
- `design_tokens_test.dart` — static scan of lib/: no hardcoded colours / `Colors.*` / `withOpacity`, no raw `TextStyle(fontSize:)`, spacing / radius literals, physical (non-directional) padding / alignment / positions, network images outside `GGNetworkImage`, `Image.memory` without `cacheWidth`, `shrinkWrap`, `DateFormat` / `NumberFormat` outside their helpers, hardcoded UI strings. Justified exceptions live in its `_allowed` map with a reason.
- `home_reads_test.dart` — the SRS §8 read budget, measured with `firestore_read_counter.dart` over a catalogue larger than every section.
