import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';

/// Product Details image carousel (SRS §5.9 item 2, IMG_4494 / IMG_4508):
/// rounded soft-grey card with swipeable images, wishlist heart (top-end),
/// "Available only in: …" chip and ★ Featured badge (top-start), then a row
/// with the discount badge (start) and gold page dots (centre).
class ProductImageCarousel extends ConsumerStatefulWidget {
  const ProductImageCarousel({super.key, required this.product});

  final ProductModel product;

  static const double aspectRatio = 4 / 3;

  @override
  ConsumerState<ProductImageCarousel> createState() => _ProductImageCarouselState();
}

class _ProductImageCarouselState extends ConsumerState<ProductImageCarousel> {
  final _controller = PageController();
  int _index = 0;

  /// Bumped when a heart tap changed nothing (guest / failure) so the
  /// optimistic flip inside [WishlistHeart] is reset to the real state.
  int _heartEpoch = 0;

  /// The customer has named wishlists → a save offers "Save to…".
  bool _hasNamedLists = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleWishlist() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await toggleWishlist(context, ref, widget.product);
    if (result == null && mounted) setState(() => _heartEpoch++);
    // With named lists (SRS §5.15), offer to pick another one.
    if (result == true && mounted && _hasNamedLists) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(l10n.wishlistSavedTo(l10n.wishlistDefaultList)),
          persist: false,
          action: SnackBarAction(label: l10n.wishlistSaveTo, onPressed: () => unawaited(_saveToList())),
        ));
    }
  }

  /// Long-press on the heart: "Save to…" a named list.
  Future<void> _saveToList() async {
    if (mounted) await saveToWishlistList(context, ref, widget.product);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final images = product.images.isEmpty ? const <String?>[null] : product.images;
    final multiple = images.length > 1;
    final title = product.title.of(context);
    final saved = ref.watch(wishlistIdsProvider.select((ids) => ids.contains(product.id)));
    // Only flips when the first named list is created / the last one deleted.
    _hasNamedLists = ref.watch(wishlistListsProvider.select((lists) => (lists.valueOrNull?.length ?? 1) > 1));
    final cityNames = _cityNames(context);
    final discount = product.discountPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: ProductImageCarousel.aspectRatio,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.field(context),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => GGNetworkImage(
                      url: images[i],
                      fit: BoxFit.contain,
                      fallbackColor: AppColors.field(context),
                      semanticLabel: multiple ? '$title (${i + 1}/${images.length})' : title,
                    ),
                  ),
                  if (cityNames != null || product.isFeatured)
                    PositionedDirectional(
                      top: AppSpacing.sm + AppSpacing.xs,
                      start: AppSpacing.sm + AppSpacing.xs,
                      // Keep clear of the heart's 44 px tap target.
                      end: AppSpacing.sm * 2 + GGCircleButton.minTapTarget,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (cityNames != null)
                            _OverlayChip(label: AppLocalizations.of(context)!.availableOnlyIn(cityNames)),
                          if (cityNames != null && product.isFeatured) const SizedBox(height: AppSpacing.sm),
                          if (product.isFeatured) const FeaturedBadge(),
                        ],
                      ),
                    ),
                  PositionedDirectional(
                    top: AppSpacing.xs,
                    end: AppSpacing.xs,
                    child: Semantics(
                      onLongPressHint: AppLocalizations.of(context)!.wishlistSaveTo,
                      child: GestureDetector(
                        key: const ValueKey('heart-save-to'),
                        onLongPress: () => unawaited(_saveToList()),
                        // The heart's tooltip would win the long-press.
                        child: TooltipVisibility(
                          visible: false,
                          child: WishlistHeart(
                            key: ValueKey('heart-$_heartEpoch'),
                            isActive: saved,
                            size: 40,
                            onChanged: (_) => _toggleWishlist(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (multiple || discount > 0) ...[
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          SizedBox(
            height: DiscountBadge.heightFor(MediaQuery.textScalerOf(context), large: true),
            child: Stack(
              children: [
                if (discount > 0)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DiscountBadge(percent: discount, large: true),
                  ),
                if (multiple)
                  Align(
                    alignment: Alignment.center,
                    child: ExcludeSemantics(
                      // Decorative 8 px dots; the images are swipeable.
                      child: AnimatedSmoothIndicator(
                        activeIndex: _index,
                        count: images.length,
                        textDirection: Directionality.of(context),
                        onDotClicked: (i) => _controller.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        ),
                        effect: ExpandingDotsEffect(
                          dotWidth: 8,
                          dotHeight: 8,
                          spacing: AppSpacing.sm - AppSpacing.xxs,
                          expansionFactor: 3,
                          activeDotColor: AppColors.gold(context),
                          dotColor: AppColors.line(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// "Erbil, Duhok" in the current language; null when the product ships
  /// everywhere or the city list hasn't loaded yet (SRS §4.3).
  String? _cityNames(BuildContext context) {
    final ids = widget.product.availableCities;
    if (ids.isEmpty) return null;
    final cities = ref.watch(citiesProvider).valueOrNull;
    if (cities == null) return null;
    final names = [
      for (final id in ids) cities.where((c) => c.id == id).firstOrNull?.name.of(context) ?? id,
    ];
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return names.join(rtl ? '، ' : ', ');
  }
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xs,
        vertical: AppSpacing.xs + AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodySmall.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.white,
        ),
      ),
    );
  }
}
