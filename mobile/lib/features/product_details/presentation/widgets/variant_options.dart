import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../../domain/product_configuration.dart';
import '../providers/product_details_controller.dart';
import 'option_formatting.dart';

/// The selected value id of one group — the only thing a value picker rebuilds for.
String? _watchSelected(WidgetRef ref, String productId, String groupId) =>
    ref.watch(productDetailsControllerProvider(productId).select((s) => s.config?.selectionFor(groupId).valueId));

void _select(WidgetRef ref, String productId, String groupId, String valueId) =>
    ref.read(productDetailsControllerProvider(productId).notifier).select(groupId, valueId);

/// Screen-reader label: "Walnut, +5,000 IQD, Out of stock".
String _valueSemantics(BuildContext context, OptionValue value, bool available) {
  final l10n = AppLocalizations.of(context)!;
  return [
    value.label.of(context),
    if (priceDeltaLabel(value.priceDelta) != null) priceDeltaLabel(value.priceDelta)!,
    if (!available) l10n.outOfStock,
  ].join(', ');
}

/// `imageVariant` (Frame Color IMG_4502, Size IMG_4505): horizontal 150 px
/// tiles with image + label (+ price delta); selected = 2 px gold border.
class ImageVariantOptions extends ConsumerWidget {
  const ImageVariantOptions({super.key, required this.productId, required this.group});

  final String productId;
  final OptionGroup group;

  static const double tileWidth = 150;
  static const double _labelFont = 14;
  static const double _deltaFont = 12;
  static const double _lineHeight = 1.3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = _watchSelected(ref, productId, group.id);
    final scaler = MediaQuery.textScalerOf(context);
    final hasDelta = group.values.any((v) => v.priceDelta != 0);
    // 150 × 150 at 1× text; grows with the text scale so labels never clip.
    const imageHeight = 92.0;
    final content = AppSpacing.sm * 2 +
        imageHeight +
        AppSpacing.sm -
        AppSpacing.xxs +
        scaler.scale(_labelFont) * _lineHeight +
        (hasDelta ? scaler.scale(_deltaFont) * _lineHeight : 0) +
        4;
    final height = math.max(tileWidth, content);

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: group.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
        itemBuilder: (context, i) {
          final value = group.values[i];
          final available = ProductConfiguration.isValueAvailable(value);
          return _ImageTile(
            key: ValueKey('option-${group.id}-${value.id}'),
            value: value,
            selected: value.id == selected,
            available: available,
            onTap: available ? () => _select(ref, productId, group.id, value.id) : null,
          );
        },
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({super.key, required this.value, required this.selected, required this.available, this.onTap});

  final OptionValue value;
  final bool selected;
  final bool available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delta = priceDeltaLabel(value.priceDelta);
    final tile = Material(
      color: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: selected ? AppColors.gold(context) : AppColors.line(context),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GGNetworkImage(url: value.imageUrl, fallbackIcon: Icons.image_outlined),
                      if (!available)
                        ColoredBox(
                          color: AppColors.black.withValues(alpha: 0.45),
                          child: Center(child: _SoldOutPill(label: l10n.outOfStock)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm - AppSpacing.xxs),
              Text(
                value.label.of(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.label.copyWith(
                  fontSize: ImageVariantOptions._labelFont,
                  height: ImageVariantOptions._lineHeight,
                  color: AppColors.text(context),
                ),
              ),
              if (delta != null)
                Text(
                  delta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: ImageVariantOptions._deltaFont,
                    height: ImageVariantOptions._lineHeight,
                    fontWeight: FontWeight.w700,
                    color: AppColors.goldText(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: available,
      label: _valueSemantics(context, value, available),
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        width: ImageVariantOptions.tileWidth,
        child: Opacity(opacity: available ? 1 : 0.6, child: tile),
      ),
    );
  }
}

class _SoldOutPill extends StatelessWidget {
  const _SoldOutPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodySmall.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.text(context),
        ),
      ),
    );
  }
}

/// `textVariant` (Size "30x30cm", IMG_4509): pill chips.
class TextVariantOptions extends ConsumerWidget {
  const TextVariantOptions({super.key, required this.productId, required this.group});

  final String productId;
  final OptionGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selected = _watchSelected(ref, productId, group.id);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final value in group.values)
          Builder(builder: (context) {
            final available = ProductConfiguration.isValueAvailable(value);
            final delta = priceDeltaLabel(value.priceDelta);
            final label = [
              value.label.of(context),
              if (delta != null) delta,
              if (!available) l10n.outOfStock,
            ].join(' · ');
            return Semantics(
              key: ValueKey('option-${group.id}-${value.id}'),
              enabled: available,
              child: Opacity(
                opacity: available ? 1 : 0.5,
                child: CategoryChip(
                  label: label,
                  selected: value.id == selected,
                  onTap: available ? () => _select(ref, productId, group.id, value.id) : null,
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// `colorSwatch` (Text Color / Color, IMG_4507, IMG_4509): 44 px circles in
/// a grey pill, each in a 48 dp tap target; the selected one gets a ring in
/// the text colour.
class ColorSwatchOptions extends ConsumerWidget {
  const ColorSwatchOptions({super.key, required this.productId, required this.group});

  final String productId;
  final OptionGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = _watchSelected(ref, productId, group.id);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.field(context),
          borderRadius: BorderRadius.circular(AppRadius.xl + AppSpacing.xs),
        ),
        // 4 px between the 48 dp targets = 8 px between the 44 px circles.
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final value in group.values)
              _Swatch(
                key: ValueKey('option-${group.id}-${value.id}'),
                value: value,
                selected: value.id == selected,
                onTap: () => _select(ref, productId, group.id, value.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({super.key, required this.value, required this.selected, required this.onTap});

  final OptionValue value;
  final bool selected;
  final VoidCallback onTap;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final available = ProductConfiguration.isValueAvailable(value);
    final color = parseHexColor(value.hex) ?? AppColors.line(context);
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? AppColors.white : AppColors.black;
    return Semantics(
      button: true,
      selected: selected,
      enabled: available,
      label: _valueSemantics(context, value, available),
      excludeSemantics: true,
      onTap: available ? onTap : null,
      child: InkResponse(
        onTap: available ? onTap : null,
        radius: size / 2 + AppSpacing.xs,
        child: SizedBox.square(
          dimension: AppSpacing.minTapTarget,
          child: Center(
            child: Container(
              width: size,
              height: size,
              padding: EdgeInsets.all(selected ? 3 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected ? Border.all(color: AppColors.text(context), width: 2.5) : null,
              ),
              child: Opacity(
                opacity: available ? 1 : 0.4,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    // Keeps white / near-background swatches visible.
                    border: Border.all(color: AppColors.line(context)),
                  ),
                  child: available ? null : Icon(Icons.close_rounded, size: 20, color: onColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
