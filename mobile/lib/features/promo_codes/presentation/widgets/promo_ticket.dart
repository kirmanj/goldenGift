import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/promo_code_model.dart';
import '../../../wallet/presentation/widgets/wallet_ui.dart';

/// "10% Off" / "5,000 IQD Off".
String promoValueLabel(AppLocalizations l10n, PromoCodeModel promo) => switch (promo.type) {
      PromoType.percent => l10n.promoPercentOff(promo.value),
      PromoType.fixed => l10n.promoAmountOff(CurrencyFormatter.format(promo.value)),
    };

/// One coupon ticket (SRS §5.23, IMG_4491): green vertical ribbon with the
/// value, bold code + copy, dashed divider, description, notes (min order,
/// max discount, first order only), "Expires on: dd/mm/yyyy" in green and
/// a Use button (or "Applied" when it is the cart's code).
class PromoTicket extends StatelessWidget {
  const PromoTicket({
    super.key,
    required this.promo,
    required this.applied,
    required this.onCopy,
    required this.onUse,
  });

  final PromoCodeModel promo;
  final bool applied;
  final VoidCallback onCopy;
  final VoidCallback onUse;

  static const double ribbonWidth = 56;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final description = promo.description.of(context);
    final title = promo.title.of(context);
    final body = description.isNotEmpty ? description : title;
    final notes = <String>[
      if (promo.minOrder != null && promo.minOrder! > 0) l10n.promoMinOrder(CurrencyFormatter.format(promo.minOrder!)),
      if (promo.type == PromoType.percent && promo.maxDiscount != null && promo.maxDiscount! > 0)
        l10n.promoMaxDiscount(CurrencyFormatter.format(promo.maxDiscount!)),
      if (promo.firstOrderOnly) l10n.promoFirstOrderOnly,
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line(context)),
        boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          children: [
            PositionedDirectional(
              top: 0,
              bottom: 0,
              start: 0,
              width: ribbonWidth,
              child: _Ribbon(label: promoValueLabel(l10n, promo)),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                ribbonWidth + AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          promo.code,
                          style: AppTextStyles.heading3.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: AppColors.text(context),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.promoCopyCode,
                        onPressed: onCopy,
                        icon: Icon(Icons.copy_rounded, color: AppColors.text(context)),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm + AppSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DashedLine(color: AppColors.line(context)),
                        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                        if (body.isNotEmpty) Text(body, style: AppTextStyles.bodyMedium.copyWith(color: muted)),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.xs + AppSpacing.xxs,
                            runSpacing: AppSpacing.xs + AppSpacing.xxs,
                            children: [
                              for (final note in notes) SoftTag(label: note, color: AppColors.primaryDark),
                            ],
                          ),
                        ],
                        if (promo.expiresAt != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            l10n.expiresOn(AppDates.display(promo.expiresAt!)),
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: successTextColor(context),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: applied
                              ? SoftTag(
                                  key: ValueKey('promo-applied-${promo.code}'),
                                  icon: Icons.check_rounded,
                                  label: l10n.promoAppliedLabel,
                                  color: AppColors.success,
                                )
                              : PrimaryButton(
                                  key: ValueKey('promo-use-${promo.code}'),
                                  label: l10n.promoUse,
                                  expand: false,
                                  height: AppSpacing.minTapTarget,
                                  onPressed: onUse,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green strip with the value written bottom-to-top and three "punched"
/// notches on its outer edge (IMG_4491).
class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final notch = AppColors.bg(context);
    return ColoredBox(
      // Slightly deepened so the white label keeps ≥ 3:1 (large bold text).
      color: Color.alphaBlend(AppColors.black.withValues(alpha: 0.15), AppColors.success),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          PositionedDirectional(
            start: -7,
            top: 0,
            bottom: 0,
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(width: 14, height: 14, decoration: BoxDecoration(color: notch, shape: BoxShape.circle)),
                ],
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.heading3.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(
          size: const Size(double.infinity, 1),
          painter: _DashPainter(color),
        ),
      );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const dash = 6.0;
    const gap = 4.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0), Offset((x + dash).clamp(0, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
