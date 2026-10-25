import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/reel_model.dart';

import 'data/reels_admin_repository.dart';

/// Status colour (SRS §9 Reels: Active / Hidden / Product unavailable).
Color reelStatusColor(BuildContext context, ReelStatus s) => switch (s) {
      ReelStatus.active => AppColors.success,
      ReelStatus.hidden => AppColors.textMuted(context),
      ReelStatus.productUnavailable => AppColors.warning,
    };

/// Status chip. [onDark] = drawn over a poster (dark glass, white label).
class ReelStatusBadge extends StatelessWidget {
  const ReelStatusBadge({super.key, required this.status, this.onDark = false});
  final ReelStatus status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark && status == ReelStatus.hidden ? AppColors.darkTextSecondary : reelStatusColor(context, status);
    final icon = switch (status) {
      ReelStatus.active => Icons.circle,
      ReelStatus.hidden => Icons.visibility_off_outlined,
      ReelStatus.productUnavailable => Icons.warning_amber_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: onDark ? AppColors.black.withValues(alpha: 0.62) : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            status.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: onDark ? AppColors.white : color, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

/// A 9:16 poster: picked bytes, else the stored URL, else a play-icon placeholder.
class ReelPosterImage extends StatelessWidget {
  const ReelPosterImage({super.key, this.url, this.bytes, this.cacheWidth = 440});
  final String? url;
  final Uint8List? bytes;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: AppColors.field(context),
      child: Center(child: Icon(Icons.play_circle_outline, size: 40, color: AppColors.textMuted(context))),
    );
    final b = bytes, u = url;
    if (b != null) {
      return Image.memory(b, fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: (_, __, ___) => placeholder);
    }
    if (u != null && u.isNotEmpty) {
      return Image.network(u, fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: (_, __, ___) => placeholder);
    }
    return placeholder;
  }
}

enum ReelCardAction { edit, toggleActive, delete }

/// One reel of the grid: the 9:16 poster with its status, duration, product
/// and caption on dark scrims (like the app's Reels tab), and the actions menu.
class ReelCard extends StatelessWidget {
  const ReelCard({super.key, required this.reel, required this.onAction, this.busy = false});
  final ReelModel reel;
  final ValueChanged<ReelCardAction> onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = reelStatusOf(reel);
    final duration = formatReelDuration(reel.durationMs);
    final title = reel.product?.title.en ?? '';
    final caption = reel.caption.en.trim();
    // Text and icons on the poster sit on dark scrims (white on ≥ 60 % black).
    final scrimTop = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [AppColors.black.withValues(alpha: 0.6), AppColors.black.withValues(alpha: 0)],
    );
    final scrimBottom = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [AppColors.black.withValues(alpha: 0), AppColors.black.withValues(alpha: 0.85)],
    );
    final white = theme.textTheme.bodySmall?.copyWith(color: AppColors.white);
    return Card(
      key: ValueKey('reel-${reel.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : () => onAction(ReelCardAction.edit),
        child: Stack(fit: StackFit.expand, children: [
          ReelPosterImage(url: reel.posterUrl),
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            height: 64,
            child: DecoratedBox(decoration: BoxDecoration(gradient: scrimTop)),
          ),
          PositionedDirectional(
            top: AppSpacing.xs,
            start: AppSpacing.sm,
            end: 0,
            child: Row(children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ReelStatusBadge(status: status, onDark: true),
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                  ),
                )
              else
                PopupMenuButton<ReelCardAction>(
                  tooltip: 'Reel actions',
                  icon: const Icon(Icons.more_vert, color: AppColors.white),
                  onSelected: onAction,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: ReelCardAction.edit, child: Text('Edit')),
                    PopupMenuItem(
                      value: ReelCardAction.toggleActive,
                      child: Text(reel.isActive ? 'Hide' : 'Activate'),
                    ),
                    const PopupMenuItem(value: ReelCardAction.delete, child: Text('Delete')),
                  ],
                ),
            ]),
          ),
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: scrimBottom),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xl, AppSpacing.sm, AppSpacing.sm),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (duration != null)
                    Row(children: [
                      const Icon(Icons.play_arrow_rounded, size: 14, color: AppColors.white),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(duration, key: ValueKey('duration-${reel.id}'), style: white),
                    ]),
                  Text(
                    title.isEmpty ? reel.productId : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(color: AppColors.white, fontWeight: FontWeight.w700),
                  ),
                  if (caption.isNotEmpty)
                    Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: white?.copyWith(color: AppColors.white.withValues(alpha: 0.88)),
                    ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
