import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'primary_button.dart';

/// Empty list / screen state: illustration, title, subtitle and an optional
/// gold CTA (SRS §4.8, §5.10 IMG_4480 "Your Golden Gift cart is feeling
/// lonely!" + Start Shopping).
///
/// [illustration] defaults to a large soft-gold circle with [icon] until
/// the mascot artwork exists (SRS §12 item 1). The CTA shows when both
/// [ctaLabel] and [onCta] are set. Not scrollable: place it in a bounded
/// area or inside a scroll view.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.illustration,
    this.icon = Icons.card_giftcard_rounded,
    this.ctaLabel,
    this.onCta,
    this.ctaIcon,
  });

  final String title;
  final String? subtitle;
  final Widget? illustration;
  final IconData icon;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final IconData? ctaIcon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            illustration ?? _DefaultIllustration(icon: icon),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
              ),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(label: ctaLabel!, icon: ctaIcon, onPressed: onCta),
            ],
          ],
        ),
      ),
    );
  }
}

class _DefaultIllustration extends StatelessWidget {
  const _DefaultIllustration({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 148,
        height: 148,
        decoration: BoxDecoration(
          color: AppColors.soft(context),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: AppColors.card(context),
              shape: BoxShape.circle,
              boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
            ),
            child: Icon(icon, size: 48, color: AppColors.gold(context)),
          ),
        ),
      ),
    );
  }
}
