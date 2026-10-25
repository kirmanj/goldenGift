import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';

/// Shared bits of the Phase 7 screens (My Wallet, Invite & Earn, Promo Codes,
/// cart promo / credits rows).

/// Success green for small text: darkened on light surfaces (brand success
/// `#2E9E5B` is only ≈3.4:1 on white), lifted on dark ones — ≥ 4.5:1 both ways.
Color successTextColor(BuildContext context) => AppColors.isDark(context)
    ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.15), AppColors.success)
    : Color.alphaBlend(AppColors.black.withValues(alpha: 0.25), AppColors.success);

/// "+5,000 IQD" / "−5,000 IQD" (true minus sign) / "0 IQD".
String signedAmount(int amount) {
  if (amount > 0) return '+${CurrencyFormatter.format(amount)}';
  if (amount < 0) return '−${CurrencyFormatter.format(-amount)}';
  return CurrencyFormatter.format(0);
}

/// "−5,000 IQD" for a deduction (discount, credits used).
String deductionAmount(int amount) => '−${CurrencyFormatter.format(amount)}';

/// A money amount that always reads left-to-right, so the sign stays in front
/// of the digits in Arabic / Kurdish layouts.
class AmountText extends StatelessWidget {
  const AmountText(this.text, {super.key, required this.style, this.textAlign});
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(text, style: style, textAlign: textAlign),
      );
}

/// Back from a screen that may have been opened by a deep link (nothing to pop).
void popOrGoProfile(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.go(AppRoutes.mainTab(2));
  }
}

/// Gold gradient header of My Wallet / Invite & Earn (SRS §2.3 `primaryDark`
/// gradient, IMG_4489 / IMG_4493): a faint icon pattern, circular back
/// button, centred title, optional content on the gold ([onGold]) and an
/// optional [overlapCard] that straddles the bottom edge (Wallet balance).
/// Everything on the gold is dark ([AppColors.textOnPrimary]).
class GoldPatternHeader extends StatelessWidget {
  const GoldPatternHeader({
    super.key,
    required this.title,
    required this.patternIcons,
    this.onGold = const [],
    this.overlapCard,
  });

  final String title;
  final List<IconData> patternIcons;
  final List<Widget> onGold;
  final Widget? overlapCard;

  /// How much of [overlapCard] hangs below the gold.
  static const double overlapBelow = 64;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl));
    final background = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          colors: AppColors.headerGradient.colors,
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: _IconPatternPainter(
                icons: patternIcons,
                color: AppColors.textOnPrimary.withValues(alpha: 0.07),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Stack(
        children: [
          Positioned.fill(bottom: overlapCard == null ? 0 : overlapBelow, child: background),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SafeArea(
                bottom: false,
                child: SizedBox(
                  height: GGAppBar.height,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: NavigationToolbar(
                      leading: GGCircleButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        iconSize: 18,
                        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                        onPressed: () => popOrGoProfile(context),
                      ),
                      middle: Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.heading2.copyWith(color: AppColors.textOnPrimary),
                        ),
                      ),
                      middleSpacing: AppSpacing.sm,
                    ),
                  ),
                ),
              ),
              ...onGold,
              if (overlapCard != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenHorizontal,
                    AppSpacing.sm,
                    AppSpacing.screenHorizontal,
                    0,
                  ),
                  child: overlapCard,
                )
              else
                const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ],
      ),
    );
  }
}

/// Scatters [icons] over the header at low alpha (fixed seed: stable layout).
class _IconPatternPainter extends CustomPainter {
  _IconPatternPainter({required this.icons, required this.color});
  final List<IconData> icons;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (icons.isEmpty || size.isEmpty) return;
    final random = math.Random(7);
    const cell = 64.0;
    var i = 0;
    for (var y = 8.0; y < size.height; y += cell) {
      for (var x = 8.0; x < size.width; x += cell) {
        final icon = icons[i++ % icons.length];
        final glyph = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: 18 + random.nextDouble() * 12,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final dx = x + random.nextDouble() * (cell - glyph.width);
        final dy = y + random.nextDouble() * (cell - glyph.height);
        canvas
          ..save()
          ..translate(dx + glyph.width / 2, dy + glyph.height / 2)
          ..rotate((random.nextDouble() - 0.5) * 0.6);
        glyph.paint(canvas, Offset(-glyph.width / 2, -glyph.height / 2));
        canvas.restore();
        glyph.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_IconPatternPainter old) => old.color != color || old.icons != icons;
}

/// Small rounded tag (bucket, referral status, promo notes). [color] is the
/// base hue: the fill is a soft tint of it, the text a contrast-safe shade.
class SoftTag extends StatelessWidget {
  const SoftTag({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final foreground = dark
        ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.3), color)
        : Color.alphaBlend(AppColors.black.withValues(alpha: 0.3), color);
    final background = Color.alphaBlend(color.withValues(alpha: dark ? 0.22 : 0.12), AppColors.card(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
