# Golden Gift — Personalized Gifts Marketplace

Multi-vendor personalized-gift e-commerce platform for Iraq / Kurdistan. Flutter monorepo with two independent sub-projects sharing one Firebase backend. Structure and conventions mirror the **BB** project (`~/AndroidStudioProjects/BB`).

**Single source of truth for scope and behaviour:** `docs/GOLDENGIFT_SRS.md` (same content in `docs/GoldenGift_SRS.docx`). Edit only the Markdown, then regenerate the .docx with `python3 docs/tools/build_srs_docx.py`. Implement phase by phase in the order defined there. Do not add features that are not in the SRS without updating the SRS first.

## Monorepo Structure

```
mobile/          # Flutter customer app (v1.0.0) — iOS, Android, Web
adminDashboard/  # Flutter web admin dashboard (v1.0.0) — Web only
docs/            # SRS, RELEASE.md, legal/ (privacy, terms), store/ (listings), design references
```

Both connect to Firebase project **`goldengift-iq`** (same Firestore, Auth, Storage).

## First-time setup on a new machine

Platform folders are committed; the Firebase config files (`firebase_options.dart`, `google-services.json`, `GoogleService-Info.plist`) are git-ignored, so regenerate them:

```bash
cd mobile && flutterfire configure --project=goldengift-iq --platforms=android,ios,web --android-package-name=com.goldengift.golden_gift --ios-bundle-id=com.goldengift.goldenGift --yes
cd adminDashboard && flutterfire configure --project=goldengift-iq --platforms=web --yes
cd mobile && flutter pub get && flutter gen-l10n
cd mobile/functions && npm install
```

## Quick Commands

```bash
cd mobile && flutter run                                   # against the real goldengift-iq project
cd mobile && flutter run --dart-define=USE_EMULATOR=true   # against the local emulators
cd mobile && flutter gen-l10n                              # after editing ARB files in assets/lang/
cd mobile && flutter analyze && flutter test
cd adminDashboard && flutter run -d chrome                 # web only

# Cloud Functions (mobile/functions — TypeScript, region europe-west1)
cd mobile/functions && npm run build && npm run typecheck && npm test   # incl. enum/path/tokenizer parity with the Dart files

# Emulators (repo root). firebase-tools 15 needs Java 21+; Android Studio's bundled JBR works:
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"                         # firebase-tools runs `java` from PATH
firebase emulators:start --project goldengift-iq           # UI on http://localhost:4000

# Dev data seeder (firebase-admin, idempotent, refuses any project but goldengift-iq)
cd mobile/functions && npm run seed:emulator               # emulator must be running
cd mobile/functions && npm run seed:dev                    # REAL goldengift-iq (Application Default Credentials)
cd mobile/functions && npx tsx scripts/seed.ts --dry-run   # validate seed data only
firebase emulators:exec --only auth,firestore,storage --project goldengift-iq "npm --prefix mobile/functions test"   # functions + security-rules tests

python3 docs/tools/build_srs_docx.py                       # after editing the SRS Markdown
python3 docs/tools/build_legal_pages.py                    # docs/legal/*.md → mobile/web/privacy.html, terms.html

# Release (docs/RELEASE.md): bump `version:` in mobile/pubspec.yaml, then
git tag v1.0.0 && git push origin v1.0.0                   # → release-android (Play internal), release-ios (TestFlight), deploy-web
# Functions / indexes / production rules: Actions ▸ "Deploy · Functions" (manual; input deploy_rules)
cd mobile && flutter build appbundle --release             # local; signs with android/key.properties (else the debug key)
cd mobile && flutter build ipa --release                   # local; owner's Apple team in Xcode
firebase deploy --only hosting --project goldengift-iq     # after `flutter build web --release` in mobile/ and adminDashboard/
```

Deploying Cloud Functions and creating the default Storage bucket need the Blaze plan on `goldengift-iq`. Once the bucket exists, allow the dashboard (web) to load Storage images: `gsutil cors set mobile/storage.cors.json gs://<bucket>`. CI (`.github/workflows/ci.yml`) analyzes and tests both apps and the functions on every push/PR. **Releases** — workflows, every GitHub secret, owner setup (signing keys, Play / App Store, App Check, `goldengift.app` domain, universal links), the pre-release checklist and rollback — are in `docs/RELEASE.md`; store texts and privacy answers in `docs/store/listing.md`; legal drafts in `docs/legal/`.

## Tech Stack (mandatory)

- Flutter 3.x / Dart >=3.0.0, **Riverpod** (`flutter_riverpod`) — NOT Bloc, NOT Provider
- **GoRouter** flat route list; bottom nav is `MainShell` + `IndexedStack` (no ShellRoute), no `refreshListenable`
- Firebase: Auth (phone OTP, email, Google, Apple), Firestore, Storage, Messaging, Analytics, App Check
- Cloud Functions (`mobile/functions/`, Node 20 / TypeScript) for: AI Gift Search (Gemini), referral credit, order notifications, gift-card codes. Client must degrade gracefully when a function is unavailable.
- Localization: `en`, `ar` (RTL), `ckb` (Kurdish Sorani, RTL) — ARB files in `mobile/assets/lang/`. Admin dashboard is English only.
- Currency: **IQD** (0 decimals). Always `CurrencyFormatter.format()`.

## Shared Firestore Collections

Top-level: `users`, `stores`, `products`, `categories`, `orders`, `carts`, `wishlists`, `banners`, `promo_codes`, `gift_card_templates`, `gift_cards`, `wallets`, `referrals`, `special_requests`, `secret_santa_groups`, `notifications`, `reviews`, `ai_searches`, `app_settings`, `reels` (Phase 11)

Admin / functions only: `admins`, `admin_audit_log`, `function_runs` (idempotency markers, rate limits), `otp_codes` + `otp_throttle` (phone codes), `counters` (order numbers), `payment_sessions` (online payments; owner may read)

Collection paths are defined once in `mobile/lib/core/constants/firestore_paths.dart` (the dashboard re-exports it) and mirrored for Cloud Functions in `mobile/functions/src/shared/paths.ts`. If you add a collection, update both of those, the production rules and the SRS data model.

## Enums & paths — single definition, must NOT diverge

`OrderStatus`, `PaymentMethod`, `PaymentStatus`, `OptionType`, `ProductAvailability`, `ReferralStatus`, `SpecialRequestStatus`, `WalletTxnType`, `UserRole`, `CategoryType`, `BannerPlacement`, `BannerActionType`, `StoreStatus`, `GiftAudience` are defined ONCE in `mobile/lib/core/constants/app_constants.dart`, and Firestore paths once in `mobile/lib/core/constants/firestore_paths.dart`. The admin dashboard depends on the mobile package (`golden_gift: path: ../mobile`) and re-exports both (`adminDashboard/lib/core/constants/admin_constants.dart`, `firestore_paths.dart`), so it also uses the app's models, parsers and search tokenizer directly. Cloud Functions mirror them in `mobile/functions/src/shared/{enums,paths}.ts`; parity tests there fail the build if they diverge. Firestore stores the string values listed in SRS §6.15.

## Design System — Gold & White / Gold & Black

Brand: **Primary Gold `#C9A227`**, Accent Gold `#E3C04A`, Deep Gold `#9C7A14`, Soft Gold tint `#FBF4DC`. **Light mode = gold on white** (`#FFFFFF` cards, `#FAFAF7` background). **Dark mode = gold on black** (`#1A1A1C` cards, `#0E0E0F` background) — both modes are first-class and every screen must be checked in both. Gold is used for: primary CTA buttons, active nav icon + underline, header gradient card on Home, price text, badges, links. Gold *text* below 18 px bold (prices, links, outline-button labels) uses `AppColors.goldText(context)` (deep gold `#8A6A0F` in light mode for contrast); fills, icons and borders use `AppColors.gold(context)`. Text ON gold is always dark (`AppColors.textOnPrimary`), never white. Never hardcode colors, spacing, radii or text styles — use `core/theme/app_colors.dart` (theme-aware helpers `AppColors.card(context)`, `AppColors.text(context)`, `AppColors.gold(context)`), `app_spacing.dart`, `app_text_styles.dart`. Fonts: Nunito (en), Vazirmatn (ar/ckb).

## Firestore Rules

**Production rules are live** (Phase 10, deployed 2026-10-22): `firebase.json` points at `mobile/firestore.production.rules` and `mobile/storage.production.rules` (Storage deploys once the default bucket exists — Blaze). Every collection / storage path needs an explicit match — `mobile/functions/test/rules/rulesCoverage.test.ts` fails otherwise — and both files end in a catch-all deny. Emulator tests live in `mobile/functions/test/rules/`. Admin = claim `admin == true` **and** a live `admins/{uid}` doc with a staff role; seller = claim `seller == storeId` and a live active store they own. `mobile/firestore.rules` / `storage.rules` are the old dev-mode files, kept only for reference — never deploy them to goldengift-iq.
