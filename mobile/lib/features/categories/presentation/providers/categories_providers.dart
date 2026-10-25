import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/utils/search_tokenizer.dart';
import '../../../../models/category_model.dart';
import '../../../../models/localized_text.dart';

/// Every visible category in admin order (SRS §5.7), live and cache-first.
/// Coming soon categories (§5.7a) are included — they stay listed.
final allCategoriesProvider = StreamProvider<List<CategoryModel>>((ref) {
  return ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.categories)
      .where('isActive', isEqualTo: true)
      .orderBy('sortOrder')
      .snapshots()
      .map((snap) {
    final now = DateTime.now();
    return [for (final d in snap.docs) CategoryModel.fromMap(d.id, d.data())]
        .where((c) => c.isVisibleAt(now))
        .toList();
  });
});

/// One category by id from the list above (product list title, chips).
final categoryByIdProvider = Provider.family<CategoryModel?, String>((ref, id) {
  final all = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
  for (final c in all) {
    if (c.id == id) return c;
  }
  return null;
});

/// "Search for a category" filters locally (SRS §5.7): matches any language,
/// with the same normalization as product search (ك/ک, ي/ی, diacritics).
List<CategoryModel> filterCategories(List<CategoryModel> categories, String query) {
  final q = SearchTokenizer.normalize(query.trim());
  if (q.isEmpty) return categories;
  return categories
      .where((c) => c.title.all.any((t) => SearchTokenizer.normalize(t).contains(q)))
      .toList();
}

Map<String, CategoryModel> categoriesById(Iterable<CategoryModel> categories) => {for (final c in categories) c.id: c};

/// A category the customer opened that is "coming soon" (SRS §5.7a).
class ComingSoonCategory {
  const ComingSoonCategory({required this.category, required this.note});

  /// The category that was opened (its name and icon are shown).
  final CategoryModel category;

  /// Its own coming-soon note, else the note of the coming-soon parent.
  final LocalizedText note;
}

/// [id] in [categories] when it is coming soon — itself or through a parent;
/// null when it is available, unknown, or the list isn't loaded.
ComingSoonCategory? comingSoonCategoryIn(List<CategoryModel>? categories, String? id) {
  if (categories == null || id == null) return null;
  final byId = categoriesById(categories);
  final category = byId[id];
  if (category == null) return null;
  final source = category.comingSoonSource(byId);
  if (source == null) return null;
  return ComingSoonCategory(
    category: category,
    note: category.comingSoonNote.isEmpty ? source.comingSoonNote : category.comingSoonNote,
  );
}

/// Ids in [categories] that are coming soon (themselves or through a parent).
Set<String> comingSoonIdsIn(List<CategoryModel> categories) {
  final byId = categoriesById(categories);
  return {
    for (final c in categories)
      if (c.isComingSoonWithin(byId)) c.id,
  };
}

/// Categories that open their products: neither coming soon nor under a
/// coming-soon parent (the coming-soon page's "Explore other categories").
List<CategoryModel> availableCategoriesIn(List<CategoryModel> categories) {
  final soon = comingSoonIdsIn(categories);
  return categories.where((c) => !soon.contains(c.id)).toList();
}
