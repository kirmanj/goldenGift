import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/services/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/reel_model.dart';
import '../../../categories/presentation/providers/categories_providers.dart';
import '../../../products/presentation/gift_audience_ui.dart';
import '../../../products/presentation/widgets/product_filter_sheet.dart' show priceBandLabel;
import '../../data/reels_repository.dart';
import '../providers/reels_providers.dart';
import '../widgets/reel_page.dart';
import '../widgets/reels_filter_sheet.dart';

/// The Reels tab (SRS §5.27): product videos in a vertical pager, filterable
/// by category, price and gift type. Black in both themes (it uses the dark
/// theme, so every token reads light-on-dark).
///
/// Videos play only while [active] (the visible tab), the app is in the
/// foreground and nothing covers the Main route (Product Details, a sheet).
class ReelsScreen extends ConsumerWidget {
  const ReelsScreen({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reelsFilterProvider);
    return Theme(
      data: AppTheme.darkTheme(Localizations.localeOf(context)),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Material(
          color: AppColors.black,
          child: Stack(
            children: [
              // A new filter is a new feed (and new players), from the top.
              Positioned.fill(
                child: ReelsFeed(key: ValueKey(filter), filter: filter, active: active),
              ),
              PositionedDirectional(top: 0, start: 0, end: 0, child: _ReelsTopBar(filter: filter)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title, sound and filter buttons, and the active filters as removable chips.
class _ReelsTopBar extends ConsumerWidget {
  const _ReelsTopBar({required this.filter});
  final ReelFilter filter;

  Future<void> _openFilter(BuildContext context, WidgetRef ref) async {
    final next = await showReelsFilterSheet(context, filter);
    if (next != null) ref.read(reelsFilterProvider.notifier).state = next;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final soundOn = ref.watch(reelsSoundOnProvider);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    void set(ReelFilter f) => ref.read(reelsFilterProvider.notifier).state = f;
    final category = filter.categoryId == null ? null : ref.watch(categoryByIdProvider(filter.categoryId!));

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.black.withValues(alpha: 0.7), AppColors.black.withValues(alpha: 0)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
            AppSpacing.screenHorizontal,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.reels,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.heading2.copyWith(color: AppColors.white),
                      ),
                    ),
                  ),
                  GGCircleButton(
                    icon: soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    tooltip: soundOn ? l10n.reelsSoundOff : l10n.reelsSoundOn,
                    toggled: soundOn,
                    onPressed: () => ref.read(reelsSoundOnProvider.notifier).state = !soundOn,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  GGCircleButton(
                    icon: Icons.tune_rounded,
                    tooltip: l10n.filters,
                    badgeCount: filter.activeCount,
                    onPressed: () => _openFilter(context, ref),
                  ),
                ],
              ),
              if (!filter.isEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (filter.giftFor != null)
                        _ActiveFilterChip(
                          label: filter.giftFor!.label(l10n),
                          onRemove: () => set(filter.copyWith(clearGiftFor: true)),
                        ),
                      if (filter.filtersPrice)
                        for (final band in filter.priceBands.toList()..sort())
                          _ActiveFilterChip(
                            label: priceBandLabel(l10n, band, rtl: rtl),
                            onRemove: () => set(filter.copyWith(priceBands: {...filter.priceBands}..remove(band))),
                          ),
                      if (filter.categoryId != null)
                        _ActiveFilterChip(
                          label: category?.title.of(context) ?? l10n.reelsCategory,
                          onRemove: () => set(filter.copyWith(clearCategory: true)),
                        ),
                      TextButton(
                        onPressed: () => set(const ReelFilter()),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.goldText(context),
                          minimumSize: const Size.square(AppSpacing.minTapTarget),
                          shape: const StadiumBorder(),
                          textStyle: AppTextStyles.link.copyWith(
                            fontFamily: AppTextStyles.fontFamily(Localizations.localeOf(context)),
                          ),
                        ),
                        child: Text(l10n.clear),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A chosen filter with a ✕ (48 dp tall tap target).
class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
      child: Semantics(
        button: true,
        label: '$label, ${l10n.reelsRemoveFilter}',
        excludeSemantics: true,
        onTap: onRemove,
        child: Tooltip(
          message: l10n.reelsRemoveFilter,
          excludeFromSemantics: true,
          child: Material(
            color: AppColors.white.withValues(alpha: 0.16),
            shape: StadiumBorder(side: BorderSide(color: AppColors.gold(context))),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onRemove,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: AppSpacing.md, end: AppSpacing.sm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppTextStyles.label.copyWith(color: AppColors.white)),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.close_rounded, size: 18, color: AppColors.white),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pager and the players of the current reel and its neighbours.
class ReelsFeed extends ConsumerStatefulWidget {
  const ReelsFeed({super.key, required this.filter, required this.active});

  final ReelFilter filter;
  final bool active;

  /// The next page loads this many reels before the end.
  static const loadMoreAhead = 3;

  @override
  ConsumerState<ReelsFeed> createState() => _ReelsFeedState();
}

class _ReelsFeedState extends ConsumerState<ReelsFeed> with WidgetsBindingObserver {
  final _pageController = PageController();
  final _players = <String, VideoPlayerController>{};
  final _failed = <String>{};
  final _viewed = <String>{};
  int _index = 0;
  bool _userPaused = false;
  bool _foreground = true;
  bool _routeCurrent = true;

  List<ReelModel> get _items => ref.read(reelsFeedProvider(widget.filter)).items;

  bool get _shouldPlay => widget.active && _foreground && _routeCurrent && !_userPaused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The feed may already be loaded (the listener below only sees changes).
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A pushed screen or an open sheet makes the Main route not current.
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current != _routeCurrent) {
      _routeCurrent = current;
      _applyPlayback();
    }
  }

  @override
  void didUpdateWidget(ReelsFeed old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      _applyPlayback();
      if (widget.active) _logView();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _applyPlayback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final p in _players.values) {
      unawaited(p.dispose());
    }
    _players.clear();
    _pageController.dispose();
    super.dispose();
  }

  /// Prepares the current reel and its neighbours; releases the others after
  /// this frame (their pages may still be on screen during a swipe).
  void _sync() {
    if (!mounted) return;
    final items = _items;
    final keep = <String>{};
    for (var i = _index - 1; i <= _index + 1; i++) {
      if (i < 0 || i >= items.length) continue;
      final reel = items[i];
      keep.add(reel.id);
      _players.putIfAbsent(reel.id, () => _create(reel));
    }
    final released = [
      for (final id in [..._players.keys])
        if (!keep.contains(id)) _players.remove(id)!,
    ];
    if (released.isNotEmpty) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final p in released) {
          unawaited(p.dispose());
        }
      });
    }
    _applyPlayback();
    _logView();
  }

  VideoPlayerController _create(ReelModel reel) {
    final player = ref.read(reelVideoControllerFactoryProvider)(reel.videoUrl);
    unawaited(player.setLooping(true));
    unawaited(player.setVolume(ref.read(reelsSoundOnProvider) ? 1 : 0));
    player.initialize().then(
      (_) {
        if (!mounted || !identical(_players[reel.id], player)) return;
        setState(() {});
        _applyPlayback();
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed.add(reel.id));
      },
    );
    return player;
  }

  void _applyPlayback() {
    if (!mounted) return;
    final items = _items;
    final currentId = _index < items.length ? items[_index].id : null;
    for (final MapEntry(key: id, value: player) in _players.entries) {
      final value = player.value;
      if (!value.isInitialized || value.hasError) continue;
      if (id == currentId && _shouldPlay) {
        if (!value.isPlaying) unawaited(player.play());
      } else {
        if (value.isPlaying) unawaited(player.pause());
        // A neighbour starts from the beginning when it becomes current.
        if (id != currentId && value.position > Duration.zero) unawaited(player.seekTo(Duration.zero));
      }
    }
  }

  void _logView() {
    final items = _items;
    if (!widget.active || _index >= items.length) return;
    final reel = items[_index];
    if (!_viewed.add(reel.id)) return;
    unawaited(
      ref.read(analyticsServiceProvider).log(AnalyticsEvents.reelView, {
        'reel_id': reel.id,
        'product_id': reel.productId,
      }),
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      _userPaused = false;
    });
    _sync();
    if (index >= _items.length - ReelsFeed.loadMoreAhead) {
      unawaited(ref.read(reelsFeedProvider(widget.filter).notifier).loadMore());
    }
  }

  void _togglePlay() {
    setState(() => _userPaused = !_userPaused);
    _applyPlayback();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = reelsFeedProvider(widget.filter);
    ref.listen<ReelsFeedState>(provider, (prev, next) {
      if (prev?.items.length != next.items.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
      }
    });
    ref.listen<bool>(reelsSoundOnProvider, (_, on) {
      for (final p in _players.values) {
        unawaited(p.setVolume(on ? 1 : 0));
      }
    });
    final feed = ref.watch(provider);

    if (feed.isLoading) return const _FeedSpinner();
    if (feed.error != null) {
      return _FeedMessage(child: ErrorState(onRetry: () => ref.read(provider.notifier).refresh()));
    }
    if (feed.items.isEmpty) {
      final filtered = !widget.filter.isEmpty;
      return _FeedMessage(
        child: EmptyState(
          icon: Icons.slow_motion_video_rounded,
          title: filtered ? l10n.reelsNoMatchTitle : l10n.reelsEmptyTitle,
          subtitle: filtered ? l10n.reelsNoMatchBody : l10n.reelsEmptyBody,
          ctaLabel: filtered ? l10n.reelsClearFilters : null,
          onCta: filtered ? () => ref.read(reelsFilterProvider.notifier).state = const ReelFilter() : null,
        ),
      );
    }

    // Mouse and trackpad drags swipe too (Flutter only drags with touch by
    // default), so the feed works on desktop browsers.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: feed.items.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, i) {
          final reel = feed.items[i];
          return ReelPage(
            key: ValueKey(reel.id),
            reel: reel,
            controller: _players[reel.id],
            failed: _failed.contains(reel.id),
            paused: i == _index && _userPaused,
            onTogglePlay: _togglePlay,
          );
        },
      ),
    );
  }
}

class _FeedSpinner extends StatelessWidget {
  const _FeedSpinner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 36,
        child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.gold(context)),
      ),
    );
  }
}

/// Empty / error states, below the top bar and above the bottom nav.
class _FeedMessage extends StatelessWidget {
  const _FeedMessage({required this.child});
  final Widget child;

  /// Room for the top bar with a row of filter chips.
  static const double _topBarHeight = 120;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return SingleChildScrollView(
      padding: EdgeInsets.only(top: padding.top + _topBarHeight, bottom: padding.bottom + AppSpacing.lg),
      child: child,
    );
  }
}
