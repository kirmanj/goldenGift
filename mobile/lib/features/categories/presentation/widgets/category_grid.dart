import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/category_model.dart';
import '../providers/categories_providers.dart';

/// Grid geometry shared by the All Categories grid and the Home 2×4 grid:
/// square tiles + two label lines, sized for the current text scale.
SliverGridDelegate categoryGridDelegate(
  BuildContext context,
  double width, {
  required int columns,
  double crossAxisSpacing = AppSpacing.md,
  double mainAxisSpacing = AppSpacing.lg,
}) {
  final tileWidth = (width - crossAxisSpacing * (columns - 1)) / columns;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: crossAxisSpacing,
    mainAxisSpacing: mainAxisSpacing,
    mainAxisExtent: CategoryTile.heightFor(context, tileWidth),
  );
}

/// All Categories grid (SRS §5.7, IMG_4496–4500): 3 columns of
/// [CategoryTile]s whose labels wrap to two lines. Lazily built. Coming soon
/// categories (themselves or through a parent in [categories]) show the
/// "Soon" pill (§5.7a).
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.categories,
    required this.onTap,
    this.padding = EdgeInsets.zero,
    this.all,
  });

  static const columns = 3;

  final List<CategoryModel> categories;

  /// The whole list, for the coming-soon parents of a filtered [categories].
  final List<CategoryModel>? all;
  final ValueChanged<CategoryModel> onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final soon = comingSoonIdsIn(all ?? categories);
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        gridDelegate: categoryGridDelegate(
          context,
          constraints.maxWidth - padding.horizontal,
          columns: columns,
        ),
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final category = categories[i];
          return CategoryTile(
            key: ValueKey(category.id),
            label: category.title.of(context),
            iconUrl: category.iconUrl,
            comingSoon: soon.contains(category.id),
            onTap: () => onTap(category),
          );
        },
      ),
    );
  }
}

/// Loading placeholder shaped like a [CategoryTile] (square + label line).
class CategoryTileSkeleton extends StatelessWidget {
  const CategoryTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AspectRatio(aspectRatio: 1, child: SkeletonLoader.box(radius: AppRadius.md)),
        SizedBox(height: AppSpacing.sm),
        FractionallySizedBox(widthFactor: 0.7, child: SkeletonLoader.line(height: 12)),
      ],
    );
  }
}
