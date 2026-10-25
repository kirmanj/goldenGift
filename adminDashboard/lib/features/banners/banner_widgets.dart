import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import 'banners_data.dart';

/// Live / Scheduled / Expired / Inactive pill.
class BannerStatusBadge extends StatelessWidget {
  const BannerStatusBadge({super.key, required this.status});
  final BannerStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BannerStatus.live => AppColors.success,
      BannerStatus.scheduled => AppColors.info,
      BannerStatus.expired => AppColors.error,
      BannerStatus.inactive => AppColors.textMuted(context),
    };
    final icon = switch (status) {
      BannerStatus.live => Icons.circle,
      BannerStatus.scheduled => Icons.schedule,
      BannerStatus.expired => Icons.history,
      BannerStatus.inactive => Icons.pause_circle_outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(status.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// 16:7 artwork preview with a placeholder.
class BannerThumb extends StatelessWidget {
  const BannerThumb({super.key, required this.url, this.width = 128});
  final String url;
  final double width;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: AppColors.field(context),
      child: Icon(Icons.image_outlined, color: AppColors.textMuted(context)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: SizedBox(
        width: width,
        height: width * 7 / 16,
        child: url.isEmpty
            ? placeholder
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
      ),
    );
  }
}
