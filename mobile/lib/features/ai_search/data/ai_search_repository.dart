import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/services/callable.dart';
import '../../../models/localized_text.dart';
import '../../../models/product_model.dart';
import '../../products/data/product_query.dart';
import '../../products/data/product_search_repository.dart';

/// One AI suggestion: the product plus Gemini's one-line "why" (SRS §5.6).
class AiSuggestion {
  const AiSuggestion(this.product, {this.reason});
  final ProductModel product;

  /// In the customer's language; null for keyword-fallback results.
  final String? reason;
}

class AiSearchResult {
  const AiSearchResult({required this.suggestions, this.searchId, this.usedFallback = false, this.rateLimited = false});
  final List<AiSuggestion> suggestions;
  final String? searchId;

  /// The function failed or is not deployed: plain keyword results instead.
  final bool usedFallback;

  /// 20 queries / user / day reached (fallback results are still shown).
  final bool rateLimited;
}

/// AI Gift Search (SRS §5.6): `aiGiftSearch({query, locale, budgetMax})` →
/// `{searchId, results: [{productId, reason}]}` (≤ 12, ranked; the function
/// logs `ai_searches` and enforces the rate limit). Any failure falls back to
/// the keyword search so the screen always shows something.
class AiSearchRepository {
  AiSearchRepository(this._db, this._call, this._keywordSearch);
  final FirebaseFirestore _db;
  final CallableInvoker _call;
  final ProductSearchRepository _keywordSearch;

  static const maxQuery = 300;
  static const maxResults = 12;

  Future<AiSearchResult> search(String query, {required String locale, int? budgetMax}) async {
    final text = query.trim();
    if (text.isEmpty) return const AiSearchResult(suggestions: []);
    var rateLimited = false;
    try {
      final data = callableMap(await _call('aiGiftSearch', {
        'query': text.length > maxQuery ? text.substring(0, maxQuery) : text,
        'locale': locale,
        if (budgetMax != null && budgetMax > 0) 'budgetMax': budgetMax,
      }));
      final results = [
        for (final r in (data['results'] as List? ?? const []))
          if (r is Map && r['productId'] is String) (r['productId'] as String, r['reason'] as String?),
      ].take(maxResults).toList();
      final products = await _products([for (final r in results) r.$1]);
      final suggestions = [
        for (final (id, reason) in results)
          if (products[id] case final p? when p.isActive) AiSuggestion(p, reason: reason),
      ];
      if (suggestions.isNotEmpty) return AiSearchResult(suggestions: suggestions, searchId: data['searchId'] as String?);
    } catch (e) {
      rateLimited = e is FirebaseFunctionsException && e.code == 'resource-exhausted';
    }
    final page = await _keywordSearch.fetch(ProductQuery(text: text), pageSize: maxResults);
    final within = budgetMax == null || budgetMax <= 0 ? page.items : page.items.where((p) => p.price <= budgetMax).toList();
    return AiSearchResult(
      suggestions: [for (final p in within) AiSuggestion(p)],
      usedFallback: true,
      rateLimited: rateLimited,
    );
  }

  Future<Map<String, ProductModel>> _products(List<String> ids) async {
    final out = <String, ProductModel>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final snap = await _db.collection(FirestorePaths.products).where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        out[d.id] = ProductModel.fromMap(d.id, d.data());
      }
    }
    return out;
  }
}

final aiSearchRepositoryProvider = Provider<AiSearchRepository>((ref) => AiSearchRepository(
      ref.watch(firestoreProvider),
      ref.watch(callableInvokerProvider),
      ref.watch(productSearchRepositoryProvider),
    ));

/// Example prompts for the chips under the text area, per language.
const aiSearchExamples = <LocalizedText>[
  LocalizedText("My sister's graduation, she loves plants, budget 50,000",
      ar: 'تخرج أختي، تحب النباتات، الميزانية 50,000', ku: 'دەرچوونی خوشکەکەم، حەزی لە ڕووەکە، بودجە 50,000'),
  LocalizedText('Anniversary gift for my wife', ar: 'هدية ذكرى زواج لزوجتي', ku: 'دیاری ساڵیادی هاوسەرگیری بۆ خێزانەکەم'),
  LocalizedText('Something personal for a new baby', ar: 'هدية شخصية لمولود جديد', ku: 'شتێکی تایبەت بۆ منداڵێکی تازە لەدایکبوو'),
];
