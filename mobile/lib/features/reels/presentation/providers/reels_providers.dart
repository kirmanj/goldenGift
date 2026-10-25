import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../models/reel_model.dart';
import '../../data/reels_repository.dart';

/// The Reels filter (SRS §5.27); the feed restarts when it changes.
final reelsFilterProvider = StateProvider<ReelFilter>((ref) => const ReelFilter());

/// Sound on every reel until the app restarts: on in the apps, off on the
/// web, where browsers block autoplay with sound (SRS §5.27).
final reelsSoundOnProvider = StateProvider<bool>((ref) => !kIsWeb);

/// Creates the player of a reel. Tests override it (or the video_player
/// platform) — there is no video decoder in widget tests.
final reelVideoControllerFactoryProvider = Provider<VideoPlayerController Function(String url)>(
  (ref) => (url) => VideoPlayerController.networkUrl(Uri.parse(url)),
);

class ReelsFeedState {
  const ReelsFeedState({
    this.items = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.cursor,
  });

  final List<ReelModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;

  /// First page failed (error state with Retry).
  final Object? error;
  final DocumentSnapshot<Object?>? cursor;

  bool get isEmpty => !isLoading && error == null && items.isEmpty;

  ReelsFeedState copyWith({
    List<ReelModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    DocumentSnapshot<Object?>? cursor,
  }) =>
      ReelsFeedState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: error,
        cursor: cursor ?? this.cursor,
      );
}

/// The feed of one [ReelFilter], 8 reels per page (SRS §5.27).
class ReelsFeedController extends StateNotifier<ReelsFeedState> {
  ReelsFeedController(this._repository, this.filter) : super(const ReelsFeedState()) {
    _loadFirst();
  }

  final ReelsRepository _repository;
  final ReelFilter filter;
  int _generation = 0;

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    try {
      final page = await _repository.fetch(filter);
      if (!mounted || generation != _generation) return;
      state = ReelsFeedState(items: page.items, isLoading: false, hasMore: page.hasMore, cursor: page.cursor);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = ReelsFeedState(isLoading: false, hasMore: false, error: e);
    }
  }

  /// Next page; a failure only stops paging (the reels already shown stay).
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore || state.error != null) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repository.fetch(filter, after: state.cursor);
      if (!mounted || generation != _generation) return;
      final seen = {for (final r in state.items) r.id};
      state = state.copyWith(
        items: [...state.items, ...page.items.where((r) => !seen.contains(r.id))],
        isLoadingMore: false,
        hasMore: page.hasMore,
        cursor: page.cursor,
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(isLoadingMore: false, hasMore: false);
    }
  }

  /// Retry after an error.
  Future<void> refresh() {
    state = const ReelsFeedState();
    return _loadFirst();
  }
}

final reelsFeedProvider =
    StateNotifierProvider.autoDispose.family<ReelsFeedController, ReelsFeedState, ReelFilter>(
  (ref, filter) => ReelsFeedController(ref.watch(reelsRepositoryProvider), filter),
);
