import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'skeleton_loader.dart';

/// Cached network image with a shimmer placeholder and a soft fallback tile
/// (SRS §5.4 AC: `cached_network_image` + shimmer placeholders).
///
/// A null / empty [url] renders the fallback without touching the network,
/// so catalogue items without images (and widget tests) stay offline.
/// Decodes at the laid-out size to keep 2-column grids at 60 fps.
class GGNetworkImage extends StatelessWidget {
  const GGNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.card_giftcard_rounded,
    this.fallbackColor,
    this.semanticLabel,
  });

  final String? url;
  final BoxFit fit;
  final IconData fallbackIcon;

  /// Fallback tile background; defaults to `AppColors.field(context)`.
  final Color? fallbackColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final src = url;
    if (src == null || src.isEmpty) return _fallback(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final w = constraints.maxWidth;
        final cacheWidth = w.isFinite && w > 0 ? (w * dpr).round() : null;
        final image = CachedNetworkImage(
          imageUrl: src,
          fit: fit,
          width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
          height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
          memCacheWidth: cacheWidth,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (_, __) => const SkeletonLoader.box(radius: 0),
          errorWidget: (context, _, __) => _fallback(context),
        );
        if (semanticLabel == null) return ExcludeSemantics(child: image);
        return Semantics(image: true, label: semanticLabel, child: image);
      },
    );
  }

  Widget _fallback(BuildContext context) => Container(
        color: fallbackColor ?? AppColors.field(context),
        alignment: Alignment.center,
        child: LayoutBuilder(
          builder: (context, c) {
            final side = c.biggest.shortestSide;
            final iconSize = side.isFinite ? (side * 0.5).clamp(16.0, 64.0) : 32.0;
            return Icon(
              fallbackIcon,
              size: iconSize,
              color: AppColors.gold(context).withValues(alpha: 0.55),
              semanticLabel: semanticLabel,
            );
          },
        ),
      );
}
