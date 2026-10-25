import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/product_model.dart';

import '../../../core/data/audit_log.dart';
import '../../../core/session/admin_session.dart';
import '../data/products_admin_repository.dart';
import '../domain/product_draft.dart';
import 'product_csv.dart';

/// Who may bulk-import products (SRS §9 Products): catalogue staff only —
/// never finance, never partner accounts.
class ProductImportAccess {
  ProductImportAccess._();

  static bool canImport(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops || r == AdminRole.content;
}

enum ImportAction { create, update, unchanged, invalid }

String importActionLabel(ImportAction a) => switch (a) {
      ImportAction.create => 'Create',
      ImportAction.update => 'Update',
      ImportAction.unchanged => 'No changes',
      ImportAction.invalid => 'Error',
    };

/// The verdict on one CSV row.
class ImportRowPlan {
  ImportRowPlan({
    required this.row,
    required this.action,
    this.id,
    this.model,
    this.data,
    this.changedFields = const [],
    this.issues = const [],
  });

  /// Spreadsheet row number (the header is row 1).
  final int row;
  final ImportAction action;

  /// The product id written (null for an invalid row without one).
  final String? id;

  /// The product after the import (for the preview).
  final ProductModel? model;

  /// What is written: the full document (create, timestamps added on
  /// commit) or only the changed fields + derived query fields (update).
  final Map<String, dynamic>? data;

  /// Firestore fields an update changes.
  final List<String> changedFields;
  final List<ImportIssue> issues;

  bool get writes => action == ImportAction.create || action == ImportAction.update;

  /// Issues of one column (to highlight the cell).
  List<ImportIssue> issuesFor(String? column) => [
        for (final i in issues)
          if (i.column == column) i
      ];
}

class ImportPlan {
  const ImportPlan({required this.sheet, required this.rows});
  final ProductCsvSheet sheet;
  final List<ImportRowPlan> rows;

  int count(ImportAction a) => rows.where((r) => r.action == a).length;
  List<ImportRowPlan> get writable => [
        for (final r in rows)
          if (r.writes) r
      ];
}

class ImportSummary {
  const ImportSummary({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.failed,
    required this.batches,
  });

  final List<String> created;
  final List<String> updated;

  /// (row, reason) of rows not written: errors and rows without changes.
  final List<(int, String)> skipped;

  /// (row, reason) of rows whose batch failed to commit.
  final List<(int, String)> failed;
  final int batches;
}

/// Turns a parsed [ProductCsvSheet] into an [ImportPlan] (validation +
/// create / update decision), then commits the plan. Uses the editor's
/// rules ([ProductDraft.validate]) and writes exactly what the editor
/// writes ([ProductsAdminRepository.productData]: the model + derived query
/// fields + `searchKeywords`).
class ProductImporter {
  ProductImporter(this._db);
  final FirebaseFirestore _db;

  /// ≤ 400 writes per batch: products + the batch's audit entry.
  static const maxBatchWrites = ProductsAdminRepository.maxBatchWrites;
  static const productsPerBatch = maxBatchWrites - 1;

  /// Never set by an import (owned by the app / functions).
  static const _derivedKeys = ['hasDiscount', 'priceBand', 'cityKeys', 'catCityKeys', 'forKeys', 'searchKeywords'];
  static const _translationKeys = {'titleAr', 'titleKu', 'descriptionAr', 'descriptionKu'};

  /// Firestore fields a column writes (availability also fixes
  /// preparationDays, which is 0 while same day — as the editor saves it).
  static const _keysOf = <String, List<String>>{
    ProductCsv.title: ['title'],
    ProductCsv.titleAr: ['titleAr'],
    ProductCsv.titleKu: ['titleKu'],
    ProductCsv.description: ['description'],
    ProductCsv.descriptionAr: ['descriptionAr'],
    ProductCsv.descriptionKu: ['descriptionKu'],
    ProductCsv.price: ['price'],
    ProductCsv.compareAtPrice: ['compareAtPrice'],
    ProductCsv.categoryIds: ['categoryIds'],
    ProductCsv.giftFor: ['giftFor'],
    ProductCsv.storeId: ['storeId'],
    ProductCsv.availability: ['availability', 'preparationDays'],
    ProductCsv.preparationDays: ['preparationDays'],
    ProductCsv.availableCities: ['availableCities'],
    ProductCsv.stock: ['stock'],
    ProductCsv.isActive: ['isActive'],
    ProductCsv.isFeatured: ['isFeatured'],
    ProductCsv.tags: ['tags'],
    ProductCsv.images: ['images'],
  };

  CollectionReference<Map<String, dynamic>> get _products => _db.collection(FirestorePaths.products);

  /// Category, store and city ids a row may reference.
  Future<ProductImportRefs> loadRefs() async {
    final results = await Future.wait([
      _db.collection(FirestorePaths.categories).get(),
      _db.collection(FirestorePaths.stores).get(),
    ]);
    final cities = await _db.doc(FirestorePaths.settingsDoc('cities')).get();
    return ProductImportRefs(
      categoryIds: {for (final d in results[0].docs) d.id},
      storeIds: {for (final d in results[1].docs) d.id},
      cityIds: {for (final c in CityModel.listFromDoc(cities.data() ?? const {})) c.id},
    );
  }

  Future<ImportPlan> analyze(ProductCsvSheet sheet, {ProductImportRefs? refs}) async {
    final r = refs ?? await loadRefs();

    // Explicit ids: duplicates in the file, then one read each.
    final firstRowOf = <String, int>{};
    final duplicateOf = <int, int>{};
    for (final row in sheet.rows) {
      final id = row.cell(ProductCsv.id);
      if (id.isEmpty) continue;
      final first = firstRowOf[id];
      if (first == null) {
        firstRowOf[id] = row.row;
      } else {
        duplicateOf[row.row] = first;
      }
    }
    final lookup = [
      for (final id in firstRowOf.keys)
        if (!id.contains('/') && id != '.' && id != '..') id
    ];
    final existing = <String, Map<String, dynamic>>{};
    for (var i = 0; i < lookup.length; i += 50) {
      final snaps = await Future.wait([for (final id in lookup.skip(i).take(50)) _products.doc(id).get()]);
      for (final s in snaps) {
        if (s.data() case final data?) existing[s.id] = data;
      }
    }

    final taken = {...firstRowOf.keys, ...ProductCsv.reservedIds};
    final plans = <ImportRowPlan>[];
    for (final row in sheet.rows) {
      final structural = sheet.rowIssues[row.row] ?? const [];
      final id = row.cell(ProductCsv.id);
      final dup = duplicateOf[row.row];
      if (structural.isNotEmpty || dup != null) {
        plans.add(ImportRowPlan(row: row.row, action: ImportAction.invalid, id: id.isEmpty ? null : id, issues: [
          ...structural,
          if (dup != null) ImportIssue(ProductCsv.id, 'The id “$id” is already used on row $dup.'),
        ]));
        continue;
      }
      final current = existing[id];
      plans.add(current != null ? _planUpdate(row, id, current, r) : await _planCreate(row, id, r, taken));
    }
    return ImportPlan(sheet: sheet, rows: plans);
  }

  ImportRowPlan _planUpdate(ProductCsvRow row, String id, Map<String, dynamic> current, ProductImportRefs refs) {
    final draft = ProductDraft.fromModel(ProductModel.fromMap(id, current));
    final touched = <String>{};
    final issues = applyRowToDraft(row, draft, isUpdate: true, refs: refs, touched: touched);
    issues.addAll(draft.validate().map(draftIssue));
    if (issues.isNotEmpty) {
      return ImportRowPlan(row: row.row, action: ImportAction.invalid, id: id, issues: issues);
    }
    final model = draft.toModel(id);
    final full = ProductsAdminRepository.productData(model);
    final changes = <String, dynamic>{};
    final keys = {for (final c in touched) ...?_keysOf[c]};
    for (final k in keys) {
      if (_translationKeys.contains(k) && !full.containsKey(k)) {
        if (current.containsKey(k)) changes[k] = FieldValue.delete();
      } else if (!_same(current[k], full[k])) {
        changes[k] = full[k];
      }
    }
    if (changes.isEmpty) {
      return ImportRowPlan(row: row.row, action: ImportAction.unchanged, id: id, model: model);
    }
    final changed = changes.keys.toList();
    for (final k in _derivedKeys) {
      changes[k] = full[k];
    }
    return ImportRowPlan(
      row: row.row,
      action: ImportAction.update,
      id: id,
      model: model,
      data: changes,
      changedFields: changed,
    );
  }

  Future<ImportRowPlan> _planCreate(ProductCsvRow row, String id, ProductImportRefs refs, Set<String> taken) async {
    final issues = <ImportIssue>[];
    if (id.isNotEmpty && (!importIdPattern.hasMatch(id) || ProductCsv.reservedIds.contains(id))) {
      issues.add(ImportIssue(ProductCsv.id,
          ProductCsv.reservedIds.contains(id) ? '“$id” is reserved.' : 'Use letters, digits, - or _ (up to 100).'));
    }
    if (id.isNotEmpty && row.cell(ProductCsv.title).isEmpty) {
      issues.add(const ImportIssue(ProductCsv.id,
          'No product has this id. To create it, also fill ${ProductCsv.title}, ${ProductCsv.price} and ${ProductCsv.storeId}.'));
    }
    final draft = ProductDraft();
    issues.addAll(applyRowToDraft(row, draft, isUpdate: false, refs: refs, touched: <String>{}));
    issues.addAll(draft.validate().map(draftIssue));
    if (issues.isNotEmpty) {
      return ImportRowPlan(row: row.row, action: ImportAction.invalid, id: id.isEmpty ? null : id, issues: issues);
    }
    final newId = id.isNotEmpty ? id : await _newId(draft.title.en, taken);
    taken.add(newId);
    final model = draft.toModel(newId);
    return ImportRowPlan(
      row: row.row,
      action: ImportAction.create,
      id: newId,
      model: model,
      data: ProductsAdminRepository.productData(model),
    );
  }

  /// Like the editor ([ProductsAdminRepository.newProductId]): the title's
  /// slug, `-2`, `-3` … until free — free in Firestore AND in this file.
  Future<String> _newId(String englishTitle, Set<String> taken) async {
    final base = slugify(englishTitle);
    if (base.isEmpty) return _products.doc().id;
    for (var n = 1; n <= 200; n++) {
      final candidate = n == 1 ? base : '$base-$n';
      if (taken.contains(candidate)) continue;
      if (!(await _products.doc(candidate).get()).exists) return candidate;
    }
    return '$base-${_products.doc().id.substring(0, 6).toLowerCase()}';
  }

  /// Writes the plan's create / update rows, [productsPerBatch] per batch,
  /// each batch with one `product.import` audit entry `{created, updated,
  /// ids}`. A batch that fails is reported and the next one still runs.
  Future<ImportSummary> commit(ImportPlan plan,
      {required String adminUid, void Function(int done, int total)? onProgress}) async {
    final rows = plan.writable;
    final created = <String>[], updated = <String>[];
    final failed = <(int, String)>[];
    var batches = 0, done = 0;
    for (var i = 0; i < rows.length; i += productsPerBatch) {
      final chunk = rows.skip(i).take(productsPerBatch).toList();
      final batch = _db.batch();
      final c = <String>[], u = <String>[];
      for (final r in chunk) {
        final ref = _products.doc(r.id);
        if (r.action == ImportAction.create) {
          batch.set(ref, {
            ...r.data!,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          c.add(r.id!);
        } else {
          batch.update(ref, {...r.data!, 'updatedAt': FieldValue.serverTimestamp()});
          u.add(r.id!);
        }
      }
      AuditLog.add(batch, _db, adminUid: adminUid, action: 'product.import', target: FirestorePaths.products, after: {
        'created': c.length,
        'updated': u.length,
        'ids': [...c, ...u]
      });
      try {
        await batch.commit();
        batches++;
        created.addAll(c);
        updated.addAll(u);
      } catch (e) {
        for (final r in chunk) {
          failed.add((r.row, 'Not saved: $e'));
        }
      }
      done += chunk.length;
      onProgress?.call(done, rows.length);
    }
    final skipped = [
      for (final r in plan.rows)
        if (r.action == ImportAction.invalid)
          (r.row, r.issues.map((i) => i.toString()).join(' '))
        else if (r.action == ImportAction.unchanged)
          (r.row, 'No changes for “${r.id}”.'),
    ];
    return ImportSummary(created: created, updated: updated, skipped: skipped, failed: failed, batches: batches);
  }

  static bool _same(Object? a, Object? b) {
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

final productImporterProvider = Provider<ProductImporter>((ref) => ProductImporter(ref.watch(firestoreProvider)));
