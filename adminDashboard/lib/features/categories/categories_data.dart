import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/features/categories/presentation/providers/categories_providers.dart'
    show filterCategories;
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/localized_text.dart';

import '../../core/data/audit_log.dart';
import '../../core/session/admin_session.dart';
import 'slug.dart';

/// Every category, active or not, in admin order (SRS §5.7, §6.3). Sorted on
/// the client so a seeded doc without `sortOrder` still shows up here.
final adminCategoriesProvider = StreamProvider.autoDispose<List<CategoryModel>>((ref) => ref
    .watch(firestoreProvider)
    .collection(FirestorePaths.categories)
    .snapshots()
    .map((s) => sortCategories([for (final d in s.docs) CategoryModel.fromMap(d.id, d.data())])));

List<CategoryModel> sortCategories(List<CategoryModel> list) => [...list]
  ..sort((a, b) {
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    return bySort != 0 ? bySort : a.id.compareTo(b.id);
  });

final categoryAdminRepositoryProvider = Provider.autoDispose<CategoryAdminRepository>((ref) =>
    CategoryAdminRepository(ref.watch(firestoreProvider), adminUid: ref.watch(adminSessionProvider)?.uid ?? ''));

enum CategoryFilter {
  all('All'),
  occasion('Occasion'),
  productType('Product type'),
  comingSoon('Coming soon');

  const CategoryFilter(this.label);
  final String label;
}

/// Filter chips + "search by title" (any language, same normalisation as the app).
List<CategoryModel> filterAdminCategories(List<CategoryModel> all, CategoryFilter filter, String query) {
  final byType = switch (filter) {
    CategoryFilter.all => all,
    CategoryFilter.occasion => all.where((c) => c.type == CategoryType.occasion).toList(),
    CategoryFilter.productType => all.where((c) => c.type == CategoryType.productType).toList(),
    CategoryFilter.comingSoon => all.where((c) => c.status == CategoryStatus.comingSoon).toList(),
  };
  return filterCategories(byType, query);
}

/// What a status means for customers (SRS §5.7a), for the status menu and editor.
extension CategoryStatusText on CategoryStatus {
  String get label => switch (this) {
        CategoryStatus.available => 'Available',
        CategoryStatus.comingSoon => 'Coming soon',
        CategoryStatus.hidden => 'Hidden',
      };

  String get description => switch (this) {
        CategoryStatus.available => 'Shown in the app with its products.',
        CategoryStatus.comingSoon => "Still listed, but customers see a 'coming soon' page instead of products.",
        CategoryStatus.hidden => 'Not shown anywhere in the app.',
      };
}

/// Trilingual coming-soon note keys (SRS §6.3).
const comingSoonNoteKeys = ['comingSoonNote', 'comingSoonNoteAr', 'comingSoonNoteKu'];

/// Seasonal windows are whole days: from the start of `activeFrom` to the end
/// of `activeTo` (local time), so a one-day window is valid.
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

String? validateSeasonWindow({required bool isSeasonal, DateTime? from, DateTime? to}) {
  if (!isSeasonal) return null;
  if (from == null || to == null) return 'A seasonal category needs both an Active from and an Active to date';
  if (to.isBefore(from)) return 'Active to must be on or after Active from';
  return null;
}

/// Ids of every category below [id] (children, grandchildren, …).
Set<String> descendantsOf(String id, List<CategoryModel> all) {
  final result = <String>{};
  var frontier = {id};
  while (frontier.isNotEmpty) {
    final next = {
      for (final c in all)
        if (c.parentId != null && frontier.contains(c.parentId) && !result.contains(c.id) && c.id != id) c.id,
    };
    result.addAll(next);
    frontier = next;
  }
  return result;
}

/// Every rule a category must pass before it is written (SRS §6.3).
List<String> validateCategory(CategoryModel c, {required List<CategoryModel> existing, required bool isNew}) {
  final errors = <String>[];
  if (c.title.en.trim().isEmpty) errors.add('English title is required');
  if (isNew) {
    final idError = validateSlugId(c.id, takenIds: existing.map((e) => e.id));
    if (idError != null) errors.add('Id: $idError');
  }
  final season = validateSeasonWindow(isSeasonal: c.isSeasonal, from: c.activeFrom, to: c.activeTo);
  if (season != null) errors.add(season);
  if (c.comingSoonNote.all.any((t) => t.trim().length > CategoryModel.comingSoonNoteMaxLength)) {
    errors.add('The coming-soon note is at most ${CategoryModel.comingSoonNoteMaxLength} characters per language');
  }
  final parent = c.parentId;
  if (parent != null) {
    if (parent == c.id) {
      errors.add('A category cannot be its own parent');
    } else if (!existing.any((e) => e.id == parent)) {
      errors.add('Parent category "$parent" does not exist');
    } else if (descendantsOf(c.id, existing).contains(parent)) {
      errors.add('The parent cannot be one of this category\'s subcategories');
    }
  }
  return errors;
}

class CategoryValidationException implements Exception {
  const CategoryValidationException(this.errors);
  final List<String> errors;
  @override
  String toString() => errors.join('\n');
}

class CategoryIdTakenException implements Exception {
  const CategoryIdTakenException(this.id);
  final String id;
  @override
  String toString() => 'The id "$id" is already used by another category.';
}

/// Moves one entry the way ReorderableListView reports it ([newIndex] counts
/// the slot before the item is removed).
List<T> moveItem<T>(List<T> list, int oldIndex, int newIndex) {
  final result = [...list];
  final item = result.removeAt(oldIndex);
  result.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
  return result;
}

/// Category writes. Each call is ONE batch carrying the change and its
/// `admin_audit_log` entry (adminDashboard/CLAUDE.md).
class CategoryAdminRepository {
  CategoryAdminRepository(this.db, {required this.adminUid});

  final FirebaseFirestore db;
  final String adminUid;

  DocumentReference<Map<String, dynamic>> _doc(String id) => db.doc(FirestorePaths.categoryDoc(id));

  void _requireAdmin() {
    if (adminUid.isEmpty) throw StateError('Not signed in as an admin.');
  }

  /// New category at the end of the list. The id is the doc id and never changes.
  Future<void> create(CategoryModel category, {required List<CategoryModel> existing}) async {
    _requireAdmin();
    final errors = validateCategory(category, existing: existing, isNew: true);
    if (errors.isNotEmpty) throw CategoryValidationException(errors);
    final ref = _doc(category.id);
    if ((await ref.get()).exists) throw CategoryIdTakenException(category.id);
    final sortOrder = existing.isEmpty ? 0 : existing.map((c) => c.sortOrder).reduce(math.max) + 1;
    final data = _withCounters(_normalized(category), sortOrder: sortOrder, productCount: 0).toMap();
    if (category.comingSoon) data['comingSoonSince'] = FieldValue.serverTimestamp();
    final batch = db.batch()..set(ref, data);
    AuditLog.add(batch, db, adminUid: adminUid, action: 'category.create', target: ref.path, after: data);
    await batch.commit();
  }

  /// Edits everything but the id, `sortOrder` (reorder) and `productCount`
  /// (maintained by product writes). Cleared translations are deleted, and so
  /// is the coming-soon note when the category is not coming soon (SRS §6.3).
  /// `comingSoonSince` is set when it becomes coming soon, deleted when it stops.
  Future<void> update(CategoryModel before, CategoryModel edited, {required List<CategoryModel> existing}) async {
    _requireAdmin();
    if (before.id != edited.id) throw ArgumentError('A category id cannot change.');
    final after = _normalized(edited);
    final errors = validateCategory(after, existing: existing, isNew: false);
    if (errors.isNotEmpty) throw CategoryValidationException(errors);
    final ref = _doc(after.id);
    final data = after.toMap()
      ..remove('sortOrder')
      ..remove('productCount')
      ..remove('comingSoonSince');
    for (final key in const ['titleAr', 'titleKu', ...comingSoonNoteKeys]) {
      data.putIfAbsent(key, FieldValue.delete);
    }
    final since = _sinceChange(before.comingSoon, after.comingSoon);
    if (since != null) data['comingSoonSince'] = since;
    final batch = db.batch()..update(ref, data);
    AuditLog.add(batch, db,
        adminUid: adminUid,
        action: 'category.update',
        target: ref.path,
        before: before.toMap(),
        after: _withCounters(after, sortOrder: before.sortOrder, productCount: before.productCount).toMap());
    await batch.commit();
  }

  /// Available · Coming soon · Hidden from the list's status menu (SRS §5.7a):
  /// `isActive`, `comingSoon`, `comingSoonSince` (and the note, cleared when
  /// it stops being coming soon) in ONE batch with a `category.status` entry.
  Future<void> setStatus(CategoryModel category, CategoryStatus status) async {
    _requireAdmin();
    if (category.status == status) return;
    final ref = _doc(category.id);
    final comingSoon = status == CategoryStatus.comingSoon;
    final data = <String, dynamic>{
      'isActive': status != CategoryStatus.hidden,
      'comingSoon': comingSoon,
      if (!comingSoon) for (final key in comingSoonNoteKeys) key: FieldValue.delete(),
    };
    final since = _sinceChange(category.comingSoon, comingSoon);
    if (since != null) data['comingSoonSince'] = since;
    Map<String, dynamic> snapshot(CategoryStatus s, bool active, bool soon, LocalizedText note) => {
          'status': s.name,
          'isActive': active,
          'comingSoon': soon,
          if (!note.isEmpty) ...note.toMap('comingSoonNote'),
        };
    final batch = db.batch()..update(ref, data);
    AuditLog.add(batch, db,
        adminUid: adminUid,
        action: 'category.status',
        target: ref.path,
        before: snapshot(category.status, category.isActive, category.comingSoon, category.comingSoonNote),
        after: snapshot(status, status != CategoryStatus.hidden, comingSoon,
            comingSoon ? category.comingSoonNote : LocalizedText.empty));
    await batch.commit();
  }

  /// Products keep the id in `categoryIds` until they are edited (SRS §9);
  /// a category with subcategories must be emptied first.
  Future<void> delete(CategoryModel category, {required List<CategoryModel> existing}) async {
    _requireAdmin();
    final children = existing.where((c) => c.parentId == category.id).map((c) => c.id).toList();
    if (children.isNotEmpty) {
      throw CategoryValidationException(['Move or delete its subcategories first: ${children.join(', ')}']);
    }
    final ref = _doc(category.id);
    final batch = db.batch()..delete(ref);
    AuditLog.add(batch, db, adminUid: adminUid, action: 'category.delete', target: ref.path, before: category.toMap());
    await batch.commit();
  }

  /// Rewrites `sortOrder` to the list position for every category whose
  /// position changed, in one batch with one `category.reorder` entry.
  /// Returns how many categories moved.
  Future<int> reorder(List<CategoryModel> ordered) async {
    _requireAdmin();
    final before = <String, dynamic>{};
    final after = <String, dynamic>{};
    final batch = db.batch();
    for (var i = 0; i < ordered.length; i++) {
      final c = ordered[i];
      if (c.sortOrder == i) continue;
      batch.update(_doc(c.id), {'sortOrder': i});
      before[c.id] = c.sortOrder;
      after[c.id] = i;
    }
    if (after.isEmpty) return 0;
    if (after.length > 450) throw StateError('Too many categories to reorder in one batch.');
    AuditLog.add(batch, db,
        adminUid: adminUid, action: 'category.reorder', target: FirestorePaths.categories, before: before, after: after);
    await batch.commit();
    return after.length;
  }
}

/// A category that isn't coming soon carries no coming-soon note; notes are trimmed.
CategoryModel _normalized(CategoryModel c) {
  if (!c.comingSoon) return c.copyWith(comingSoonNote: LocalizedText.empty);
  final n = c.comingSoonNote;
  String? opt(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
  return c.copyWith(comingSoonNote: LocalizedText(n.en.trim(), ar: opt(n.ar), ku: opt(n.ku)));
}

/// `comingSoonSince` when the coming-soon flag changes: set on, deleted off.
FieldValue? _sinceChange(bool before, bool after) {
  if (!before && after) return FieldValue.serverTimestamp();
  if (before && !after) return FieldValue.delete();
  return null;
}

/// Through toMap → fromMap so fields added to the model later are kept.
CategoryModel _withCounters(CategoryModel c, {required int sortOrder, required int productCount}) =>
    CategoryModel.fromMap(c.id, {...c.toMap(), 'sortOrder': sortOrder, 'productCount': productCount});
