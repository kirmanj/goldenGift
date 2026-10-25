import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The analytics events the SRS requires (§4.7). Log only through this class so
/// event names stay consistent; parameters follow GA4 e-commerce naming.
class AnalyticsEvents {
  AnalyticsEvents._();

  static const signUp = 'sign_up';
  static const login = 'login';
  static const viewItem = 'view_item';
  static const addToCart = 'add_to_cart';
  static const addToWishlist = 'add_to_wishlist';
  static const beginCheckout = 'begin_checkout';
  static const purchase = 'purchase';
  static const aiSearch = 'ai_search';
  static const share = 'share';
  static const referralShare = 'referral_share';
  static const specialRequestSubmit = 'special_request_submit';

  /// Reels (SRS §5.27): a reel shown (once per reel per feed) / its product opened.
  static const reelView = 'reel_view';
  static const reelProductTap = 'reel_product_tap';
}

class AnalyticsService {
  AnalyticsService(this._analytics);

  final FirebaseAnalytics _analytics;

  /// Analytics must never break a user flow: failures are only logged in debug.
  Future<void> log(String name, [Map<String, Object>? parameters]) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (e) {
      if (kDebugMode) debugPrint('analytics: $name failed: $e');
    }
  }
}

final analyticsServiceProvider =
    Provider<AnalyticsService>((ref) => AnalyticsService(FirebaseAnalytics.instance));
