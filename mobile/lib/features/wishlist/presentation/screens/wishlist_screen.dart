import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../profile/presentation/widgets/profile_header.dart';
import '../../data/wishlist_repository.dart';
import '../providers/wishlist_providers.dart';
import '../widgets/wishlist_grid.dart';
import '../widgets/wishlist_list_sheets.dart';

/// My Wishlists (SRS §5.15): the signed-in customer's saved gifts as a
/// 2-column product grid; the heart removes, a tap opens Product Details.
/// Phase 9 adds named lists: chips (default list first) filter the grid,
/// "New list" creates one, the ⋯ button renames / deletes the selected named
/// list (its gifts move to the default list) and each card can move.
class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  String _selected = WishlistRepository.defaultList;

  String? get _uid => ref.read(authStateProvider).valueOrNull?.uid;

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _newList() async {
    final l10n = AppLocalizations.of(context)!;
    final name =
        await showWishlistListNameDialog(context, title: l10n.wishlistNewList, confirmLabel: l10n.wishlistCreateList);
    final uid = _uid;
    if (name == null || uid == null || !mounted) return;
    try {
      final id = await ref.read(wishlistRepositoryProvider).createList(uid, name);
      if (mounted) setState(() => _selected = id);
    } catch (_) {
      if (mounted) _snack(l10n.somethingWentWrong);
    }
  }

  Future<void> _listMenu(WishlistList list) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card(context),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WishlistSheetOption(
                key: const ValueKey('wishlist-rename'),
                icon: Icons.edit_outlined,
                label: l10n.wishlistRenameList,
                onTap: () => Navigator.of(sheetContext).pop('rename'),
              ),
              WishlistSheetOption(
                key: const ValueKey('wishlist-delete'),
                icon: Icons.delete_outline_rounded,
                label: l10n.wishlistDeleteList,
                destructive: true,
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    final uid = _uid;
    if (uid == null) return;
    final repo = ref.read(wishlistRepositoryProvider);
    try {
      if (action == 'rename') {
        final name = await showWishlistListNameDialog(
          context,
          title: l10n.wishlistRenameList,
          confirmLabel: l10n.save,
          initial: list.name,
        );
        if (name != null && name != list.name) await repo.renameList(uid, list.id, name);
      } else if (action == 'delete') {
        if (!await confirmDeleteWishlistList(context, list.name)) return;
        await repo.deleteList(uid, list.id);
        if (mounted) setState(() => _selected = WishlistRepository.defaultList);
      }
    } catch (_) {
      if (mounted) _snack(l10n.somethingWentWrong);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    final lists = ref.watch(wishlistListsOrDefaultProvider);
    final selected = lists.firstWhere((l) => l.id == _selected, orElse: () => WishlistList.defaultList);

    final Widget body;
    if (!signedIn) {
      body = ListView(
        padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
        children: [
          ProfileMessageCard(
            key: const ValueKey('wishlist-guest-card'),
            icon: Icons.favorite_rounded,
            title: l10n.signInToContinue,
            body: l10n.signInToContinueBody,
            primaryLabel: l10n.signIn,
            onPrimary: () => unawaited(context.push(AppRoutes.signIn)),
            secondaryLabel: l10n.signUp,
            onSecondary: () => unawaited(context.push(AppRoutes.signUp)),
          ),
        ],
      );
    } else {
      body = ref.watch(wishlistItemsProvider).when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
                vertical: AppSpacing.sm,
              ),
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: SkeletonLoader.productGrid(),
              ),
            ),
            error: (_, __) => _Scrollable(
              bottom: bottom,
              child: ErrorState(onRetry: () => ref.invalidate(wishlistItemsProvider)),
            ),
            data: (items) {
              // No gifts and no named lists: the plain v1 empty state.
              if (items.isEmpty && lists.length == 1) {
                return _Scrollable(
                  bottom: bottom,
                  child: EmptyState(
                    title: l10n.wishlistEmptyTitle,
                    subtitle: l10n.wishlistEmptyBody,
                    icon: Icons.favorite_border_rounded,
                    ctaLabel: l10n.startShopping,
                    onCta: () => context.go(AppRoutes.mainTab(0)),
                  ),
                );
              }
              final known = {for (final l in lists) l.id};
              // Gifts in a list that no longer exists show under the default list.
              String listOf(WishlistItem i) => known.contains(i.listId) ? i.listId : WishlistRepository.defaultList;
              final shown = [for (final i in items) if (listOf(i) == selected.id) i];
              final chips = SliverToBoxAdapter(
                child: _ListChips(
                  lists: lists,
                  selectedId: selected.id,
                  onSelect: (id) => setState(() => _selected = id),
                  onNewList: lists.length - 1 < WishlistRepository.maxLists ? _newList : null,
                ),
              );
              if (shown.isEmpty) {
                return CustomScrollView(
                  slivers: [
                    chips,
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: bottom),
                        child: EmptyState(
                          key: const ValueKey('wishlist-list-empty'),
                          title: l10n.wishlistListEmptyTitle,
                          subtitle: l10n.wishlistListEmptyBody,
                          icon: Icons.bookmark_border_rounded,
                          ctaLabel: l10n.startShopping,
                          onCta: () => context.go(AppRoutes.mainTab(0)),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return WishlistGrid(
                items: shown,
                bottomPadding: bottom,
                header: [chips],
                canMove: lists.length > 1,
              );
            },
          );
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        title: l10n.myWishlists,
        actions: [
          if (signedIn && !selected.isDefault)
            GGCircleButton(
              key: const ValueKey('wishlist-list-menu'),
              icon: Icons.more_horiz_rounded,
              tooltip: l10n.wishlistListOptions,
              onPressed: () => unawaited(_listMenu(selected)),
            ),
        ],
      ),
      body: body,
    );
  }
}

/// Horizontal list chips: the default list first, then the named lists, then
/// "+ New list".
class _ListChips extends StatelessWidget {
  const _ListChips({required this.lists, required this.selectedId, required this.onSelect, this.onNewList});

  final List<WishlistList> lists;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback? onNewList;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = [
      for (final list in lists)
        CategoryChip(
          key: ValueKey('wishlist-chip-${list.id}'),
          label: wishlistListName(l10n, list),
          icon: list.isDefault ? Icons.favorite_rounded : Icons.bookmark_border_rounded,
          selected: list.id == selectedId,
          onTap: () => onSelect(list.id),
        ),
      if (onNewList != null)
        CategoryChip(
          key: const ValueKey('wishlist-chip-new'),
          label: l10n.wishlistNewList,
          icon: Icons.add_rounded,
          onTap: onNewList,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: SizedBox(
        height: CategoryChip.height,
        child: ListView.separated(
          key: const ValueKey('wishlist-chips'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, i) => chips[i],
        ),
      ),
    );
  }
}

/// Centres a fixed state but lets it scroll on short screens / large text.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child, required this.bottom});
  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - bottom)),
            child: Center(child: child),
          ),
        ),
      );
}
