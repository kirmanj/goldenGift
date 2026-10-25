import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/analytics_service.dart';
import '../../data/ai_search_repository.dart';

enum AiSearchPhase { idle, loading, done, error }

class AiSearchState {
  const AiSearchState({this.phase = AiSearchPhase.idle, this.query = '', this.budgetMax, this.result});

  final AiSearchPhase phase;
  final String query;
  final int? budgetMax;
  final AiSearchResult? result;
}

/// One AI Gift Search at a time (SRS §5.6). The repository already falls back
/// to keyword search, so only a failing fallback ends in [AiSearchPhase.error].
/// Every finished search logs `ai_search` (SRS §4.7).
class AiSearchController extends StateNotifier<AiSearchState> {
  AiSearchController(this._repo, this._analytics) : super(const AiSearchState());

  final AiSearchRepository _repo;
  final AnalyticsService _analytics;
  int _seq = 0;

  /// GA4 caps parameter values at 100 characters.
  static const _maxTermLength = 100;

  Future<void> search(String query, {required String locale, int? budgetMax}) async {
    final text = query.trim();
    if (text.isEmpty) return;
    final seq = ++_seq;
    state = AiSearchState(phase: AiSearchPhase.loading, query: text, budgetMax: budgetMax);
    try {
      final result = await _repo.search(text, locale: locale, budgetMax: budgetMax);
      if (!mounted || seq != _seq) return;
      state = AiSearchState(phase: AiSearchPhase.done, query: text, budgetMax: budgetMax, result: result);
      unawaited(_analytics.log(AnalyticsEvents.aiSearch, {
        'search_term': text.length > _maxTermLength ? text.substring(0, _maxTermLength) : text,
        'results': result.suggestions.length,
        'fallback': result.usedFallback ? 1 : 0,
      }));
    } catch (_) {
      if (!mounted || seq != _seq) return;
      state = AiSearchState(phase: AiSearchPhase.error, query: text, budgetMax: budgetMax);
    }
  }
}

final aiSearchControllerProvider = StateNotifierProvider.autoDispose<AiSearchController, AiSearchState>(
  (ref) => AiSearchController(ref.watch(aiSearchRepositoryProvider), ref.watch(analyticsServiceProvider)),
);

/// Budget presets (IQD) for the budget chips; null = any budget.
const aiSearchBudgets = <int>[25000, 50000, 100000, 200000];
