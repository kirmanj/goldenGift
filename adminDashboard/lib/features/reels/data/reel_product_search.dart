import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/utils/search_tokenizer.dart';
import 'package:golden_gift/models/product_model.dart';

import '../../products/data/products_admin_repository.dart';
import '../../products/domain/product_search.dart';

/// How many products the picker lists.
const reelProductPickerLimit = 8;

/// The newest products (what the picker shows before anything is typed, and
/// what typed text is matched against, like the products table's search).
final reelPickerRecentProductsProvider = FutureProvider.autoDispose<List<ProductModel>>(
    (ref) async => (await ref.watch(productsAdminRepositoryProvider).fetchPage(limit: 50)).items);

/// Products for the reel editor's picker (SRS §9 Reels "search by title"):
/// an exact id, whole-catalogue hits for the longest word (`searchKeywords`,
/// the app's tokenizer) and the newest products matching every word — the
/// same matching as the Products table ([matchesProductSearch]).
final reelProductSearchProvider = FutureProvider.autoDispose.family<List<ProductModel>, String>((ref, query) async {
  final repo = ref.watch(productsAdminRepositoryProvider);
  final recent = await ref.watch(reelPickerRecentProductsProvider.future);
  final q = query.trim();
  if (q.isEmpty) return recent.take(reelProductPickerLimit).toList();

  final found = <String, ProductModel>{};
  if (!q.contains('/') && !q.contains(RegExp(r'\s'))) {
    final exact = await repo.load(q);
    if (exact != null) found[exact.id] = exact;
  }
  final tokens = SearchTokenizer.tokenize(q)..sort((a, b) => b.length.compareTo(a.length));
  if (tokens.isNotEmpty) {
    try {
      for (final p in await repo.searchKeyword(tokens.first, limit: 20)) {
        if (matchesProductSearch(p, q)) found.putIfAbsent(p.id, () => p);
      }
    } catch (_) {
      // The newest products below still match.
    }
  }
  for (final p in recent) {
    if (matchesProductSearch(p, q)) found.putIfAbsent(p.id, () => p);
  }
  return found.values.take(reelProductPickerLimit).toList();
});
