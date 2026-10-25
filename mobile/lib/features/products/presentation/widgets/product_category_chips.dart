import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../categories/presentation/providers/categories_providers.dart';

/// Horizontal category chips of the products list (SRS §5.8, IMG_4481):
/// "All" + every visible category; the selected chip has the soft-gold fill
/// and gold border. The chip the screen opened with is scrolled into view
/// (IMG_4495). Hidden until categories are available. Coming soon
/// categories carry the "Soon" pill (SRS §5.7a).
class ProductCategoryChips extends ConsumerStatefulWidget {
  const ProductCategoryChips({super.key, required this.selectedId, required this.onSelected});

  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  ConsumerState<ProductCategoryChips> createState() => _ProductCategoryChipsState();
}

class _ProductCategoryChipsState extends ConsumerState<ProductCategoryChips> {
  final _initialChipKey = GlobalKey();
  late final String? _initialId = widget.selectedId;
  bool _revealed = false;

  void _revealInitialChip() {
    if (_revealed || _initialId == null) return;
    _revealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _initialChipKey.currentContext;
      if (chip != null && chip.mounted) {
        Scrollable.ensureVisible(chip, alignment: 0.5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(allCategoriesProvider).valueOrNull;
    if (categories == null || categories.isEmpty) return const SizedBox.shrink();
    _revealInitialChip();
    final l10n = AppLocalizations.of(context)!;
    final selected = widget.selectedId;
    final soon = comingSoonIdsIn(categories);

    // A Row (not a builder) so the initial chip exists to scroll to; the
    // catalogue has ~50 lightweight chips.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: SizedBox(
        height: CategoryChip.height,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
          child: Row(
            children: [
              CategoryChip(
                label: l10n.all,
                selected: selected == null,
                onTap: () => widget.onSelected(null),
              ),
              for (final category in categories)
                Padding(
                  key: category.id == _initialId ? _initialChipKey : null,
                  padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
                  child: CategoryChip(
                    label: category.title.of(context),
                    imageUrl: category.iconUrl,
                    comingSoon: soon.contains(category.id),
                    selected: selected == category.id,
                    onTap: () => widget.onSelected(category.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
