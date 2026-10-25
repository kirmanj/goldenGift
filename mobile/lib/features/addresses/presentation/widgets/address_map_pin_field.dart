import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../providers/address_map_providers.dart';

/// Address form ▸ optional map pin (SRS §5.20): "Pin on map" until a pin is
/// chosen, then "Location pinned" with Change / Remove.
class AddressMapPinField extends StatelessWidget {
  const AddressMapPinField({super.key, required this.pin, required this.onPick, required this.onRemove});

  final GeoPin? pin;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final current = pin;
    if (current == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlineButton(
            key: const ValueKey('address-pin-map'),
            label: l10n.addressPinOnMap,
            icon: Icons.pin_drop_outlined,
            height: 48,
            onPressed: onPick,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.addressPinOnMapHint,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: muted),
          ),
        ],
      );
    }
    final linkStyle = TextButton.styleFrom(
      foregroundColor: AppColors.goldText(context),
      minimumSize: const Size.square(AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
    return Container(
      key: const ValueKey('address-pin-preview'),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.soft(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gold(context).withValues(alpha: 0.6)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: AppSpacing.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_rounded, color: AppColors.gold(context)),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.addressLocationPinned,
                      style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                    ),
                    Text(
                      formatGeoPin(current),
                      textDirection: TextDirection.ltr,
                      style: AppTextStyles.bodySmall.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('address-pin-change'),
                onPressed: onPick,
                style: linkStyle,
                child: Text(l10n.addressChangePin, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(
                key: const ValueKey('address-pin-remove'),
                onPressed: onRemove,
                style: linkStyle,
                child: Text(l10n.remove, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
