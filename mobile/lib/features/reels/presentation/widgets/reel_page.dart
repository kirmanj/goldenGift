import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/localized_text.dart';
import '../../../../models/product_model.dart';
import '../../../../models/reel_model.dart';
import '../../../product_details/data/product_repository.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';

/// The product of a reel as a [ProductModel] — enough for the wishlist and
/// sharing, which only need the id, title, image and price.
ProductModel reelProductModel(ReelModel reel) {
  final p = reel.product;
  return ProductModel(
    id: reel.productId,
    title: p?.title ?? LocalizedText.empty,
    storeId: reel.storeId,
    categoryIds: reel.categoryIds,
    images: [if (p?.image != null) p!.image!],
    price: p?.price ?? 0,
    compareAtPrice: p?.compareAtPrice,
    giftFor: reel.giftFor,
  );
}

/// One reel of the feed (SRS §5.27): the video (poster until the first
/// frame), tap to pause / play, caption, Save + Share rail and the product
/// card. Text sits on dark scrims; everything mirrors in RTL.
class ReelPage extends ConsumerWidget {
  const ReelPage({
    super.key,
    required this.reel,
    required this.controller,
    required this.failed,
    required this.paused,
    required this.onTogglePlay,
  });

  final ReelModel reel;

  /// Null while the reel is not prepared (far from the current one).
  final VideoPlayerController? controller;
  final bool failed;

  /// Paused by the customer (shows the play glyph).
  final bool paused;
  final VoidCallback onTogglePlay;

  void _openProduct(BuildContext context, WidgetRef ref) {
    unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.reelProductTap, {
      'reel_id': reel.id,
      'product_id': reel.productId,
    }));
    context.push(AppRoutes.product(reel.productId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // The floating bottom nav overlaps the page (MainShell.extendBody); its
    // height is part of the bottom padding.
    final bottom = MediaQuery.paddingOf(context).bottom;
    final caption = reel.caption.of(context).trim();
    final product = reel.product;
    final saved = ref.watch(wishlistIdsProvider).contains(reel.productId);

    return Stack(
      fit: StackFit.expand,
      children: [
        _ReelVideo(reel: reel, controller: controller, failed: failed),
        Positioned.fill(
          child: Semantics(
            button: true,
            label: paused ? l10n.reelsPlay : l10n.reelsPause,
            onTap: onTogglePlay,
            excludeSemantics: true,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTogglePlay),
          ),
        ),
        if (paused) const Center(child: IgnorePointer(child: _PlayGlyph())),
        // Legibility scrim behind the caption and the product card.
        const PositionedDirectional(
          start: 0,
          end: 0,
          bottom: 0,
          child: IgnorePointer(child: _BottomScrim()),
        ),
        PositionedDirectional(
          start: AppSpacing.screenHorizontal,
          end: AppSpacing.screenHorizontal,
          bottom: bottom + AppSpacing.md,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: caption.isEmpty ? const SizedBox.shrink() : _ReelCaption(text: caption)),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WishlistHeart(
                        isActive: saved,
                        size: 44,
                        onChanged: (_) => toggleWishlist(context, ref, reelProductModel(reel)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      GGCircleButton(
                        icon: Icons.share_outlined,
                        tooltip: l10n.share,
                        onPressed: () {
                          final model = reelProductModel(reel);
                          unawaited(shareProduct(ref, model, model.title.of(context)).catchError((Object _) {}));
                        },
                      ),
                    ],
                  ),
                ],
              ),
              if (product != null) ...[
                const SizedBox(height: AppSpacing.md),
                ReelProductCard(product: product, onTap: () => _openProduct(context, ref)),
              ],
            ],
          ),
        ),
        if (controller != null)
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: bottom,
            child: IgnorePointer(child: _ReelProgress(controller: controller!)),
          ),
      ],
    );
  }
}

/// Poster, then the video (cover-fit) once its first frame is ready; a gold
/// spinner while loading / buffering; a message when it can't be played.
class _ReelVideo extends StatelessWidget {
  const _ReelVideo({required this.reel, required this.controller, required this.failed});

  final ReelModel reel;
  final VideoPlayerController? controller;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final poster = reel.posterUrl ?? reel.product?.image;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: AppColors.black,
          child: poster == null
              ? null
              : GGNetworkImage(url: poster, fit: BoxFit.cover, fallbackColor: AppColors.black),
        ),
        if (failed)
          const _VideoError()
        else if (controller != null)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller!,
            builder: (context, value, _) {
              if (value.hasError) return const _VideoError();
              if (!value.isInitialized) return const _Spinner();
              final size = value.size;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (size.width > 0 && size.height > 0)
                    FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(controller!)),
                    )
                  else
                    Center(child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(controller!))),
                  if (value.isBuffering) const _Spinner(),
                ],
              );
            },
          )
        else
          const _Spinner(),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 32,
        child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.gold(context)),
      ),
    );
  }
}

class _VideoError extends StatelessWidget {
  const _VideoError();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.black.withValues(alpha: 0.55),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, size: 40, color: AppColors.text(context)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppLocalizations.of(context)!.reelsVideoError,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayGlyph extends StatelessWidget {
  const _PlayGlyph();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.black.withValues(alpha: 0.4)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Icon(Icons.play_arrow_rounded, size: 56, color: AppColors.white.withValues(alpha: 0.92)),
      ),
    );
  }
}

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.paddingOf(context).bottom + 300,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.black.withValues(alpha: 0),
              AppColors.black.withValues(alpha: 0.55),
              AppColors.black.withValues(alpha: 0.85),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
      ),
    );
  }
}

/// Two lines; a tap shows the whole caption (and folds it again).
class _ReelCaption extends StatefulWidget {
  const _ReelCaption({required this.text});
  final String text;

  @override
  State<_ReelCaption> createState() => _ReelCaptionState();
}

class _ReelCaptionState extends State<_ReelCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.bodyMedium.copyWith(
      color: AppColors.white,
      shadows: [Shadow(color: AppColors.black.withValues(alpha: 0.6), blurRadius: 6)],
    );
    void toggle() => setState(() => _expanded = !_expanded);
    // One labelled, ≥ 48 dp tap target: the caption is its own label.
    return Semantics(
      button: true,
      label: widget.text,
      excludeSemantics: true,
      onTap: toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: AppSpacing.minTapTarget,
            maxHeight: MediaQuery.sizeOf(context).height * 0.3,
          ),
          child: Align(
            alignment: AlignmentDirectional.bottomStart,
            heightFactor: 1,
            child: SingleChildScrollView(
              physics: _expanded ? null : const NeverScrollableScrollPhysics(),
              child: Text(
                widget.text,
                maxLines: _expanded ? null : 2,
                overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glass product card (SRS §5.27): image, title, price and the gold
/// "Shop now" — a gold arrow on narrow screens. The whole card opens the product.
class ReelProductCard extends StatelessWidget {
  const ReelProductCard({super.key, required this.product, required this.onTap});

  final ReelProduct product;
  final VoidCallback onTap;

  /// Below this card width the "Shop now" label becomes an icon.
  static const double compactWidth = 330;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = product.title.of(context);
    final radius = BorderRadius.circular(AppRadius.lg);
    return Semantics(
      button: true,
      label: '${l10n.reelsViewProduct(title)}, ${CurrencyFormatter.format(product.price)}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.black.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: AppColors.white.withValues(alpha: 0.16)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < compactWidth;
                return Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: SizedBox.square(
                        dimension: 52,
                        child: GGNetworkImage(url: product.image, fallbackColor: AppColors.field(context)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.white),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          PriceText(price: product.price, oldPrice: product.hasDiscount ? product.compareAtPrice : null),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ShopNow(label: l10n.reelsShopNow, compact: compact),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ShopNow extends StatelessWidget {
  const _ShopNow({required this.label, required this.compact});
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final arrow = Directionality.of(context) == TextDirection.rtl
        ? Icons.arrow_back_rounded
        : Icons.arrow_forward_rounded;
    if (compact) {
      return Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.headerGradient),
        child: Icon(arrow, size: 22, color: AppColors.textOnPrimary),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w800, color: AppColors.textOnPrimary),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(arrow, size: 18, color: AppColors.textOnPrimary),
        ],
      ),
    );
  }
}

/// Thin gold line: how far the current reel has played.
class _ReelProgress extends StatelessWidget {
  const _ReelProgress({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final total = value.duration.inMilliseconds;
        final progress = total <= 0 ? 0.0 : (value.position.inMilliseconds / total).clamp(0.0, 1.0);
        return LinearProgressIndicator(
          value: progress,
          minHeight: 2,
          color: AppColors.gold(context),
          backgroundColor: AppColors.white.withValues(alpha: 0.18),
        );
      },
    );
  }
}
