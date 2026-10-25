import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/features/products/data/product_derived.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/store_model.dart';

import '../../../core/data/audit_log.dart';
import '../../../core/session/admin_session.dart';
import '../domain/product_draft.dart';

/// One page of the products table.
class ProductPage {
  const ProductPage(this.items, this.cursor, {required this.hasMore});
  final List<ProductModel> items;

  /// Last document read (start the next page after it); null when nothing was read.
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class RebuildResult {
  const RebuildResult({required this.scanned, required this.updated, required this.batches});
  final int scanned;
  final int updated;
  final int batches;
}

class ProductNotFoundException implements Exception {
  const ProductNotFoundException(this.id);
  final String id;

  @override
  String toString() => 'Product "$id" no longer exists.';
}

/// Reads and writes `products` for the dashboard (SRS §6.4, §9 "Products").
/// Every write is ONE batch that includes its `admin_audit_log` entry, and
/// always carries the derived query fields ([ProductDerived]) so the product is
/// queryable even before `onProductWrite` has run.
class ProductsAdminRepository {
  ProductsAdminRepository(this._db);
  final FirebaseFirestore _db;

  static const pageSize = 50;

  /// Firestore allows 500 writes per batch; the SRS caps ours at 400.
  static const maxBatchWrites = 400;

  /// Maintained by the app / functions; the editor never overwrites them.
  static const counterFields = {'salesCount', 'viewCount', 'ratingAvg', 'ratingCount'};

  /// Optional translations: omitted by `toMap()` when empty, so an update
  /// must delete them explicitly.
  static const _translationFields = ['titleAr', 'titleKu', 'descriptionAr', 'descriptionKu'];
  static const _timestampFields = {'createdAt', 'updatedAt'};

  CollectionReference<Map<String, dynamic>> get _products => _db.collection(FirestorePaths.products);

  /// What the editor writes: the model plus its derived query fields.
  static Map<String, dynamic> productData(ProductModel p) => {...p.toMap(), ...ProductDerived.of(p)};

  // ── Reads ────────────────────────────────────────────────────────────────

  /// Newest first, [pageSize] per page. Uses the composite indexes in
  /// mobile/firestore.indexes.json (`isActive`/`categoryIds` + `createdAt`);
  /// category + active together filters `isActive` on the page, so no extra
  /// index is needed.
  ///
  /// [storeId] (a seller's own store, SRS §9 Seller view) is the only server
  /// filter then (`storeId` + `createdAt` index); category / active are
  /// applied to the page.
  Future<ProductPage> fetchPage({
    String? categoryId,
    bool? isActive,
    String? storeId,
    DocumentSnapshot<Map<String, dynamic>>? after,
    int limit = pageSize,
  }) async {
    Query<Map<String, dynamic>> q = _products;
    if (storeId != null) {
      q = q.where('storeId', isEqualTo: storeId);
    } else if (categoryId != null) {
      q = q.where('categoryIds', arrayContains: categoryId);
    } else if (isActive != null) {
      q = q.where('isActive', isEqualTo: isActive);
    }
    q = q.orderBy('createdAt', descending: true);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.limit(limit).get();
    var items = [for (final d in snap.docs) ProductModel.fromMap(d.id, d.data())];
    if (storeId != null && categoryId != null) items = items.where((p) => p.categoryIds.contains(categoryId)).toList();
    if ((storeId != null || categoryId != null) && isActive != null) {
      items = items.where((p) => p.isActive == isActive).toList();
    }
    return ProductPage(items, snap.docs.isEmpty ? after : snap.docs.last, hasMore: snap.docs.length == limit);
  }

  /// Whole-catalogue lookup of one search token (same tokenizer as the app);
  /// [storeId] limits it to one store (`storeId` + `searchKeywords` + `createdAt` index).
  Future<List<ProductModel>> searchKeyword(String token, {String? storeId, int limit = pageSize}) async {
    Query<Map<String, dynamic>> q = _products.where('searchKeywords', arrayContains: token);
    if (storeId != null) q = q.where('storeId', isEqualTo: storeId);
    final snap = await q.orderBy('createdAt', descending: true).limit(limit).get();
    return [for (final d in snap.docs) ProductModel.fromMap(d.id, d.data())];
  }

  /// A Firestore auto id (provisional upload folder of an unsaved product).
  String autoId() => _products.doc().id;

  Future<ProductModel?> load(String id) async {
    final snap = await _products.doc(id).get();
    final data = snap.data();
    return data == null ? null : ProductModel.fromMap(snap.id, data);
  }

  /// Id for a new product: the slug of its English title, made unique
  /// (`-2`, `-3` …). A title without latin letters gets an auto id.
  /// Path segments the dashboard routes use under /products/.
  static const reservedIds = {'new', 'import'};

  Future<String> newProductId(String englishTitle) async {
    final base = slugify(englishTitle);
    if (base.isEmpty) return autoId();
    for (var n = 1; n <= 50; n++) {
      final candidate = n == 1 ? base : '$base-$n';
      if (reservedIds.contains(candidate)) continue;
      if (!(await _products.doc(candidate).get()).exists) return candidate;
    }
    return '$base-${autoId().substring(0, 6).toLowerCase()}';
  }

  /// Active stores first, then by name. A seller ([onlyStoreId]) reads only
  /// their own store — the rules keep other pending stores private.
  Future<List<StoreModel>> stores({String? onlyStoreId}) async {
    if (onlyStoreId != null) {
      final d = await _db.doc(FirestorePaths.storeDoc(onlyStoreId)).get();
      return d.exists ? [StoreModel.fromMap(d.id, d.data()!)] : const [];
    }
    final snap = await _db.collection(FirestorePaths.stores).get();
    final stores = [for (final d in snap.docs) StoreModel.fromMap(d.id, d.data())];
    stores.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.name.en.toLowerCase().compareTo(b.name.en.toLowerCase());
    });
    return stores;
  }

  // ── Writes (each one batch + audit entry) ────────────────────────────────

  /// Creates (`isNew`, id from [newProductId]) or updates `products/{p.id}`.
  /// An update leaves [counterFields] (and fields the editor doesn't know)
  /// untouched and deletes translations that were cleared.
  Future<void> save(ProductModel p, {required bool isNew, required String adminUid}) async {
    final ref = _products.doc(p.id);
    final target = FirestorePaths.productDoc(p.id);
    final data = productData(p);
    final batch = _db.batch();
    if (isNew) {
      batch.set(ref, {
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AuditLog.add(batch, _db, adminUid: adminUid, action: 'product.create', target: target, after: data);
    } else {
      final current = await ref.get();
      final currentData = current.data();
      if (currentData == null) throw ProductNotFoundException(p.id);
      final before = withoutTimestamps(currentData);
      final changes = Map<String, dynamic>.of(data)..removeWhere((k, _) => counterFields.contains(k));
      final cleared = [for (final k in _translationFields) if (!changes.containsKey(k)) k];
      batch.update(ref, {
        ...changes,
        for (final k in cleared) k: FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final after = {...before, ...changes}..removeWhere((k, _) => cleared.contains(k));
      AuditLog.add(batch, _db,
          adminUid: adminUid, action: 'product.update', target: target, before: before, after: after);
    }
    await batch.commit();
  }

  Future<void> delete(String id, {required String adminUid}) async {
    final ref = _products.doc(id);
    final current = (await ref.get()).data();
    final batch = _db.batch()..delete(ref);
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'product.delete',
        target: FirestorePaths.productDoc(id),
        before: current == null ? null : withoutTimestamps(current));
    await batch.commit();
  }

  /// Inline `isActive` / `isFeatured` toggle from the table.
  Future<void> setFlag(String id, String field, bool value, {required String adminUid}) async {
    assert(field == 'isActive' || field == 'isFeatured', 'Only isActive / isFeatured are inline toggles');
    final batch = _db.batch()
      ..update(_products.doc(id), {field: value, 'updatedAt': FieldValue.serverTimestamp()});
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'product.update',
        target: FirestorePaths.productDoc(id),
        before: {field: !value},
        after: {field: value});
    await batch.commit();
  }

  /// "Rebuild search keywords": recomputes [ProductDerived] (keywords, price
  /// band, city keys, gift-type keys …) for every product with the current tokenizer and writes
  /// the stale fields only, in batches of ≤ [maxBatchWrites] writes, each with
  /// one `product.rebuildKeywords` audit entry. `updatedAt` is left alone, as
  /// `onProductWrite` does for derived fields.
  Future<RebuildResult> rebuildSearchFields({required String adminUid, void Function(int scanned)? onProgress}) async {
    const chunk = maxBatchWrites - 1; // + the audit entry
    var scanned = 0, updated = 0, batches = 0;
    DocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      var q = _products.orderBy(FieldPath.documentId);
      if (last != null) q = q.startAfterDocument(last);
      final snap = await q.limit(chunk).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      final ids = <String>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final derived = ProductDerived.of(ProductModel.fromMap(doc.id, data));
        final stale = {
          for (final e in derived.entries)
            if (!_sameValue(data[e.key], e.value)) e.key: e.value,
        };
        if (stale.isEmpty) continue;
        batch.update(doc.reference, stale);
        ids.add(doc.id);
      }
      scanned += snap.docs.length;
      if (ids.isNotEmpty) {
        AuditLog.add(batch, _db,
            adminUid: adminUid,
            action: 'product.rebuildKeywords',
            target: FirestorePaths.products,
            after: {'productIds': ids, 'count': ids.length});
        await batch.commit();
        batches++;
        updated += ids.length;
      }
      onProgress?.call(scanned);
      if (snap.docs.length < chunk) break;
      last = snap.docs.last;
    }
    return RebuildResult(scanned: scanned, updated: updated, batches: batches);
  }

  static Map<String, dynamic> withoutTimestamps(Map<String, dynamic> map) =>
      Map.of(map)..removeWhere((k, _) => _timestampFields.contains(k));

  static bool _sameValue(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }
}

/// By `sortOrder`, then id (sorted on the client so a doc without
/// `sortOrder` still shows up).
List<CategoryModel> sortProductCategories(List<CategoryModel> list) => [...list]
  ..sort((a, b) {
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    return bySort != 0 ? bySort : a.id.compareTo(b.id);
  });

final productsAdminRepositoryProvider =
    Provider<ProductsAdminRepository>((ref) => ProductsAdminRepository(ref.watch(firestoreProvider)));

/// Pickers of the editor and filters of the list (live, so a category or
/// store added in another tab shows up without a reload).
final productCategoryOptionsProvider = StreamProvider.autoDispose<List<CategoryModel>>((ref) => ref
    .watch(firestoreProvider)
    .collection(FirestorePaths.categories)
    .snapshots()
    .map((s) => sortProductCategories([for (final d in s.docs) CategoryModel.fromMap(d.id, d.data())])));

final productStoreOptionsProvider = FutureProvider.autoDispose<List<StoreModel>>((ref) {
  final session = ref.watch(adminSessionProvider);
  return ref
      .watch(productsAdminRepositoryProvider)
      .stores(onlyStoreId: session?.role == AdminRole.seller ? session?.storeId ?? '-' : null);
});

final productCityOptionsProvider = StreamProvider.autoDispose<List<CityModel>>((ref) => ref
    .watch(firestoreProvider)
    .doc(FirestorePaths.settingsDoc('cities'))
    .snapshots()
    .map((s) => CityModel.listFromDoc(s.data() ?? const {})));

/// Label for the availability column / picker (SRS §6.15 `ProductAvailability`).
String availabilityLabel(ProductAvailability a) => switch (a) {
      ProductAvailability.sameDay => 'Same day',
      ProductAvailability.preparationDays => 'Preparation days',
      ProductAvailability.outOfStock => 'Out of stock',
    };

/// "Gift for" chip / column label (SRS §5.8a `GiftAudience`).
String giftAudienceLabel(GiftAudience a) => switch (a) {
      GiftAudience.men => 'For him',
      GiftAudience.women => 'For her',
      GiftAudience.companies => 'For companies',
    };
