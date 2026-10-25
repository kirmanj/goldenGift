import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/session_providers.dart';
import '../../../models/cart_item_model.dart';

/// Where cart lines live (SRS §5.9 Add to Cart, §6.5).
abstract class CartStore {
  Stream<List<CartItemModel>> watch();
  Future<List<CartItemModel>> read();
  Future<void> upsert(CartItemModel item);
  Future<void> remove(String itemId);
  Future<void> clear();
}

/// Signed-in customers: `carts/{uid}/items/{itemId}`.
class FirestoreCartStore implements CartStore {
  FirestoreCartStore(this._db, this.uid);
  final FirebaseFirestore _db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _items => _db.collection(FirestorePaths.cartItems(uid));

  List<CartItemModel> _parse(QuerySnapshot<Map<String, dynamic>> snap) {
    final items = [for (final d in snap.docs) CartItemModel.fromMap(d.id, d.data())];
    items.sort((a, b) => (a.addedAt ?? DateTime(0)).compareTo(b.addedAt ?? DateTime(0)));
    return items;
  }

  @override
  Stream<List<CartItemModel>> watch() => _items.snapshots().map(_parse);

  @override
  Future<List<CartItemModel>> read() async => _parse(await _items.get());

  @override
  Future<void> upsert(CartItemModel item) => _items.doc(item.id).set({
        ...item.toMap(),
        'addedAt': item.addedAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(item.addedAt!),
      });

  @override
  Future<void> remove(String itemId) => _items.doc(itemId).delete();

  @override
  Future<void> clear() async {
    final snap = await _items.get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}

/// Guests: a JSON list in SharedPreferences under a `cart_` key, so logout
/// clears it (SRS §2.1 "cart is kept locally and merged after sign-in", AUTH-6).
class LocalCartStore implements CartStore {
  LocalCartStore(this._prefs);
  final SharedPreferences _prefs;

  static const key = '${PrefsKeys.cartPrefix}items';
  final _changes = StreamController<List<CartItemModel>>.broadcast();

  @override
  Future<List<CartItemModel>> read() async => _readSync();

  List<CartItemModel> _readSync() {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .map((m) => CartItemModel.fromMap(m['id'] as String, m))
          .toList();
    } catch (_) {
      return []; // a corrupt local cart must never crash the app
    }
  }

  Future<void> _write(List<CartItemModel> items) async {
    await _prefs.setString(
      key,
      jsonEncode([
        for (final i in items)
          {...i.toMap(), 'id': i.id, 'addedAt': (i.addedAt ?? DateTime.now()).toIso8601String()},
      ]),
    );
    _changes.add(items);
  }

  @override
  Stream<List<CartItemModel>> watch() async* {
    yield _readSync();
    yield* _changes.stream;
  }

  @override
  Future<void> upsert(CartItemModel item) async {
    final items = _readSync();
    final i = items.indexWhere((x) => x.id == item.id);
    final stamped = item.addedAt == null ? item.copyWith(addedAt: DateTime.now()) : item;
    if (i >= 0) {
      items[i] = stamped;
    } else {
      items.add(stamped);
    }
    await _write(items);
  }

  @override
  Future<void> remove(String itemId) async => _write(_readSync()..removeWhere((x) => x.id == itemId));

  @override
  Future<void> clear() async {
    await _prefs.remove(key);
    _changes.add(const []);
  }
}
