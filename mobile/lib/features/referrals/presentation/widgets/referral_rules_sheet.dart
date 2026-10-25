import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/app_settings_model.dart';

/// "Learn more about referrals" (SRS §5.19): the rules with the amounts from
/// `app_settings/referral`; the monthly cap and credit expiry only when set.
Future<void> showReferralRulesSheet(BuildContext context, ReferralSettings settings) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => ReferralRulesSheet(settings: settings),
    );

class ReferralRulesSheet extends StatelessWidget {
  const ReferralRulesSheet({super.key, required this.settings});
  final ReferralSettings settings;

  /// Rule lines, in reading order.
  static List<(IconData, String)> rules(AppLocalizations l10n, ReferralSettings s) => [
        if (s.joinBonus > 0)
          (Icons.person_add_alt_1_rounded, l10n.referralRuleJoin(CurrencyFormatter.format(s.joinBonus))),
        if (s.orderBonus > 0)
          (Icons.local_shipping_rounded, l10n.referralRuleOrder(CurrencyFormatter.format(s.orderBonus))),
        if (s.maxReferralsPerMonth > 0)
          (Icons.calendar_month_rounded, l10n.referralRuleMonthlyCap(s.maxReferralsPerMonth)),
        if (s.creditsExpiryDays > 0) (Icons.hourglass_bottom_rounded, l10n.creditsExpiryNote(s.creditsExpiryDays)),
        (Icons.account_balance_wallet_rounded, l10n.referralRuleSpend),
        (Icons.shield_outlined, l10n.referralRuleFairUse),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          0,
          AppSpacing.screenHorizontal,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child:
                  Text(l10n.referralRulesTitle, style: AppTextStyles.heading2.copyWith(color: AppColors.text(context))),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (icon, text) in rules(l10n, settings))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
                        child: Icon(icon, size: 18, color: AppColors.gold(context)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs + AppSpacing.xxs),
                        child: Text(text, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text(context))),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(label: l10n.ok, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
