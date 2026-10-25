import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../models/cart_item_model.dart';
import '../../../../models/product_model.dart';
import '../../../../models/store_model.dart';
import 'cart_controller.dart';

enum CartLineStatus {
  ok,

  /// Product gone, inactive, out of stock, its store suspended, or a chosen
  /// option no longer exists / is out of stock — shown in error red, excluded
  /// from totals (SRS §5.10).
  unavailable,

  /// Still orderable but the price moved since it was added; checkout uses the new price.
  priceChanged,
}

class CartLine {
  const CartLine(this.item, this.status, {this.currentUnitPrice});
  final CartItemModel item;
  final CartLineStatus status;
  final int? currentUnitPrice;

  bool get counts => status != CartLineStatus.unavailable;

  /// What the line costs now (new price when it changed).
  int get effectiveLineTotal => (currentUnitPrice ?? item.unitPrice) * item.qty;
}

class CartStoreGroup {
  const CartStoreGroup(this.storeId, this.lines, {this.store});
  final String storeId;
  final StoreModel? store;
  final List<CartLine> lines;
}

class CartSummary {
  const CartSummary(this.lines, this.groups);
  final List<CartLine> lines;

  /// One group per partner store; the UI shows store headers only when > 1.
  final List<CartStoreGroup> groups;

  int get subtotal => lines.where((l) => l.counts).fold(0, (total, l) => total + l.effectiveLineTotal);
  int get orderableCount => lines.where((l) => l.counts).fold(0, (n, l) => n + l.item.qty);
  bool get hasUnavailable => lines.any((l) => !l.counts);
  bool get canCheckout => orderableCount > 0;

  /// Longest preparation among orderable lines (earliest delivery date, SRS §5.11).
  int get maxPreparationDays =>
      lines.where((l) => l.counts).fold(0, (m, l) => l.item.preparationDays > m ? l.item.preparationDays : m);
}

/// Pure rule for one line against the live product (tested without Firebase).
CartLine resolveLine(CartItemModel item, ProductModel? product, {StoreModel? store}) {
  final storeClosed = store != null && store.status != StoreStatus.active;
  if (product == null || !product.isActive || product.isOutOfStock || storeClosed) {
    return CartLine(item, CartLineStatus.unavailable);
  }
  var unit = product.price;
  for (final s in item.selections) {
    if (s.valueId == null) continue;
    final group = product.optionGroups.where((g) => g.id == s.groupId).firstOrNull;
    final value = group?.valueById(s.valueId);
    if (value == null || (value.stock != null && value.stock! <= 0)) {
      return CartLine(item, CartLineStatus.unavailable);
    }
    unit += value.priceDelta;
  }
  if (product.stock != null && product.stock! < item.qty) {
    return CartLine(item, CartLineStatus.unavailable);
  }
  return unit == item.unitPrice
      ? CartLine(item, CartLineStatus.ok)
      : CartLine(item, CartLineStatus.priceChanged, currentUnitPrice: unit);
}

CartSummary summarize(List<CartItemModel> items, Map<String, ProductModel> products,
    {Map<String, StoreModel> stores = const {}}) {
  final lines = [for (final i in items) resolveLine(i, products[i.productId], store: stores[i.storeId])];
  final byStore = <String, List<CartLine>>{};
  for (final l in lines) {
    byStore.putIfAbsent(l.item.storeId, () => []).add(l);
  }
  return CartSummary(lines, [
    for (final e in byStore.entries) CartStoreGroup(e.key, e.value, store: stores[e.key]),
  ]);
}

/// Product ids in the cart as a stable key, so product docs reload only when
/// lines are added or removed (not on quantity changes).
final _cartProductKeyProvider = Provider<String>((ref) =>
    (ref.watch(cartControllerProvider).items.map((i) => i.productId).toSet().toList()..sort()).join(','));

final _cartStoreKeyProvider = Provider<String>((ref) =>
    (ref.watch(cartControllerProvider).items.map((i) => i.storeId).toSet().toList()..sort()).join(','));

Future<Map<String, T>> _byIds<T>(FirebaseFirestore db, String collection, String key,
    T Function(String id, Map<String, dynamic> data) parse) async {
  if (key.isEmpty) return {};
  final ids = key.split(',');
  final out = <String, T>{};
  for (var i = 0; i < ids.length; i += 30) {
    final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
    try {
      final snap = await db.collection(collection).where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        out[d.id] = parse(d.id, d.data());
      }
    } on FirebaseException catch (e) {
      // One unreadable doc (e.g. a store still pending approval is private,
      // SRS §6.17) denies the whole `in` query: read the others one by one.
      if (e.code != 'permission-denied') rethrow;
      for (final id in chunk) {
        try {
          final d = await db.collection(collection).doc(id).get();
          if (d.exists) out[d.id] = parse(d.id, d.data()!);
        } on FirebaseException catch (_) {
          // Treated as missing (the line shows as unavailable).
        }
      }
    }
  }
  return out;
}

final cartProductsProvider = FutureProvider<Map<String, ProductModel>>((ref) => _byIds(
    ref.watch(firestoreProvider), FirestorePaths.products, ref.watch(_cartProductKeyProvider), ProductModel.fromMap));

final cartStoresProvider = FutureProvider<Map<String, StoreModel>>((ref) => _byIds(
    ref.watch(firestoreProvider), FirestorePaths.stores, ref.watch(_cartStoreKeyProvider), StoreModel.fromMap));

/// Cart lines with live availability and totals; null while products load.
final cartSummaryProvider = Provider<AsyncValue<CartSummary>>((ref) {
  final cart = ref.watch(cartControllerProvider);
  if (cart.isLoading) return const AsyncValue.loading();
  final products = ref.watch(cartProductsProvider);
  final stores = ref.watch(cartStoresProvider).valueOrNull ?? const {};
  return products.whenData((p) => summarize(cart.items, p, stores: stores));
});
