import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../../data/photo_service.dart';
import '../../domain/product_configuration.dart';
import '../providers/product_details_controller.dart';

/// `photoUpload` (Upload your photos 1–4, IMG_4502): a 2-column grid of
/// dashed gold boxes numbered 1…N. Tapping an empty box asks for camera or
/// gallery, then [PhotoService.pick] crops and compresses the photo; it is
/// kept in memory as a thumbnail with ✕ until Add to Cart uploads it.
class PhotoUploadGrid extends ConsumerWidget {
  const PhotoUploadGrid({super.key, required this.productId, required this.group, this.hasError = false});

  final String productId;
  final OptionGroup group;
  final bool hasError;

  static const double _aspectRatio = 1.5;

  int get slotCount => math.max(group.maxPhotos ?? group.minPhotos ?? 1, 1);

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(productDetailsControllerProvider(productId).notifier);
    final service = ref.read(photoServiceProvider);
    final source = await showPhotoSourceSheet(context);
    if (source == null) return;
    void snack(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    try {
      final photo = await service.pick(source);
      if (photo == null || !notifier.mounted) return;
      notifier.addPhoto(group.id, photo, maxPhotos: slotCount);
    } on PhotoTooLargeException {
      snack(l10n.photoTooLarge);
    } catch (_) {
      snack(l10n.somethingWentWrong);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(productDetailsControllerProvider(productId)
        .select((s) => s.config?.selectionFor(group.id).photos ?? const <PickedPhoto>[]));
    final slots = math.max(slotCount, photos.length);
    return LayoutBuilder(builder: (context, constraints) {
      const gap = AppSpacing.sm + AppSpacing.xs;
      final width = (constraints.maxWidth - gap) / 2;
      final height = math.max(width / _aspectRatio, _EmptySlot.minHeight(context));
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < slots; i++)
            SizedBox(
              width: width,
              height: height,
              child: i < photos.length
                  ? _PhotoThumb(
                      photo: photos[i],
                      number: i + 1,
                      onRemove: () =>
                          ref.read(productDetailsControllerProvider(productId).notifier).removePhoto(group.id, i),
                    )
                  : _EmptySlot(
                      key: ValueKey('photo-slot-${group.id}-${i + 1}'),
                      number: i + 1,
                      hasError: hasError,
                      onTap: () => _pick(context, ref)),
            ),
        ],
      );
    });
  }
}

/// "Take a photo / Choose from gallery" sheet; null when dismissed.
Future<ImageSource?> showPhotoSourceSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.card(context),
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheetContext) {
      Widget option(IconData icon, String label, ImageSource source) => ListTile(
            minTileHeight: 56,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
            leading: Icon(icon, color: AppColors.gold(sheetContext)),
            title: Text(label, style: AppTextStyles.label.copyWith(color: AppColors.text(sheetContext))),
            onTap: () => Navigator.of(sheetContext).pop(source),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(Icons.photo_camera_outlined, l10n.takePhoto, ImageSource.camera),
              option(Icons.photo_library_outlined, l10n.chooseFromGallery, ImageSource.gallery),
            ],
          ),
        ),
      );
    },
  );
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({super.key, required this.number, required this.onTap, this.hasError = false});

  final int number;
  final VoidCallback onTap;
  final bool hasError;

  static double minHeight(BuildContext context) =>
      AppSpacing.md * 2 + 28 + AppSpacing.xs + MediaQuery.textScalerOf(context).scale(15) * 1.3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = hasError ? AppColors.error : AppColors.gold(context);
    return Semantics(
      button: true,
      label: l10n.photoSlot(number),
      hint: l10n.uploadYourPhotos,
      excludeSemantics: true,
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: color, radius: AppRadius.md),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_upload_outlined, size: 28, color: color),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$number',
                    style: AppTextStyles.label.copyWith(
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: hasError ? AppColors.error : AppColors.goldText(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, required this.number, required this.onRemove});

  final PickedPhoto photo;
  final int number;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: LayoutBuilder(builder: (context, c) {
            final dpr = MediaQuery.devicePixelRatioOf(context);
            return Image.memory(
              photo.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: c.maxWidth.isFinite ? (c.maxWidth * dpr).round() : null,
              semanticLabel: l10n.photoSlot(number),
              errorBuilder: (context, _, __) => ColoredBox(
                color: AppColors.field(context),
                child: Icon(Icons.image_outlined, color: AppColors.gold(context)),
              ),
            );
          }),
        ),
        PositionedDirectional(
          top: 0,
          end: 0,
          child: GGCircleButton(
            icon: Icons.close_rounded,
            size: 30,
            iconSize: 18,
            tooltip: l10n.removePhoto,
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}

/// Rounded-rect dashed outline (the upload boxes in IMG_4502).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

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
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius;
}
