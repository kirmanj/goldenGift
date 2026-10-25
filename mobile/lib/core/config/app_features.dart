/// Product switches for features that are built but not offered yet.
/// Each can be turned on at build time without code changes, e.g.
///   flutter build web --dart-define=AI_GIFT_SEARCH=true
class AppFeatures {
  AppFeatures._();

  /// AI Gift Search (SRS §5.6): hidden for now (owner, 2026-10-22). Off removes
  /// the Home header bar and sends `/ai-gift-search` links to Home; the screen
  /// and the `aiGiftSearch` function stay in place for when it is switched on.
  static const bool aiGiftSearch = bool.fromEnvironment('AI_GIFT_SEARCH');
}
