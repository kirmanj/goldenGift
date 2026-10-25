import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'product_card.dart';

enum _SkeletonKind { box, line, productGrid, list }

/// Shimmer loading placeholders (SRS §4.8 — every list screen has a loading
/// skeleton). Presets:
/// * [SkeletonLoader.box] — a rounded block; fills its parent when no size.
/// * [SkeletonLoader.line] — one text line.
/// * [SkeletonLoader.productGrid] — 2-column grid shaped like [ProductCard].
/// * [SkeletonLoader.list] — rows of thumbnail + two lines.
///
/// The grid and list presets do not scroll; place them in a scroll view or
/// a bounded area. Colours follow the active theme (light / dark).
class SkeletonLoader extends StatelessWidget {
  const SkeletonLoader.box({
    super.key,
    this.width,
    this.height,
    this.radius = AppRadius.md,
  })  : _kind = _SkeletonKind.box,
        count = 1;

  const SkeletonLoader.line({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadius.xs,
  })  : _kind = _SkeletonKind.line,
        count = 1;

  const SkeletonLoader.productGrid({super.key, this.count = 4})
      : _kind = _SkeletonKind.productGrid,
        width = null,
        height = null,
        radius = AppRadius.md;

  const SkeletonLoader.list({super.key, this.count = 6})
      : _kind = _SkeletonKind.list,
        width = null,
        height = null,
        radius = AppRadius.md;

  final _SkeletonKind _kind;
  final double? width;
  final double? height;
  final double radius;

  /// Number of items for the grid / list presets.
  final int count;

  /// Shimmer base colour for the current theme.
  static Color baseColor(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkSurfaceSecondary : AppColors.border;

  /// Shimmer highlight colour for the current theme.
  static Color highlightColor(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkBorder : AppColors.surfaceSecondary;

  /// Keeps an explicit [width] inside stretching parents (Column/ListView).
  Widget _sized(Widget block) => width == null
      ? block
      : Align(alignment: AlignmentDirectional.centerStart, heightFactor: 1, child: block);

  @override
  Widget build(BuildContext context) {
    final content = switch (_kind) {
      _SkeletonKind.box => _sized(_Block(width: width, height: height, radius: radius)),
      _SkeletonKind.line => _sized(
          _Block(width: width ?? double.infinity, height: height, radius: radius),
        ),
      _SkeletonKind.productGrid => _ProductGridSkeleton(count: count),
      _SkeletonKind.list => _ListSkeleton(count: count),
    };
    final shimmer = Shimmer.fromColors(
      baseColor: baseColor(context),
      highlightColor: highlightColor(context),
      period: const Duration(milliseconds: 1400),
      child: content,
    );
    // Single blocks are usually part of a larger loading layout; only the
    // composite presets announce themselves to screen readers.
    if (_kind == _SkeletonKind.box || _kind == _SkeletonKind.line) {
      return ExcludeSemantics(child: shimmer);
    }
    return Semantics(
      label: AppLocalizations.of(context)?.loading,
      child: ExcludeSemantics(child: shimmer),
    );
  }
}

/// Solid block that the shimmer gradient paints over. With no size it
/// expands to a bounded parent (and collapses to zero when unbounded).
class _Block extends StatelessWidget {
  const _Block({this.width, this.height, required this.radius});
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: SkeletonLoader.baseColor(context),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class _ProductGridSkeleton extends StatelessWidget {
  const _ProductGridSkeleton({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: count,
        gridDelegate: ProductCard.gridDelegate(context, constraints.maxWidth),
        itemBuilder: (_, __) => const _ProductCardSkeleton(),
      ),
    );
  }
}

class _ProductCardSkeleton extends StatelessWidget {
  const _ProductCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(ProductCard.imageInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 1, child: _Block(radius: AppRadius.md)),
          SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          _Block(width: double.infinity, height: 14, radius: AppRadius.xs),
          SizedBox(height: AppSpacing.sm),
          FractionallySizedBox(
            widthFactor: 0.6,
            child: _Block(height: 14, radius: AppRadius.xs),
          ),
          SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          FractionallySizedBox(
            widthFactor: 0.45,
            child: _Block(height: 18, radius: AppRadius.xs),
          ),
        ],
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                _Block(width: 64, height: 64, radius: AppRadius.md),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Block(width: double.infinity, height: 14, radius: AppRadius.xs),
                      SizedBox(height: AppSpacing.sm),
                      FractionallySizedBox(
                        widthFactor: 0.7,
                        child: _Block(height: 12, radius: AppRadius.xs),
                      ),
                      SizedBox(height: AppSpacing.sm),
                      FractionallySizedBox(
                        widthFactor: 0.35,
                        child: _Block(height: 12, radius: AppRadius.xs),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
