import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/services/analytics_service.dart';
import '../../../models/product_model.dart';

/// One product, live and cache-first (SRS §5.9). Emits null when it doesn't exist.
final productByIdProvider = StreamProvider.autoDispose.family<ProductModel?, String>((ref, id) => ref
    .watch(firestoreProvider)
    .doc(FirestorePaths.productDoc(id))
    .snapshots()
    .map((snap) => snap.exists ? ProductModel.fromMap(snap.id, snap.data()!) : null));

/// Public product link (SRS §4.6), opened in-app through the `/p/:id` route.
Uri productShareLink(String productId) => Uri.parse('https://goldengift.app/p/$productId');

/// System share sheet + `share` analytics event.
Future<void> shareProduct(WidgetRef ref, ProductModel product, String title) async {
  await Share.share('$title\n${productShareLink(product.id)}', subject: title);
  unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.share, {
    'content_type': 'product',
    'item_id': product.id,
    'method': 'system_share',
  }));
}

/// Device-local viewing history: how often each category was viewed (SRS §5.4
/// item 9 "For you": the user's most-viewed categories; guests get newest).
class ViewHistory extends StateNotifier<Map<String, int>> {
  ViewHistory(this._prefs) : super(_load(_prefs));

  static const key = 'view_history_categories';
  static const _maxCategories = 30;
  final SharedPreferences _prefs;

  static Map<String, int> _load(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(key);
      if (raw == null) return const {};
      return Map<String, int>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return const {};
    }
  }

  void recordView(ProductModel product) {
    if (product.categoryIds.isEmpty) return;
    final next = {...state};
    for (final c in product.categoryIds) {
      next[c] = (next[c] ?? 0) + 1;
    }
    // Keep the most viewed categories only.
    final kept = Map.fromEntries(
      (next.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(_maxCategories),
    );
    state = kept;
    _prefs.setString(key, jsonEncode(kept));
  }

  /// Most-viewed category, or null with no history.
  String? get topCategory {
    if (state.isEmpty) return null;
    return (state.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }
}

final viewHistoryProvider = StateNotifierProvider<ViewHistory, Map<String, int>>(
  (ref) => ViewHistory(ref.watch(sharedPreferencesProvider)),
);

/// Called once when Product Details opens: `view_item` + viewing history.
void recordProductView(WidgetRef ref, ProductModel product) {
  ref.read(viewHistoryProvider.notifier).recordView(product);
  unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.viewItem, {
    'currency': 'IQD',
    'value': product.price,
    'items': [
      {'item_id': product.id, 'price': product.price},
    ],
  }));
}
