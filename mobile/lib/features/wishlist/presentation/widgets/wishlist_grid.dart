import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../../data/wishlist_repository.dart';
import '../providers/wishlist_providers.dart';
import 'wishlist_list_sheets.dart';

/// 2-column grid of saved gifts, same card as the products list (SRS §5.15,
/// §5.8). Cards are built from the denormalized wishlist entry, so the list
/// costs no product reads; the heart (always active here) removes the gift.
/// With more than one list, each card gets a "Move to…" button (also on
/// long-press). [header] slivers (the list chips) scroll with the grid.
class WishlistGrid extends ConsumerStatefulWidget {
  const WishlistGrid({
    super.key,
    required this.items,
    required this.bottomPadding,
    this.header = const [],
    this.canMove = false,
  });

  final List<WishlistItem> items;
  final double bottomPadding;
  final List<Widget> header;

  /// Show "Move to…" on every card.
  final bool canMove;

  /// The card's product: enough for image, title, price and navigation.
  static ProductModel productFor(WishlistItem item) => ProductModel(
        id: item.productId,
        title: item.title,
        images: [if (item.image != null && item.image!.isNotEmpty) item.image!],
        price: item.price,
        storeId: '',
      );

  @override
  ConsumerState<WishlistGrid> createState() => _WishlistGridState();
}

class _WishlistGridState extends ConsumerState<WishlistGrid> {
  /// Re-keys a card whose heart tap changed nothing (e.g. a failed write),
  /// resetting the heart's optimistic flip.
  final _epochs = <String, int>{};

  Future<void> _remove(ProductModel product) async {
    final result = await toggleWishlist(context, ref, product);
    if (result == null && mounted) {
      setState(() => _epochs[product.id] = (_epochs[product.id] ?? 0) + 1);
    }
  }

  Future<void> _move(WishlistItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final list = await showWishlistListPicker(context, title: l10n.wishlistMoveTo, selectedId: item.listId);
    if (list == null || list.id == item.listId || !mounted) return;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    try {
      await ref.read(wishlistRepositoryProvider).moveItem(uid, item.productId, list.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.wishlistMovedTo(wishlistListName(l10n, list)))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CustomScrollView(
      slivers: [
        ...widget.header,
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
            AppSpacing.screenHorizontal,
            widget.bottomPadding,
          ),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid(
              gridDelegate: ProductCard.gridDelegate(context, constraints.crossAxisExtent),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = widget.items[i];
                  final product = WishlistGrid.productFor(item);
                  final card = ProductCard(
                    key: ValueKey('${product.id}#${_epochs[product.id] ?? 0}'),
                    product: product,
                    isWishlisted: true,
                    onTap: () => unawaited(context.push(AppRoutes.product(product.id))),
                    onWishlistChanged: (_) => unawaited(_remove(product)),
                  );
                  if (!widget.canMove) return card;
                  return GestureDetector(
                    key: ValueKey('wishlist-card-${product.id}'),
                    onLongPress: () => unawaited(_move(item)),
                    // Shortcut only: screen readers use the labelled "Move to" button.
                    excludeFromSemantics: true,
                    child: Stack(
                      children: [
                        card,
                        PositionedDirectional(
                          top: ProductCard.imageInset + AppSpacing.xs,
                          start: ProductCard.imageInset + AppSpacing.xs,
                          child: GGCircleButton(
                            key: ValueKey('wishlist-move-${product.id}'),
                            icon: Icons.drive_file_move_outline,
                            iconSize: 20,
                            size: 36,
                            tooltip: l10n.wishlistMoveTo,
                            onPressed: () => unawaited(_move(item)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                childCount: widget.items.length,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
