import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../../data/ai_search_repository.dart';

/// 2-column AI results (SRS §5.6): a [ProductCard] (wishlist heart as in
/// the products list) with Gemini's one-line "why" under it.
class AiSuggestionGrid extends ConsumerWidget {
  const AiSuggestionGrid({super.key, required this.suggestions});

  final List<AiSuggestion> suggestions;

  static const double _captionFont = 12;
  static const double _captionHeight = 1.4;
  static const int _captionLines = 2;

  static double captionExtent(BuildContext context) =>
      AppSpacing.xs + _captionLines * MediaQuery.textScalerOf(context).scale(_captionFont) * _captionHeight + 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(wishlistIdsProvider);
    final withReasons = suggestions.any((s) => (s.reason ?? '').trim().isNotEmpty);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.gridGap;
        final cardWidth = (constraints.crossAxisExtent - gap) / 2;
        final cardHeight = ProductCard.heightFor(context, cardWidth);
        final extent = cardHeight + (withReasons ? captionExtent(context) : 0);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: extent,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final s = suggestions[i];
              final product = s.product;
              final reason = (s.reason ?? '').trim();
              return Column(
                key: ValueKey('ai-result-${product.id}'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: cardHeight,
                    child: ProductCard(
                      product: product,
                      isWishlisted: saved.contains(product.id),
                      onWishlistChanged: (_) => toggleWishlist(context, ref, product),
                      onTap: () => unawaited(context.push(AppRoutes.product(product.id))),
                    ),
                  ),
                  if (reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs, start: AppSpacing.xxs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xxs),
                            child: Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.gold(context)),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              reason,
                              key: ValueKey('ai-reason-${product.id}'),
                              maxLines: _captionLines,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                fontSize: _captionFont,
                                height: _captionHeight,
                                color: AppColors.textMuted(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
            childCount: suggestions.length,
          ),
        );
      },
    );
  }
}
