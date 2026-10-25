import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../l10n/l10n.dart';
import '../../../profile/presentation/widgets/profile_header.dart';

/// Building blocks shared by Checkout, Order Details and the other Phase 6
/// screens (SRS §5.11, §5.12).

/// White / near-black card with an optional section header.
class OrderSection extends StatelessWidget {
  const OrderSection({super.key, this.title, this.icon, this.trailing, required this.child});

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: AppColors.gold(context)),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title!,
                      style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          ],
          child,
        ],
      ),
    );
  }
}

/// "Subtotal ............ 70,000 IQD". [negative] prefixes a minus (discounts,
/// credits); [emphasized] is the bold gold total.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.negative = false,
    this.emphasized = false,
  });

  final String label;
  final int amount;
  final bool negative;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final value = '${negative && amount > 0 ? '−' : ''}${CurrencyFormatter.format(amount)}';
    final labelStyle = emphasized
        ? AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context))
        : AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context));
    final valueStyle = emphasized
        ? AppTextStyles.heading3.copyWith(color: AppColors.goldText(context))
        : AppTextStyles.label.copyWith(color: AppColors.text(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        children: [
          Text(label, style: labelStyle),
          Text(value, textDirection: TextDirection.ltr, style: valueStyle),
        ],
      ),
    );
  }
}

/// Guests see this instead of account-only content (SRS AUTH-5).
class GuestSignInCard extends StatelessWidget {
  const GuestSignInCard({super.key, required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
      children: [
        ProfileMessageCard(
          key: const ValueKey('guest-sign-in-card'),
          icon: icon,
          title: l10n.signInToContinue,
          body: l10n.signInToContinueBody,
          primaryLabel: l10n.signIn,
          onPrimary: () => unawaited(context.push(AppRoutes.signIn)),
          secondaryLabel: l10n.signUp,
          onSecondary: () => unawaited(context.push(AppRoutes.signUp)),
        ),
      ],
    );
  }
}

/// Centres a fixed state (empty / error) but lets it scroll on short screens
/// and with large text.
class CenteredScroll extends StatelessWidget {
  const CenteredScroll({super.key, required this.child, this.bottom = AppSpacing.xl});
  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - bottom)),
            child: Center(child: child),
          ),
        ),
      );
}

/// Error-red for small text: base red on light, lifted on dark (≥ 4.5:1).
Color errorText(BuildContext context) => AppColors.isDark(context)
    ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.35), AppColors.error)
    : AppColors.error;

/// Short floating message (replaces the current one).
void showOrderSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
