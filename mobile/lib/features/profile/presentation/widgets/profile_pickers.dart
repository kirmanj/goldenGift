import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/app_settings_model.dart';

const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
);

/// Camera or gallery for the profile photo (SRS §5.14).
Future<ImageSource?> showAvatarSourceSheet(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.card(context),
    showDragHandle: true,
    shape: _sheetShape,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetOption(
                icon: Icons.photo_camera_outlined,
                label: l10n.takePhoto,
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              _SheetOption(
                icon: Icons.photo_library_outlined,
                label: l10n.chooseFromGallery,
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Active delivery cities (`app_settings/cities`, SRS §4.3) with the
/// current one checked. Resolves to the chosen city, or null when closed.
Future<CityModel?> showCityPickerSheet(BuildContext context, {String? selectedId}) {
  return showModalBottomSheet<CityModel>(
    context: context,
    backgroundColor: AppColors.card(context),
    showDragHandle: true,
    isScrollControlled: true,
    shape: _sheetShape,
    builder: (_) => _CityPickerSheet(selectedId: selectedId),
  );
}

class _CityPickerSheet extends ConsumerWidget {
  const _CityPickerSheet({this.selectedId});
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cities = ref.watch(activeCitiesProvider);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                child: Text(
                  l10n.selectCity,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: cities.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.screenHorizontal),
                  child: SkeletonLoader.list(count: 4),
                ),
                error: (_, __) => SingleChildScrollView(
                  child: ErrorState(
                    onRetry: () {
                      ref.invalidate(citiesProvider);
                      ref.invalidate(activeCitiesProvider);
                    },
                  ),
                ),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          l10n.noResults,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        children: [
                          for (final city in list)
                            _SheetOption(
                              key: ValueKey('city-${city.id}'),
                              icon: Icons.location_city_rounded,
                              label: city.name.of(context),
                              selected: city.id == selectedId,
                              onTap: () => Navigator.of(context).pop(city),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(icon, color: selected ? gold : AppColors.textMuted(context)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.label.copyWith(fontSize: 16, color: AppColors.text(context)),
                  ),
                ),
                if (selected) Icon(Icons.check_rounded, color: gold),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
