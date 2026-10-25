import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/connectivity_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../../../categories/presentation/providers/categories_providers.dart';
import '../../../categories/presentation/widgets/category_grid.dart';
import '../../../products/data/product_query.dart';
import '../../../products/presentation/widgets/gift_audience_widgets.dart';
import '../../../products/presentation/widgets/product_sliver_grid.dart';
import '../banner_actions.dart';
import '../providers/home_providers.dart';

/// Shared Home spacing: every section owns its top gap, so a hidden section
/// leaves no hole.
class HomeLayout {
  HomeLayout._();
  static const double h = AppSpacing.screenHorizontal;
  static const double sectionGap = AppSpacing.lg;

  static const EdgeInsets section = EdgeInsets.fromLTRB(h, sectionGap, h, 0);
}

/// Nothing (a hidden section).
const _hidden = SliverToBoxAdapter();

/// "Offline — showing saved items" while Firestore serves only its cache (SRS §4.8).
class HomeOfflineChip extends ConsumerWidget {
  const HomeOfflineChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isOfflineProvider).valueOrNull != true) return _hidden;
    return const SliverPadding(
      padding: EdgeInsets.fromLTRB(HomeLayout.h, AppSpacing.md, HomeLayout.h, 0),
      sliver: SliverToBoxAdapter(
        child: Align(alignment: AlignmentDirectional.centerStart, child: OfflineChip()),
      ),
    );
  }
}

/// One banner placement (SRS §5.4 items 2, 5, 8, 10): carousel of the live
/// banners in the app's language; tap runs the banner's action.
class HomeBannerSection extends ConsumerWidget {
  const HomeBannerSection({super.key, required this.placement});

  final BannerPlacement placement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeBannersProvider);
    final padding = placement == BannerPlacement.homeTop
        ? const EdgeInsets.fromLTRB(HomeLayout.h, AppSpacing.md, HomeLayout.h, 0)
        : HomeLayout.section;
    if (!async.hasValue) {
      if (async.hasError) return _hidden;
      return SliverPadding(
        padding: padding,
        sliver: const SliverToBoxAdapter(
          child: AspectRatio(aspectRatio: 16 / 7, child: SkeletonLoader.box(radius: AppRadius.lg)),
        ),
      );
    }
    final banners = async.requireValue[placement] ?? const [];
    if (banners.isEmpty) return _hidden;
    final language = Localizations.localeOf(context).languageCode;
    return SliverPadding(
      padding: padding,
      sliver: SliverToBoxAdapter(
        child: BannerCarousel(
          imageUrls: [for (final b in banners) b.imageFor(language)],
          onTap: (i) {
            if (i < banners.length) openBannerAction(context, banners[i]);
          },
        ),
      ),
    );
  }
}

/// 2 rows × 4: the first 7 categories + "More" (SRS §5.4 item 3, IMG_4476).
/// Coming soon categories keep their tile with the "Soon" pill (§5.7a).
class HomeCategoryGrid extends ConsumerWidget {
  const HomeCategoryGrid({super.key});

  static const columns = 4;
  static const shownCategories = 7;
  static const _crossSpacing = AppSpacing.sm + AppSpacing.xs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeCategoriesProvider);
    if (!async.hasValue) {
      if (async.hasError) return _hidden;
      return SliverPadding(
        padding: HomeLayout.section,
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) => SliverGrid(
            gridDelegate: categoryGridDelegate(
              context,
              constraints.crossAxisExtent,
              columns: columns,
              crossAxisSpacing: _crossSpacing,
              mainAxisSpacing: AppSpacing.md,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, __) => const CategoryTileSkeleton(),
              childCount: columns * 2,
            ),
          ),
        ),
      );
    }
    final soon = comingSoonIdsIn(async.requireValue);
    final categories = async.requireValue.take(shownCategories).toList();
    if (categories.isEmpty) return _hidden;
    return SliverPadding(
      padding: HomeLayout.section,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) => SliverGrid(
          gridDelegate: categoryGridDelegate(
            context,
            constraints.crossAxisExtent,
            columns: columns,
            crossAxisSpacing: _crossSpacing,
            mainAxisSpacing: AppSpacing.md,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              if (i == categories.length) {
                return CategoryTile.more(onTap: () => context.push(AppRoutes.categories));
              }
              final category = categories[i];
              return CategoryTile(
                key: ValueKey(category.id),
                label: category.title.of(context),
                iconUrl: category.iconUrl,
                comingSoon: soon.contains(category.id),
                onTap: () => context.push(AppRoutes.productsFor(ProductQuery(categoryId: category.id))),
              );
            },
            childCount: categories.length + 1,
          ),
        ),
      ),
    );
  }
}

/// "Shop for" (SRS §5.4 item 3, §5.8a): For him · For her · For companies,
/// each opening the products list filtered by that gift type. No reads.
class HomeShopForSection extends StatelessWidget {
  const HomeShopForSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SliverPadding(
      padding: HomeLayout.section,
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: l10n.shopForTitle),
            const SizedBox(height: AppSpacing.sm),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, audience) in GiftAudience.values.indexed) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(
                      child: GiftAudienceTile(
                        audience: audience,
                        onTap: () => openGiftAudience(context, audience),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum HomeProductKind { popular, featured, forYou }

/// Popular / Featured / For you (SRS §5.4 items 4, 7, 9): title + "View All"
/// (the same query on the products list) + 2-column cards.
class HomeProductSection extends ConsumerWidget {
  const HomeProductSection(this.kind, {super.key});

  final HomeProductKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final (StreamProvider<List<ProductModel>> provider, ProductQuery query, String title) = switch (kind) {
      HomeProductKind.popular => (popularProductsProvider, HomeQueries.popular, l10n.popular),
      HomeProductKind.featured => (featuredProductsProvider, HomeQueries.featured, l10n.featured),
      HomeProductKind.forYou => (forYouProductsProvider, HomeQueries.forYou, l10n.forYou),
    };
    final async = ref.watch(provider);
    if (!async.hasValue) {
      if (async.hasError) return _hidden;
      return SliverPadding(
        padding: HomeLayout.section,
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: title),
              const SizedBox(height: AppSpacing.sm),
              const SkeletonLoader.productGrid(count: 2),
            ],
          ),
        ),
      );
    }
    final products = async.requireValue;
    if (products.isEmpty) return _hidden;
    return SliverPadding(
      padding: HomeLayout.section,
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: SectionHeader(
              title: title,
              onViewAll: () => context.push(AppRoutes.productsFor(query)),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
          ProductSliverGrid(products: products),
        ],
      ),
    );
  }
}
