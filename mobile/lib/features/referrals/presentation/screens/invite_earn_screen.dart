import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/app_settings_model.dart';
import '../../../../models/referral_model.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../profile/presentation/widgets/profile_header.dart' show ProfileMessageCard;
import '../../../wallet/data/wallet_repository.dart';
import '../../../wallet/presentation/widgets/wallet_ui.dart';
import '../../data/referrals_repository.dart';
import '../providers/referral_providers.dart';
import '../widgets/referral_rules_sheet.dart';

/// Invite & Earn (SRS §5.19, IMG_4489): credits balance on a gold header,
/// successful / pending referral counts, the referral code (copy) and the
/// Invite Friends share, the rules sheet and the list of invited friends.
/// The code is written by `onUserCreate`; until it exists a skeleton shows.
class InviteEarnScreen extends ConsumerWidget {
  const InviteEarnScreen({super.key});

  static const patternIcons = [Icons.card_giftcard_rounded, Icons.auto_awesome_outlined, Icons.redeem_rounded];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final credits = ref.watch(walletProvider).valueOrNull?.credits ?? 0;
    final bottom = MediaQuery.paddingOf(context).bottom + AppSpacing.lg;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: ListView(
        padding: EdgeInsets.only(bottom: bottom),
        children: [
          GoldPatternHeader(
            title: l10n.inviteAndEarn,
            patternIcons: patternIcons,
            onGold: [
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                child: Text(
                  l10n.creditsBalance,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    CurrencyFormatter.format(signedIn ? credits : 0),
                    key: const ValueKey('invite-credits'),
                    style: AppTextStyles.heading1.copyWith(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textOnPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
            child: signedIn
                ? const _InviteBody()
                : ProfileMessageCard(
                    key: const ValueKey('invite-guest-card'),
                    icon: Icons.lock_outline_rounded,
                    title: l10n.signInToContinue,
                    body: l10n.inviteSignInBody,
                    primaryLabel: l10n.signIn,
                    onPrimary: () => context.push(AppRoutes.signIn),
                    secondaryLabel: l10n.signUp,
                    onSecondary: () => context.push(AppRoutes.signUp),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InviteBody extends ConsumerWidget {
  const _InviteBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final stats = ref.watch(referralStatsProvider);
    final settings = ref.watch(referralSettingsProvider).valueOrNull ?? const ReferralSettings();
    final code = ref.watch(currentUserProfileProvider).valueOrNull?.referralCode;
    final referrals = ref.watch(myReferralsProvider).valueOrNull ?? const <ReferralModel>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatCard(
          key: const ValueKey('stat-successful'),
          title: l10n.successfulReferrals,
          hint: l10n.successfulReferralsHint,
          count: stats.successful,
        ),
        const SizedBox(height: AppSpacing.md),
        _StatCard(
          key: const ValueKey('stat-pending'),
          title: l10n.pendingReferrals,
          hint: l10n.pendingReferralsHint,
          count: stats.pending,
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(l10n.inviteFriends, style: AppTextStyles.heading2.copyWith(color: AppColors.text(context))),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.inviteFriendsBody, style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context))),
        const SizedBox(height: AppSpacing.md),
        _CodeBox(code: code, rewardLine: referralRewardLine(l10n, settings)),
        const SizedBox(height: AppSpacing.md),
        Builder(
          builder: (buttonContext) => PrimaryButton(
            key: const ValueKey('invite-share'),
            label: l10n.inviteFriends,
            icon: Icons.redeem_rounded,
            onPressed: code == null ? null : () => shareReferral(buttonContext, ref, code),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton(
            key: const ValueKey('invite-learn-more'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted(context),
              minimumSize: const Size.square(AppSpacing.minTapTarget),
            ),
            onPressed: () => showReferralRulesSheet(context, settings),
            child: Text(
              l10n.learnMoreReferrals,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textMuted(context),
                decoration: TextDecoration.underline,
                decorationColor: AppColors.textMuted(context),
              ),
            ),
          ),
        ),
        if (referrals.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            header: true,
            child: Text(
              l10n.referralInvitesTitle,
              style: AppTextStyles.sectionTitle.copyWith(color: AppColors.text(context)),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final r in referrals)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ReferralRow(referral: r),
            ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({super.key, required this.title, required this.hint, required this.count});
  final String title;
  final String hint;
  final int count;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.line(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
                  const SizedBox(height: AppSpacing.xs),
                  Text(hint, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context))),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              '$count',
              style: AppTextStyles.heading1.copyWith(color: AppColors.goldText(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft-gold "Your referral code" box: spaced gold letters, copy button and
/// who gets what.
class _CodeBox extends ConsumerWidget {
  const _CodeBox({required this.code, required this.rewardLine});
  final String? code;
  final String? rewardLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final gold = AppColors.gold(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md + AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.soft(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.yourReferralCode,
                  style: AppTextStyles.label.copyWith(color: AppColors.textMuted(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (code == null)
                  const SkeletonLoader.line(key: ValueKey('referral-code-skeleton'), width: 170, height: 32)
                else
                  // Codes are Latin letters/digits: always left-to-right.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        code!,
                        key: const ValueKey('referral-code'),
                        style: AppTextStyles.heading1.copyWith(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 6,
                          color: AppColors.goldText(context),
                        ),
                      ),
                    ),
                  ),
                if (rewardLine != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(rewardLine!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context))),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            key: const ValueKey('referral-copy'),
            tooltip: l10n.copyReferralCode,
            onPressed: code == null ? null : () => copyReferralCode(context, ref, code!),
            style: IconButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: AppColors.textOnPrimary,
              disabledBackgroundColor: gold.withValues(alpha: 0.4),
              minimumSize: const Size(52, 52),
            ),
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}

class _ReferralRow extends StatelessWidget {
  const _ReferralRow({required this.referral});
  final ReferralModel referral;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = (referral.referredName ?? '').trim().split(RegExp(r'\s+')).first;
    final (label, color) = switch (referral.status) {
      ReferralStatus.pending => (l10n.referralStatusPending, AppColors.warning),
      ReferralStatus.completed => (l10n.referralStatusCompleted, AppColors.success),
      ReferralStatus.cancelled => (l10n.referralStatusCancelled, AppColors.error),
    };
    final display = name.isEmpty ? l10n.referralAFriend : name;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.line(context)),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.soft(context),
                child: Text(
                  display.characters.first.toUpperCase(),
                  style: AppTextStyles.label.copyWith(color: AppColors.goldText(context)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (referral.createdAt != null)
                        Text(
                          AppDates.display(referral.createdAt!),
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
                        ),
                      SoftTag(label: label, color: color),
                    ],
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
