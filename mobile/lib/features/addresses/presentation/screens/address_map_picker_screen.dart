import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../providers/address_map_providers.dart';

/// Opens the full-screen pin picker; resolves to the chosen position, null
/// when the customer goes back.
Future<GeoPin?> showAddressMapPicker(BuildContext context, {GeoPin? initial}) => Navigator.of(context).push<GeoPin>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddressMapPickerScreen(initial: initial ?? defaultMapCenter),
      ),
    );

/// Full-screen map with a fixed centre pin (SRS §5.20, Phase 9): the customer
/// moves the map under the pin and taps "Use this location".
class AddressMapPickerScreen extends ConsumerStatefulWidget {
  const AddressMapPickerScreen({super.key, required this.initial});

  final GeoPin initial;

  @override
  ConsumerState<AddressMapPickerScreen> createState() => _AddressMapPickerScreenState();
}

class _AddressMapPickerScreenState extends ConsumerState<AddressMapPickerScreen> {
  late GeoPin _center = widget.initial;

  static const double _pinSize = 48;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final buildMap = ref.watch(addressMapBuilderProvider);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.addressMapTitle, showBack: true),
      body: Stack(
        children: [
          Positioned.fill(
            child: buildMap(context, initial: widget.initial, onCenterChanged: (c) => _center = c),
          ),
          // The pin's tip marks the map centre.
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: _pinSize),
                child: Icon(
                  Icons.location_on_rounded,
                  key: const ValueKey('map-centre-pin'),
                  size: _pinSize,
                  color: AppColors.gold(context),
                  shadows: [Shadow(blurRadius: 6, color: AppColors.black.withValues(alpha: 0.33), offset: const Offset(0, 2))],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: AppSpacing.sm,
            start: AppSpacing.screenHorizontal,
            end: AppSpacing.screenHorizontal,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.line(context)),
                  boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
                ),
                child: Text(
                  l10n.addressMapHelp,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: AppColors.text(context)),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
            AppSpacing.screenHorizontal,
            AppSpacing.md,
          ),
          child: PrimaryButton(
            key: const ValueKey('map-use-location'),
            label: l10n.addressUseThisLocation,
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(_center),
          ),
        ),
      ),
    );
  }
}
