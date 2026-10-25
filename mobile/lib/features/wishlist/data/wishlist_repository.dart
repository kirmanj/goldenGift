import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/utils/firestore_parse.dart';
import '../../../models/localized_text.dart';
import '../../../models/product_model.dart';

/// `wishlists/{uid}/items/{productId}` (SRS §5.15, §6.6). Every item belongs
/// to one list (`listId`, "default" unless the customer chose a named list).
class WishlistItem {
  const WishlistItem({
    required this.productId,
    required this.title,
    this.image,
    required this.price,
    this.listId = WishlistRepository.defaultList,
    this.addedAt,
  });

  final String productId;
  final LocalizedText title;
  final String? image;
  final int price;
  final String listId;
  final DateTime? addedAt;

  factory WishlistItem.fromMap(String id, Map<String, dynamic> map) => WishlistItem(
        productId: map['productId'] as String? ?? id,
        title: LocalizedText.fromMap(map, 'title'),
        image: FirestoreParse.stringOrNull(map['image']),
        price: FirestoreParse.integer(map['price']),
        listId: map['listId'] as String? ?? WishlistRepository.defaultList,
        addedAt: FirestoreParse.date(map['addedAt']),
      );
}

/// A named wishlist (SRS §5.15, Phase 9), stored in the `lists` array of
/// `wishlists/{uid}` as `{id, name, createdAt}`. The default list is implicit:
/// it always exists, is named by the app's translations and can be neither
/// renamed nor deleted.
class WishlistList {
  const WishlistList({required this.id, this.name = '', this.createdAt});

  static const defaultList = WishlistList(id: WishlistRepository.defaultList);

  final String id;

  /// Empty for the default list (the UI shows its translated name).
  final String name;
  final DateTime? createdAt;

  bool get isDefault => id == WishlistRepository.defaultList;

  factory WishlistList.fromMap(Map<String, dynamic> map) => WishlistList(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        createdAt: FirestoreParse.date(map['createdAt']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        // Server timestamps aren't allowed inside arrays.
        'createdAt': Timestamp.fromDate(createdAt ?? DateTime.now()),
      };

  @override
  bool operator ==(Object other) =>
      other is WishlistList && other.id == id && other.name == name && other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt);
}

class WishlistListException implements Exception {
  const WishlistListException(this.message);
  final String message;
  @override
  String toString() => 'WishlistListException: $message';
}

class WishlistRepository {
  WishlistRepository(this._db);
  final FirebaseFirestore _db;

  static const defaultList = 'default';
  static const maxListName = 40;
  static const maxLists = 20;

  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _db.collection(FirestorePaths.wishlistItems(uid));

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db.doc('${FirestorePaths.wishlists}/$uid');

  Stream<List<WishlistItem>> watch(String uid) => _items(uid)
      .orderBy('addedAt', descending: true)
      .snapshots()
      .map((s) => [for (final d in s.docs) WishlistItem.fromMap(d.id, d.data())]);

  /// Saves [product] to [listId] (the default list unless given). A product is
  /// in one list at a time, so saving it again moves it.
  Future<void> add(String uid, ProductModel product, {String listId = defaultList}) => _items(uid).doc(product.id).set({
        'listId': listId,
        'productId': product.id,
        ...product.title.toMap('title'),
        'image': product.mainImage,
        'price': product.price,
        'addedAt': FieldValue.serverTimestamp(),
      });

  Future<void> remove(String uid, String productId) => _items(uid).doc(productId).delete();

  // ── Named lists (Phase 9) ────────────────────────────────────────────────

  /// The default list first, then the named lists in creation order.
  Stream<List<WishlistList>> watchLists(String uid) => _doc(uid).snapshots().map((s) => withDefault(s.data()));

  /// Parses `wishlists/{uid}` into lists, the default always first.
  static List<WishlistList> withDefault(Map<String, dynamic>? data) {
    final named = [
      for (final m in FirestoreParse.mapList(data?['lists']))
        if (WishlistList.fromMap(m) case final l when l.id.isNotEmpty && !l.isDefault) l,
    ]..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    return [WishlistList.defaultList, ...named];
  }

  static String _cleanName(String name) {
    final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) throw const WishlistListException('empty name');
    return trimmed.length > maxListName ? trimmed.substring(0, maxListName) : trimmed;
  }

  /// Current named lists (the default excluded).
  Future<List<WishlistList>> _named(String uid) async =>
      withDefault((await _doc(uid).get()).data()).where((l) => !l.isDefault).toList();

  /// Replaces the whole `lists` array (an update keeps the doc's other
  /// fields; a merge would not replace the array). Lists are edited by their
  /// owner only, so a plain read-then-write is enough (no transaction).
  Future<void> _writeLists(String uid, List<WishlistList> lists) =>
      _doc(uid).set({'lists': [for (final l in lists) l.toMap()]}, SetOptions(mergeFields: ['lists']));

  /// Creates a named list and returns its id.
  Future<String> createList(String uid, String name) async {
    final clean = _cleanName(name);
    final lists = await _named(uid);
    if (lists.length >= maxLists) throw const WishlistListException('too many lists');
    final id = _doc(uid).collection('_').doc().id;
    // arrayUnion: a list created at the same time elsewhere is kept.
    await _doc(uid).set({
      'lists': FieldValue.arrayUnion([WishlistList(id: id, name: clean, createdAt: DateTime.now()).toMap()]),
    }, SetOptions(merge: true));
    return id;
  }

  Future<void> renameList(String uid, String listId, String name) async {
    if (listId == defaultList) throw const WishlistListException('the default list is fixed');
    final clean = _cleanName(name);
    final lists = await _named(uid);
    if (!lists.any((l) => l.id == listId)) throw const WishlistListException('no such list');
    await _writeLists(uid, [
      for (final l in lists) l.id == listId ? WishlistList(id: l.id, name: clean, createdAt: l.createdAt) : l,
    ]);
  }

  /// Deletes a named list; its gifts move to the default list.
  Future<void> deleteList(String uid, String listId) async {
    if (listId == defaultList) throw const WishlistListException('the default list is fixed');
    final items = await _items(uid).where('listId', isEqualTo: listId).get();
    // ≤ 500 writes per batch.
    const chunk = 450;
    for (var i = 0; i < items.docs.length; i += chunk) {
      final batch = _db.batch();
      for (final d in items.docs.skip(i).take(chunk)) {
        batch.update(d.reference, {'listId': defaultList});
      }
      await batch.commit();
    }
    await _writeLists(uid, (await _named(uid)).where((l) => l.id != listId).toList());
  }

  /// Moves a saved gift to another list.
  Future<void> moveItem(String uid, String productId, String listId) =>
      _items(uid).doc(productId).update({'listId': listId});
}

final wishlistRepositoryProvider =
    Provider<WishlistRepository>((ref) => WishlistRepository(ref.watch(firestoreProvider)));
