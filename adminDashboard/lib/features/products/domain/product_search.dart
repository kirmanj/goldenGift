import 'package:golden_gift/core/utils/search_tokenizer.dart';
import 'package:golden_gift/models/product_model.dart';

/// Client-side filter over the loaded products: every word of [query] must
/// appear (as part of a word) in the product's titles, id or tags, after the
/// app's normalisation (case, Arabic/Kurdish letter variants).
bool matchesProductSearch(ProductModel p, String query) {
  final q = SearchTokenizer.normalize(query.trim());
  if (q.isEmpty) return true;
  final haystack = SearchTokenizer.normalize([p.id, ...p.title.all, ...p.tags].join(' '));
  return q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(haystack.contains);
}

/// The keyword to look up across the whole catalogue (`searchKeywords
/// array-contains`), or null unless [query] is exactly one token.
String? singleSearchKeyword(String query) {
  final tokens = SearchTokenizer.tokenize(query);
  return tokens.length == 1 ? tokens.single : null;
}
