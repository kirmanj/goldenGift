# Golden Gift — Brand Assets

Master emblem: a square gift box formed by two mirrored **G** letters with a faceted ribbon bow on the lid, in bevelled metallic gold. Wordmark: **GOLDEN GIFT** in Cinzel Bold, tagline **PERSONALIZED GIFTS** in Cinzel Regular.

All raster files are exported from the SVG masters in `svg/`. Edit the SVG, never the PNGs.

## Folder map

| Folder | Contents | Use |
|---|---|---|
| `svg/` | `gg_emblem_{black,white,transparent}.svg`, `gg_lockup_{black,white}.svg`, `gg_wide_{black,white}.svg` | Source of truth; print, web, Figma |
| `png/` | Each variant at `@2x` (2048 / 3200 px master) plus 1024 · 512 · 256 · 128 (square) and 1600 · 800 · 400 (wide); `icon_master_{black,white,transparent}.png` (emblem trimmed to fill 76 % of a 1024 square) | Marketing, in-app images, social |
| `app-icons/ios/` | `AppIcon-1024.png` + 20…180 px sizes | Xcode `AppIcon.appiconset` (or let `flutter_launcher_icons` generate from `AppIcon-1024.png`) |
| `app-icons/android/` | `ic_launcher_foreground.png` (1024, transparent, emblem inside the 66 % safe zone), `ic_launcher_background.png` (solid `#0E0E0F`), `ic_launcher_legacy_512.png`, `mipmap-*/ic_launcher.png` | Adaptive icon + legacy fallback |
| `app-icons/store/` | `app_store_1024.png`, `play_store_512.png` | Store listings |
| `web/` | `favicon.ico` (16/32/48), `icon-16…512.png`, `apple-touch-icon.png` (180), `og-image-{dark,light}.png` (1200 w) | Flutter web `web/` folder, PWA manifest, admin dashboard, link previews |
| `splash/` | `splash_ios_{dark,light}.png` (1242×2688), `splash_android_{dark,light}.png` (1080×1920), `splash_logo_512.png` (transparent emblem) | Launch screens / `flutter_native_splash` |

## Colours

| Token | Hex | Use |
|---|---|---|
| Gold (primary) | `#C9A227` | Flat gold for UI (buttons, icons, text) |
| Gold accent | `#E3C04A` | Highlights, dark-mode primary |
| Gold deep | `#9C7A14` | Shadows, gradient start |
| Gold highlight | `#F6E7A1` | Gradient top, specular line |
| Black (dark bg) | `#0E0E0F` | Dark-mode background, icon background |
| White (light bg) | `#FFFFFF` | Light-mode background |
| Tagline on dark | `#CFC6A8` | |
| Tagline on light | `#6B6F80` | |

Metallic gradient (SVG `#gold`): `#F6E7A1 → #D4AF37 → #9C7A14 → #E3C04A → #B8921F`, 45°.

## Typography

- Wordmark: **Cinzel Bold**, letter-spacing ≈ 0.16 em, all caps.
- Tagline: **Cinzel Regular**, letter-spacing ≈ 0.4 em, all caps.
- In-app UI fonts stay Nunito (en) / Vazirmatn (ar, ckb) — Cinzel is for the logo only.

## Clear space & minimum size

- Clear space around the lockup = height of the bow on every side.
- Emblem alone: minimum 24 px (use `icon_master_*` at ≤ 64 px).
- Lockup (emblem + wordmark): minimum 120 px wide; below that use the emblem only.
- Wide lockup: minimum 160 px wide (app bar: use `gg_wide_*` at 32–40 px tall).

## Do / Don't

- Use the gold-on-black or gold-on-white versions only; do not recolour the gold.
- Do not add a stroke, drop shadow or glow beyond what is in the files.
- Do not stretch, rotate or place on busy photos without the black/white plate.
- Do not reproduce the wordmark in another typeface.

## Wiring into the Flutter apps

**Mobile (`mobile/pubspec.yaml`)**
```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: ../branding/app-icons/ios/AppIcon-1024.png
  adaptive_icon_foreground: ../branding/app-icons/android/ic_launcher_foreground.png
  adaptive_icon_background: "#0E0E0F"
  remove_alpha_ios: true
  web:
    generate: true
    image_path: ../branding/web/icon-512.png
    background_color: "#0E0E0F"
    theme_color: "#C9A227"
```
Then `dart run flutter_launcher_icons`.

**In-app** — `mobile/assets/images/` holds `logo.png` (emblem on black), `logo_transparent.png`, `logo_wide_dark.png`, `logo_wide_light.png`. Use the `GGLogo` widget (`lib/core/widgets/gg_logo.dart`) which picks the right file for the current theme.

**Splash** — `flutter_native_splash` config:
```yaml
flutter_native_splash:
  color: "#FFFFFF"
  color_dark: "#0E0E0F"
  image: ../branding/splash/splash_logo_512.png
  image_dark: ../branding/splash/splash_logo_512.png
```

**Web / admin** — copy `web/favicon.ico`, `web/icon-192.png`, `web/icon-512.png`, `web/apple-touch-icon.png` into each project's `web/` folder and reference them in `manifest.json` / `index.html`.
