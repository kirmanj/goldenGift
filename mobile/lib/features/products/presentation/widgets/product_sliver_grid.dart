import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/product_model.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';

/// Two-column [ProductCard] grid as a sliver (SRS §5.4, §5.8): cards are built
/// lazily and the cells are sized by [ProductCard.gridDelegate] for the
/// current width and text scale. A tap opens Product Details; the heart
/// saves to the wishlist (guests get "Sign in to continue", SRS §5.15).
class ProductSliverGrid extends ConsumerWidget {
  const ProductSliverGrid({super.key, required this.products});

  final List<ProductModel> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(wishlistIdsProvider);
    return SliverLayoutBuilder(
      builder: (context, constraints) => SliverGrid(
        gridDelegate: ProductCard.gridDelegate(context, constraints.crossAxisExtent),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final product = products[i];
            return ProductCard(
              key: ValueKey(product.id),
              product: product,
              isWishlisted: saved.contains(product.id),
              onWishlistChanged: (_) => toggleWishlist(context, ref, product),
              onTap: () {
                context.push(AppRoutes.product(product.id));
              },
            );
          },
          childCount: products.length,
        ),
      ),
    );
  }
}
