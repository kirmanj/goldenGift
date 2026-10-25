import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../product_details/data/photo_service.dart';
import '../../../product_details/domain/product_configuration.dart';
import '../../../product_details/presentation/widgets/photo_upload_grid.dart' show showPhotoSourceSheet;

/// Picks one photo (camera / gallery sheet → crop → compress) and reports
/// "too large" / failures in a snack bar. Null when cancelled.
Future<PickedPhoto?> pickOnePhoto(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(photoServiceProvider);
  final source = await showPhotoSourceSheet(context);
  if (source == null) return null;
  void snack(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  try {
    return await service.pick(source);
  } on PhotoTooLargeException {
    snack(l10n.photoTooLarge);
  } catch (_) {
    snack(l10n.somethingWentWrong);
  }
  return null;
}

/// A row of removable thumbnails plus a dashed "add photo" tile while fewer
/// than [max] are picked (Special Requests IMG_4492, partner samples, the
/// gift-card photo). Photos stay in memory until the form uploads them.
class PickedPhotosField extends ConsumerWidget {
  const PickedPhotosField({
    super.key,
    required this.photos,
    required this.max,
    required this.onAdd,
    required this.onRemove,
    this.enabled = true,
    this.tileSize = 88,
    this.keyPrefix = 'photos',
  });

  final List<PickedPhoto> photos;
  final int max;
  final ValueChanged<PickedPhoto> onAdd;
  final ValueChanged<int> onRemove;
  final bool enabled;
  final double tileSize;

  /// Keys: `{prefix}-add`, `{prefix}-remove-{i}`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.sm + AppSpacing.xs,
      runSpacing: AppSpacing.sm + AppSpacing.xs,
      children: [
        for (var i = 0; i < photos.length; i++)
          SizedBox.square(
            dimension: tileSize,
            child: _Thumb(
              photo: photos[i],
              label: l10n.photoSlot(i + 1),
              removeKey: ValueKey('$keyPrefix-remove-$i'),
              onRemove: enabled ? () => onRemove(i) : null,
            ),
          ),
        if (photos.length < max)
          SizedBox.square(
            dimension: tileSize,
            child: DashedAddTile(
              key: ValueKey('$keyPrefix-add'),
              label: l10n.srAddPhoto,
              onTap: !enabled
                  ? null
                  : () async {
                      final photo = await pickOnePhoto(context, ref);
                      if (photo != null) onAdd(photo);
                    },
            ),
          ),
      ],
    );
  }
}

/// Soft tile with a dashed gold outline and an "add image" icon.
class DashedAddTile extends StatelessWidget {
  const DashedAddTile({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.gold(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: CustomPaint(
        painter: DashedRRectPainter(color: color, radius: AppRadius.lg),
        child: Material(
          color: AppColors.field(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(child: Icon(Icons.add_photo_alternate_outlined, size: 30, color: color)),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.label, required this.removeKey, required this.onRemove});

  final PickedPhoto photo;
  final String label;
  final Key removeKey;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: LayoutBuilder(builder: (context, c) {
            final dpr = MediaQuery.devicePixelRatioOf(context);
            return Image.memory(
              photo.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: c.maxWidth.isFinite ? (c.maxWidth * dpr).round() : null,
              semanticLabel: label,
              errorBuilder: (context, _, __) => ColoredBox(
                color: AppColors.field(context),
                child: Icon(Icons.image_outlined, color: AppColors.gold(context)),
              ),
            );
          }),
        ),
        if (onRemove != null)
          PositionedDirectional(
            top: 0,
            end: 0,
            child: GGCircleButton(
              key: removeKey,
              icon: Icons.close_rounded,
              size: 28,
              iconSize: 16,
              tooltip: l10n.removePhoto,
              onPressed: onRemove,
            ),
          ),
      ],
    );
  }
}

/// Rounded-rect dashed outline.
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dash = 6;
  static const double _gap = 4;
  static const double _stroke = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) => old.color != color || old.radius != radius;
}

/// "Uploading photos… 40%" under a form while its photos upload.
class UploadProgressLine extends StatelessWidget {
  const UploadProgressLine({super.key, required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final percent = (progress.clamp(0, 1) * 100).round();
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 6,
              color: AppColors.gold(context),
              backgroundColor: AppColors.field(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.uploadingPhotos(percent),
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
          ),
        ],
      ),
    );
  }
}
