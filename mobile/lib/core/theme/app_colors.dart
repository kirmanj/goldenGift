import 'package:flutter/material.dart';

/// Golden Gift palette — Gold & White (light) / Gold & Black (dark).
///
/// Gold carries the brand: primary CTA buttons, active nav item, the Home
/// header card, prices, badges and links. Everything else stays white
/// (light mode) or near-black (dark mode) so the gold reads as a deliberate
/// accent. Text placed ON gold is always dark (`textOnPrimary`) — white on
/// gold fails contrast.
class AppColors {
  AppColors._();

  // ══════════════════════════════════════════════════════════
  //  BRAND — GOLD
  // ══════════════════════════════════════════════════════════

  /// Primary brand gold — buttons, active states, prices.
  static const Color primary = Color(0xFFC9A227);

  /// Lighter accent gold — hover / pressed / gradient end / dark-mode primary.
  static const Color accent = Color(0xFFE3C04A);

  /// Deep gold — gradient start on the Home / Wallet / Invite headers.
  static const Color primaryDark = Color(0xFF9C7A14);

  /// Soft gold tint — selected chips, info cards, icon backgrounds (light).
  static const Color primarySoft = Color(0xFFFBF4DC);

  /// Soft gold tint for dark mode (gold at low alpha on black).
  static const Color primarySoftDark = Color(0xFF2E2710);

  /// Gold for TEXT smaller than 18 px bold on light surfaces (prices, links,
  /// outline-button labels, active nav label): ≈5:1 on white. Brand gold
  /// #C9A227 is only ≈2.4:1, so SRS §8 reserves it for fills, icons, borders
  /// and ≥18 px bold text. Use [goldText] rather than this constant.
  static const Color goldTextLight = Color(0xFF8A6A0F);

  /// Text/icon colour used ON gold surfaces (buttons, header gradient).
  static const Color textOnPrimary = Color(0xFF1F1A08);

  /// Header gradient (Home greeting card, Wallet / Invite & Earn headers).
  static const LinearGradient headerGradient = LinearGradient(
    colors: [primaryDark, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Metallic shimmer gradient for the logo / gift-card tiles.
  static const LinearGradient goldShimmer = LinearGradient(
    colors: [Color(0xFF9C7A14), Color(0xFFE3C04A), Color(0xFFC9A227)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ══════════════════════════════════════════════════════════
  //  LIGHT THEME — Gold on White
  // ══════════════════════════════════════════════════════════

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  /// Page background.
  static const Color background = Color(0xFFFAFAF7);

  /// Cards, sheets, app bar.
  static const Color surface = Color(0xFFFFFFFF);

  /// Inputs, chips, category tiles.
  static const Color surfaceSecondary = Color(0xFFF3F2EC);

  /// Dividers / card outlines.
  static const Color border = Color(0xFFE6E3D8);

  static const Color textPrimary = Color(0xFF1E1E2A);
  static const Color textSecondary = Color(0xFF6B6F80);
  static const Color textHint = Color(0xFF9CA0B0);

  // ══════════════════════════════════════════════════════════
  //  DARK THEME — Gold on Black
  // ══════════════════════════════════════════════════════════

  static const Color darkBackground = Color(0xFF0E0E0F);
  static const Color darkSurface = Color(0xFF1A1A1C);
  static const Color darkSurfaceSecondary = Color(0xFF242427);
  static const Color darkBorder = Color(0xFF343438);
  static const Color darkTextPrimary = Color(0xFFF4F1E8);
  static const Color darkTextSecondary = Color(0xFFB0ADA3);
  static const Color darkTextHint = Color(0xFF7C7A73);

  // ══════════════════════════════════════════════════════════
  //  SEMANTIC
  // ══════════════════════════════════════════════════════════

  static const Color success = Color(0xFF2E9E5B);
  static const Color successSoft = Color(0xFFE8F6EE);
  static const Color warning = Color(0xFFE08A1E);
  static const Color warningSoft = Color(0xFFFFF4E5);
  static const Color error = Color(0xFFD32F2F);
  static const Color errorSoft = Color(0xFFFDECEC);
  static const Color info = Color(0xFF2F6FD3);

  /// Gift-card tiles on Home.
  static const LinearGradient giftCardGradient = goldShimmer;

  // ══════════════════════════════════════════════════════════
  //  THEME-AWARE HELPERS
  // ══════════════════════════════════════════════════════════

  static bool isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color bg(BuildContext c) => isDark(c) ? darkBackground : background;
  static Color card(BuildContext c) => isDark(c) ? darkSurface : surface;
  static Color field(BuildContext c) =>
      isDark(c) ? darkSurfaceSecondary : surfaceSecondary;
  static Color line(BuildContext c) => isDark(c) ? darkBorder : border;
  static Color text(BuildContext c) => isDark(c) ? darkTextPrimary : textPrimary;
  static Color textMuted(BuildContext c) =>
      isDark(c) ? darkTextSecondary : textSecondary;
  static Color soft(BuildContext c) => isDark(c) ? primarySoftDark : primarySoft;
  /// Brand gold for fills, icons, borders, indicators.
  static Color gold(BuildContext c) => isDark(c) ? accent : primary;

  /// Gold for text (see [goldTextLight]); bright gold on dark surfaces.
  static Color goldText(BuildContext c) => isDark(c) ? accent : goldTextLight;
}
