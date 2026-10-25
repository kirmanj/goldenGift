import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../models/cart_item_model.dart';
import '../../data/cart_stores.dart';

class CartState {
  const CartState({this.items = const [], this.isLoading = true, this.error});
  final List<CartItemModel> items;
  final bool isLoading;
  final Object? error;

  /// Badge on the Cart tab (SRS §5.3): total quantity.
  int get count => items.fold(0, (n, i) => n + i.qty);
}

/// The cart, wherever it lives (SRS §5.9, §5.10): local for guests, Firestore
/// once signed in. A guest's lines move into the account on sign-in, merging
/// identical configurations (SRS §2.1).
class CartController extends StateNotifier<CartState> {
  CartController({
    required CartStore Function(String uid) remoteStore,
    required CartStore localStore,
    AnalyticsService? analytics,
  })  : _remoteStore = remoteStore,
        _local = localStore,
        _analytics = analytics,
        super(const CartState());

  static const maxQty = 99;

  final CartStore Function(String uid) _remoteStore;
  final CartStore _local;
  final AnalyticsService? _analytics;

  CartStore? _store;
  String? _uid;
  bool _started = false;
  StreamSubscription<List<CartItemModel>>? _sub;

  CartStore get _active => _store ?? _local;

  /// Called with the signed-in uid (null for guests) whenever auth changes.
  Future<void> onAuthChanged(String? uid) async {
    if (_started && uid == _uid) return;
    final wasGuest = !_started || _uid == null;
    _started = true;
    _uid = uid;
    if (uid != null && wasGuest) await _mergeGuestCart(uid);
    _listen(uid == null ? _local : _remoteStore(uid));
  }

  void _listen(CartStore store) {
    _store = store;
    _sub?.cancel();
    _sub = store.watch().listen(
      (items) {
        if (mounted) state = CartState(items: items, isLoading: false);
      },
      onError: (Object e) {
        if (mounted) state = CartState(items: state.items, isLoading: false, error: e);
      },
    );
  }

  Future<void> _mergeGuestCart(String uid) async {
    try {
      final guestItems = await _local.read();
      if (guestItems.isEmpty) return;
      final remote = _remoteStore(uid);
      final existing = await remote.read();
      for (final item in guestItems) {
        final same = existing.where((e) => e.isSameConfiguration(item)).firstOrNull;
        if (same != null) {
          await remote.upsert(same.copyWith(qty: (same.qty + item.qty).clamp(1, maxQty)));
        } else {
          await remote.upsert(item);
        }
      }
      await _local.clear();
    } catch (e) {
      // Keep the guest cart; the next sign-in event retries the merge.
      if (kDebugMode) debugPrint('cart merge failed: $e');
    }
  }

  /// Adds a configured line; identical product + selections increments qty (SRS §5.9).
  Future<CartItemModel> add(CartItemModel item) async {
    final same = state.items.where((e) => e.isSameConfiguration(item)).firstOrNull;
    final saved = same != null ? same.copyWith(qty: (same.qty + item.qty).clamp(1, maxQty)) : item;
    await _active.upsert(saved);
    unawaited(_analytics?.log(AnalyticsEvents.addToCart, {
      'currency': 'IQD',
      'value': item.lineTotal,
      'items': [
        {'item_id': item.productId, 'price': item.unitPrice, 'quantity': item.qty},
      ],
    }));
    return saved;
  }

  Future<void> setQty(String itemId, int qty) async {
    final item = state.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;
    await _active.upsert(item.copyWith(qty: qty.clamp(1, maxQty)));
  }

  Future<void> remove(String itemId) => _active.remove(itemId);

  /// After an order is placed (Phase 6 `placeOrder` clears the server copy too).
  Future<void> clear() => _active.clear();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final localCartStoreProvider =
    Provider<CartStore>((ref) => LocalCartStore(ref.watch(sharedPreferencesProvider)));

final cartControllerProvider = StateNotifierProvider<CartController, CartState>((ref) {
  final controller = CartController(
    remoteStore: (uid) => FirestoreCartStore(ref.read(firestoreProvider), uid),
    localStore: ref.watch(localCartStoreProvider),
    analytics: ref.read(analyticsServiceProvider),
  );
  ref.listen(authStateProvider, (_, next) {
    if (!next.isLoading) controller.onAuthChanged(next.valueOrNull?.uid);
  }, fireImmediately: true);
  return controller;
});

final cartCountProvider = Provider<int>((ref) => ref.watch(cartControllerProvider.select((s) => s.count)));
