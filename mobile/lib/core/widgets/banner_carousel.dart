import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'gg_network_image.dart';

/// Auto-playing banner carousel with a gold dot indicator (SRS §5.4 items
/// 2 and 10; IMG_4476): 16:7 images, rounded lg, auto-play every 5 s.
/// Hidden entirely when [imageUrls] is empty; a single banner neither
/// auto-plays nor shows dots. [onTap] receives the banner index.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({
    super.key,
    required this.imageUrls,
    this.onTap,
    this.autoPlay = true,
    this.autoPlayInterval = const Duration(seconds: 5),
    this.aspectRatio = 16 / 7,
    this.semanticLabels,
  });

  final List<String> imageUrls;
  final ValueChanged<int>? onTap;
  final bool autoPlay;
  final Duration autoPlayInterval;
  final double aspectRatio;

  /// Optional per-banner accessibility labels (banner titles); otherwise a
  /// tappable banner is announced as "Offer 1 of 3".
  final List<String>? semanticLabels;

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _controller = CarouselSliderController();
  int _index = 0;

  @override
  void didUpdateWidget(BannerCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= widget.imageUrls.length) _index = 0;
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    if (urls.isEmpty) return const SizedBox.shrink();
    final multiple = urls.length > 1;
    final labels = widget.semanticLabels;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CarouselSlider.builder(
          carouselController: _controller,
          itemCount: urls.length,
          options: CarouselOptions(
            aspectRatio: widget.aspectRatio,
            viewportFraction: 1,
            enableInfiniteScroll: multiple,
            autoPlay: widget.autoPlay && multiple,
            autoPlayInterval: widget.autoPlayInterval,
            autoPlayCurve: Curves.easeInOutCubic,
            onPageChanged: (i, _) => setState(() => _index = i),
          ),
          itemBuilder: (context, i, _) {
            final label = labels != null && i < labels.length
                ? labels[i]
                : (widget.onTap == null ? null : AppLocalizations.of(context)!.bannerSemanticLabel(i + 1, urls.length));
            return Semantics(
              button: widget.onTap != null,
              label: label,
              onTap: widget.onTap == null ? null : () => widget.onTap!(i),
              excludeSemantics: true,
              child: GestureDetector(
                onTap: widget.onTap == null ? null : () => widget.onTap!(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: GGNetworkImage(url: urls[i], fallbackIcon: Icons.image_outlined),
                ),
              ),
            );
          },
        ),
        if (multiple) ...[
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          // Decorative: the banners themselves are the screen-reader targets
          // (the 8 px dots are too small to be tap targets, SRS §8).
          ExcludeSemantics(
            child: AnimatedSmoothIndicator(
              activeIndex: _index,
              count: urls.length,
              textDirection: Directionality.of(context),
              onDotClicked: (i) => _controller.animateToPage(i),
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
        ],
      ],
    );
  }
}
