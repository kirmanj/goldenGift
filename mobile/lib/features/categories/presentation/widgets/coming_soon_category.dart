import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/category_model.dart';
import '../../../home/presentation/providers/home_providers.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../providers/categories_providers.dart';

/// The coming-soon experience of a category (SRS §5.7a).
///
/// [ComingSoonCategoryPage] is what the products list shows instead of its
/// grid when the category (or its parent) is coming soon: a gold hero with
/// the category's medallion, the message card with the admin's note and the
/// two CTAs, then "Explore other categories" and "Gifts you might love".
/// [ComingSoonInlineCard] is the compact version inside Home ▸ Discover.

const double _h = AppSpacing.screenHorizontal;

/// How far the message card rides up over the hero's bottom edge.
const double _cardOverlap = AppSpacing.xl;

class ComingSoonCategoryPage extends ConsumerWidget {
  const ComingSoonCategoryPage({
    super.key,
    required this.info,
    required this.onBack,
    required this.onCategorySelected,
  });

  final ComingSoonCategory info;

  /// App bar back (the products list decides: previous list, pop or Home).
  final VoidCallback onBack;

  /// A tile of "Explore other categories".
  final ValueChanged<CategoryModel> onCategorySelected;

  /// At most this many tiles in "Explore other categories".
  static const otherCategoriesLimit = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allCategoriesProvider).valueOrNull ?? const <CategoryModel>[];
    final others = availableCategoriesIn(all)
        .where((c) => c.id != info.category.id)
        .take(otherCategoriesLimit)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        showBack: true,
        onBack: onBack,
        onCartTap: () => context.go(AppRoutes.mainTab(1)),
      ),
      body: CustomScrollView(
        key: ValueKey('coming-soon-${info.category.id}'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(_h, AppSpacing.sm, _h, 0),
            sliver: SliverLayoutBuilder(builder: (context, constraints) {
              // Small phones: the card spans the hero and keeps a tighter
              // padding, so the CTAs keep their full labels.
              final narrow = constraints.crossAxisExtent < 320;
              return SliverToBoxAdapter(
                child: _EntranceFade(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ComingSoonHero(info: info, bottomInset: _cardOverlap),
                      // Rides up over the hero; the space it leaves below is
                      // the gap to the next section.
                      Transform.translate(
                        offset: const Offset(0, -_cardOverlap),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: narrow ? 0 : AppSpacing.sm + AppSpacing.xs),
                          child: _MessageCard(
                            info: info,
                            narrow: narrow,
                            secondaryLabel: AppLocalizations.of(context)!.comingSoonBackHome,
                            secondaryIcon: Icons.home_outlined,
                            onSecondary: () => context.go(AppRoutes.mainTab(0)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          if (others.isNotEmpty)
            SliverToBoxAdapter(child: _OtherCategoriesSection(categories: others, onTap: onCategorySelected)),
          const SliverToBoxAdapter(child: _GiftsSection()),
          SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl + MediaQuery.paddingOf(context).bottom)),
        ],
      ),
    );
  }
}

/// Discover's compact coming-soon card (SRS §5.4 item 12): the hero without
/// motion, the message and note, "Explore all categories" and "Show all
/// gifts" (back to the All chip).
class ComingSoonInlineCard extends StatelessWidget {
  const ComingSoonInlineCard({super.key, required this.info, required this.onShowAllGifts});

  final ComingSoonCategory info;
  final VoidCallback onShowAllGifts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const radius = BorderRadius.all(Radius.circular(AppRadius.xl));
    return DecoratedBox(
      key: ValueKey('coming-soon-inline-${info.category.id}'),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: radius,
        border: Border.all(color: AppColors.line(context)),
        boxShadow: AppElevation.soft,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ComingSoonHero(info: info, compact: true),
            _MessageBody(
              info: info,
              padding: const EdgeInsets.all(AppSpacing.lg),
              secondaryLabel: l10n.comingSoonShowAllGifts,
              secondaryIcon: Icons.card_giftcard_rounded,
              onSecondary: onShowAllGifts,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero ────────────────────────────────────────────────────────────────────

/// The gold hero: header gradient with a soft glow, halo rings and twinkling
/// sparkles, the floating medallion, the "Coming soon" eyebrow, the category
/// name and the tagline. Everything on the gold is dark
/// ([AppColors.textOnPrimary]) except the eyebrow, which is gold on a dark pill.
///
/// Moves (a 6 s loop: float, light sweep, twinkle) unless [compact] or the
/// system asks for reduced motion (`MediaQuery.disableAnimations`).
class ComingSoonHero extends StatefulWidget {
  const ComingSoonHero({super.key, required this.info, this.compact = false, this.bottomInset = 0});

  final ComingSoonCategory info;

  /// Smaller medallion and title, no rounded corners of its own, no motion.
  final bool compact;

  /// Extra space at the bottom for a card that overlaps the hero.
  final double bottomInset;

  /// Loop length of the float / sweep / twinkle.
  static const loop = Duration(seconds: 6);

  @override
  State<ComingSoonHero> createState() => _ComingSoonHeroState();
}

class _ComingSoonHeroState extends State<ComingSoonHero> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: ComingSoonHero.loop);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = widget.compact || MediaQuery.disableAnimationsOf(context);
    if (still) {
      _loop
        ..stop()
        ..value = 0;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final compact = widget.compact;
    final category = widget.info.category;
    final name = category.title.of(context);
    final direction = Directionality.of(context);
    const topPad = AppSpacing.lg;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final medallion = compact ? 84.0 : math.min(124.0, width * 0.38);
      final radius = compact ? BorderRadius.zero : BorderRadius.circular(AppRadius.xl);

      final content = Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          topPad,
          AppSpacing.lg,
          (compact ? AppSpacing.lg : AppSpacing.xl) + widget.bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Medallion(size: medallion, iconUrl: category.iconUrl, loop: _loop),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
            const _Eyebrow(),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              header: true,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: (compact ? AppTextStyles.heading2 : AppTextStyles.heading1)
                    .copyWith(color: AppColors.textOnPrimary, height: 1.2),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.comingSoonTagline,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textOnPrimary,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ],
        ),
      );

      return RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: AppColors.headerGradient.colors,
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            boxShadow: compact ? null : AppElevation.card,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: CustomPaint(
              painter: _HeroBackdropPainter(
                loop: _loop,
                medallionCenterY: topPad + medallion / 2,
                medallion: medallion,
                direction: direction,
              ),
              child: content,
            ),
          ),
        ),
      );
    });
  }
}

/// "✦ COMING SOON": gold on a dark pill (no letter spacing in Arabic script).
class _Eyebrow extends StatelessWidget {
  const _Eyebrow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final latin = Localizations.localeOf(context).languageCode == 'en';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.textOnPrimary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppElevation.soft,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.accent),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Flexible(
              child: Text(
                latin ? l10n.comingSoon.toUpperCase() : l10n.comingSoon,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                  letterSpacing: latin ? 1.6 : 0,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glossy medallion: gold-shimmer rim, a pearl (light) / onyx (dark) disc with
/// the category icon — or a metallic gift emblem — a top gloss, a light sweep
/// every 3 s and a gentle float.
class _Medallion extends StatelessWidget {
  const _Medallion({required this.size, required this.iconUrl, required this.loop});

  final double size;
  final String? iconUrl;
  final Animation<double> loop;

  /// Lift in logical pixels at the top of the float.
  static const double floatHeight = 5;

  static double liftOf(double t) => math.sin(2 * math.pi * t);

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final hasIcon = iconUrl != null && iconUrl!.isNotEmpty;
    final Widget emblem = hasIcon
        ? GGNetworkImage(
            url: iconUrl,
            fit: BoxFit.contain,
            fallbackIcon: Icons.redeem_rounded,
            fallbackColor: Colors.transparent,
          )
        : ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: AppColors.goldShimmer.createShader,
            child: Icon(Icons.redeem_rounded, size: size * 0.42, color: AppColors.white),
          );

    final face = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.055),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.goldShimmer,
        boxShadow: [
          BoxShadow(
            color: dark ? AppColors.black.withValues(alpha: 0.4) : AppColors.primaryDark.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          // A thin bright halo just outside the rim.
          BoxShadow(color: AppColors.white.withValues(alpha: 0.35), spreadRadius: 2),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.45),
            radius: 0.95,
            colors: dark
                ? const [AppColors.darkSurfaceSecondary, AppColors.darkSurface]
                : const [AppColors.white, AppColors.primarySoft],
          ),
          border: Border.all(
            color: dark ? AppColors.accent.withValues(alpha: 0.3) : AppColors.white.withValues(alpha: 0.7),
          ),
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.all(size * (hasIcon ? 0.17 : 0.1)),
                child: Center(child: emblem),
              ),
              // Top gloss.
              Align(
                alignment: Alignment.topCenter,
                child: FractionallySizedBox(
                  widthFactor: 0.82,
                  heightFactor: 0.46,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.pill)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.white.withValues(alpha: dark ? 0.10 : 0.55),
                          AppColors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              CustomPaint(painter: _SweepPainter(loop: loop, alpha: dark ? 0.22 : 0.5)),
            ],
          ),
        ),
      ),
    );

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, -floatHeight * liftOf(loop.value)),
          child: child,
        ),
        child: face,
      ),
    );
  }
}

/// A soft diagonal band of light that crosses the disc twice per loop.
class _SweepPainter extends CustomPainter {
  _SweepPainter({required this.loop, required this.alpha}) : super(repaint: loop);

  final Animation<double> loop;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final p = (loop.value * 2) % 1;
    const active = 0.42;
    if (p > active || loop.value == 0) return;
    final x = (-0.6 + 2.2 * (p / active)) * size.width;
    final band = size.width * 0.34;
    canvas
      ..save()
      ..translate(x, size.height / 2)
      ..rotate(-0.42);
    final rect = Rect.fromLTWH(-band / 2, -size.height, band, size.height * 2);
    final paint = Paint()
      ..shader = LinearGradient(colors: [
        AppColors.white.withValues(alpha: 0),
        AppColors.white.withValues(alpha: alpha),
        AppColors.white.withValues(alpha: 0),
      ]).createShader(rect);
    canvas
      ..drawRect(rect, paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.alpha != alpha || old.loop != loop;
}

/// Glow, halo rings, twinkling sparkles and the medallion's ground shadow.
class _HeroBackdropPainter extends CustomPainter {
  _HeroBackdropPainter({
    required this.loop,
    required this.medallionCenterY,
    required this.medallion,
    required this.direction,
  }) : super(repaint: loop);

  final Animation<double> loop;
  final double medallionCenterY;
  final double medallion;
  final TextDirection direction;

  /// (x, y) as fractions of the hero, size in px, twinkle phase. Kept off the
  /// centre column where the text is.
  static const _sparkles = <(double, double, double, double)>[
    (0.08, 0.10, 7, 0.00),
    (0.20, 0.30, 4, 0.35),
    (0.90, 0.08, 5, 0.60),
    (0.80, 0.24, 8, 0.15),
    (0.94, 0.42, 3.5, 0.80),
    (0.06, 0.50, 4.5, 0.50),
    (0.14, 0.70, 6, 0.25),
    (0.88, 0.64, 5.5, 0.90),
    (0.04, 0.86, 3, 0.70),
    (0.95, 0.88, 6.5, 0.40),
    (0.30, 0.06, 3, 0.85),
    (0.70, 0.05, 3.5, 0.10),
    (0.26, 0.92, 3.5, 0.55),
    (0.74, 0.93, 4, 0.30),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = loop.value;
    final rtl = direction == TextDirection.rtl;
    final focus = Offset(size.width / 2, medallionCenterY);

    // Warm glow behind the medallion and a second light from the bottom end.
    final glow = Rect.fromCircle(center: focus, radius: size.width * 0.62);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(colors: [
          AppColors.white.withValues(alpha: 0.42),
          AppColors.white.withValues(alpha: 0),
        ]).createShader(glow),
    );
    final corner = Offset(rtl ? 0 : size.width, size.height);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(colors: [
          AppColors.white.withValues(alpha: 0.16),
          AppColors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: corner, radius: size.width * 0.75)),
    );

    // Halo rings, breathing slightly.
    for (var i = 0; i < 3; i++) {
      final breathe = 1 + 0.025 * math.sin(2 * math.pi * (t + i * 0.15));
      canvas.drawCircle(
        focus,
        medallion / 2 * (1.28 + i * 0.34) * breathe,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.white.withValues(alpha: 0.36 - i * 0.1),
      );
    }

    // Ground shadow: smaller and fainter while the medallion floats up.
    final lift = (_Medallion.liftOf(t) + 1) / 2;
    final shadowWidth = medallion * 0.62 * (1 - 0.14 * lift);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(focus.dx, focus.dy + medallion / 2 + AppSpacing.sm + AppSpacing.xxs),
        width: shadowWidth,
        height: 9,
      ),
      Paint()
        ..color = AppColors.black.withValues(alpha: 0.16 * (1 - 0.35 * lift))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Four-point sparkles.
    for (final (fx, fy, r, phase) in _sparkles) {
      final twinkle = 0.5 + 0.5 * math.sin(2 * math.pi * (t * 2 + phase));
      final alpha = 0.32 + 0.5 * twinkle;
      final c = Offset((rtl ? 1 - fx : fx) * size.width, fy * size.height);
      final radius = r * (0.85 + 0.15 * twinkle);
      final path = Path()
        ..moveTo(c.dx, c.dy - radius)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + radius, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + radius)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - radius, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - radius)
        ..close();
      canvas.drawPath(path, Paint()..color = AppColors.white.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(_HeroBackdropPainter old) =>
      old.medallionCenterY != medallionCenterY ||
      old.medallion != medallion ||
      old.direction != direction ||
      old.loop != loop;
}

// ─── Message card ────────────────────────────────────────────────────────────

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.info,
    required this.narrow,
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.onSecondary,
  });

  final ComingSoonCategory info;
  final bool narrow;
  final String secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.isDark(context) ? AppColors.line(context) : AppColors.card(context)),
        boxShadow: AppElevation.card,
      ),
      child: _MessageBody(
        info: info,
        padding: EdgeInsets.all(narrow ? AppSpacing.md : AppSpacing.lg),
        secondaryLabel: secondaryLabel,
        secondaryIcon: secondaryIcon,
        onSecondary: onSecondary,
      ),
    );
  }
}

/// Ornament, message, optional note, gold CTA + outline CTA.
class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.info,
    required this.padding,
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.onSecondary,
  });

  final ComingSoonCategory info;
  final EdgeInsetsGeometry padding;
  final String secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final note = info.note.of(context).trim();
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Ornament(),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.comingSoonMessage(info.category.title.of(context)),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.text(context), height: 1.6),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _NoteQuote(note: note),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: l10n.comingSoonExploreAll,
            icon: Icons.grid_view_rounded,
            fitLabel: true,
            onPressed: () => context.push(AppRoutes.categories),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          OutlineButton(label: secondaryLabel, icon: secondaryIcon, fitLabel: true, onPressed: onSecondary),
        ],
      ),
    );
  }
}

/// Hairlines fading into a small gold diamond.
class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    Widget line(bool towardsEnd) => SizedBox(
          width: AppSpacing.xl + AppSpacing.sm,
          height: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: towardsEnd
                    ? [gold.withValues(alpha: 0), gold]
                    : [gold, gold.withValues(alpha: 0)],
              ),
            ),
          ),
        );
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          line(true),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.diamond_outlined, size: 14, color: gold),
          const SizedBox(width: AppSpacing.sm),
          line(false),
        ],
      ),
    );
  }
}

/// The admin's note as a refined quote line: “ Arriving before Ramadan ”.
class _NoteQuote extends StatelessWidget {
  const _NoteQuote({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.soft(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(child: Icon(Icons.format_quote_rounded, size: 22, color: AppColors.gold(context))),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                note,
                key: const ValueKey('coming-soon-note'),
                textAlign: TextAlign.center,
                style: AppTextStyles.label.copyWith(color: AppColors.goldText(context), height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sections ────────────────────────────────────────────────────────────────

/// "Explore other categories": available categories only, as tiles.
class _OtherCategoriesSection extends StatelessWidget {
  const _OtherCategoriesSection({required this.categories, required this.onTap});

  final List<CategoryModel> categories;
  final ValueChanged<CategoryModel> onTap;

  static const double tileWidth = 84;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.comingSoonExploreOthers,
          maxLines: 2,
          padding: const EdgeInsets.symmetric(horizontal: _h),
          onViewAll: () => context.push(AppRoutes.categories),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: CategoryTile.heightFor(context, tileWidth),
          child: ListView.separated(
            key: const ValueKey('coming-soon-other-categories'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _h),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
            itemBuilder: (context, i) {
              final category = categories[i];
              return SizedBox(
                width: tileWidth,
                child: CategoryTile(
                  key: ValueKey(category.id),
                  label: category.title.of(context),
                  iconUrl: category.iconUrl,
                  onTap: () => onTap(category),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "Gifts you might love": Home's Popular products (SRS §5.4 item 4) in a
/// row, with wishlist hearts. Hidden when there are none or the list fails.
class _GiftsSection extends ConsumerWidget {
  const _GiftsSection();

  static const double cardWidth = 164;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(popularProductsProvider);
    if (async.hasError && !async.hasValue) return const SizedBox.shrink();
    final products = async.valueOrNull;
    if (products != null && products.isEmpty) return const SizedBox.shrink();
    final saved = ref.watch(wishlistIdsProvider);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: l10n.comingSoonGiftsYouMightLove,
            maxLines: 2,
            padding: const EdgeInsets.symmetric(horizontal: _h),
            onViewAll: products == null ? null : () => context.push(AppRoutes.productsFor(HomeQueries.popular)),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: ProductCard.heightFor(context, cardWidth),
            child: ListView.separated(
              key: const ValueKey('coming-soon-gifts'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _h),
              itemCount: products?.length ?? 3,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.gridGap),
              itemBuilder: (context, i) {
                if (products == null) {
                  return const SizedBox(width: cardWidth, child: SkeletonLoader.box(radius: AppRadius.lg));
                }
                final product = products[i];
                return SizedBox(
                  width: cardWidth,
                  child: ProductCard(
                    key: ValueKey(product.id),
                    product: product,
                    isWishlisted: saved.contains(product.id),
                    onWishlistChanged: (_) => toggleWishlist(context, ref, product),
                    onTap: () => context.push(AppRoutes.product(product.id)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One gentle fade + rise when the page opens (instant with reduced motion).
class _EntranceFade extends StatelessWidget {
  const _EntranceFade({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: still ? Duration.zero : const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * AppSpacing.md), child: child),
      ),
      child: child,
    );
  }
}
