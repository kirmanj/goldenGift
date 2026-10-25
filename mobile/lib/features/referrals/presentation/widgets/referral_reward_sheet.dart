import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/app_settings_model.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../providers/referral_providers.dart';

/// Shows the Home referral sheet (SRS §5.4 item 13, IMG_4488).
Future<void> showReferralRewardSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const ReferralRewardSheet(),
    );

/// "Referral rewards" chip, "Invite friends, earn credits", Friend joins /
/// First paid order tiles (a tile is hidden when its bonus is 0), how it
/// works, My Rewards (→ Invite & Earn) / Invite (→ share sheet), Maybe later.
class ReferralRewardSheet extends ConsumerWidget {
  const ReferralRewardSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(referralSettingsProvider).valueOrNull ?? const ReferralSettings();
    final code = ref.watch(currentUserProfileProvider).valueOrNull?.referralCode;
    final friend = CurrencyFormatter.format(s.joinBonus);
    final you = CurrencyFormatter.format(s.orderBonus);
    final watchBody = s.joinBonus > 0 && s.orderBonus > 0
        ? l10n.referralWatchBoth(friend, you)
        : s.orderBonus > 0
            ? l10n.referralWatchYou(you)
            : l10n.referralWatchFriend(friend);
    final gold = AppColors.gold(context);
    final muted = AppColors.textMuted(context);

    void openRewards() {
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      unawaited(router.push(AppRoutes.inviteAndEarn));
    }

    final tiles = [
      if (s.joinBonus > 0) _StatTile(amount: friend, label: l10n.referralFriendJoins),
      if (s.orderBonus > 0) _StatTile(amount: you, label: l10n.referralFirstPaidOrder),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, 0, AppSpacing.screenHorizontal, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: gold.withValues(alpha: 0.35)),
                gradient: LinearGradient(
                  colors: [AppColors.soft(context), AppColors.card(context)],
                  begin: AlignmentDirectional.topEnd,
                  end: AlignmentDirectional.bottomStart,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm + AppSpacing.xs, vertical: AppSpacing.xs + AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: gold.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.redeem_rounded, size: 16, color: gold),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Flexible(
                            child: Text(
                              l10n.referralRewardsChip,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.goldText(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: gold,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
                          ),
                          child: const Icon(Icons.group_rounded, size: 28, color: AppColors.textOnPrimary),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            l10n.referralSheetTitle,
                            style: AppTextStyles.heading2.copyWith(color: AppColors.text(context)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                  Text(l10n.referralSheetBody, style: AppTextStyles.bodyMedium.copyWith(color: muted)),
                  if (tiles.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < tiles.length; i++) ...[
                          if (i > 0) const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                          Expanded(child: tiles[i]),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.line(context)),
                    ),
                    child: Column(
                      children: [
                        _HowRow(
                          icon: Icons.link_rounded,
                          title: l10n.referralShareLinkTitle,
                          body: l10n.referralShareLinkBody,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _HowRow(
                          icon: Icons.auto_awesome_rounded,
                          title: l10n.referralWatchCreditsTitle,
                          body: watchBody,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final rewards = OutlineButton(
                  key: const ValueKey('referral-sheet-rewards'),
                  label: l10n.referralMyRewards,
                  onPressed: openRewards,
                );
                final invite = Builder(
                  builder: (buttonContext) => PrimaryButton(
                    key: const ValueKey('referral-sheet-invite'),
                    label: l10n.referralInvite,
                    icon: Icons.redeem_rounded,
                    onPressed: code == null ? openRewards : () => shareReferral(buttonContext, ref, code),
                  ),
                );
                // Side by side on phones; stacked when narrow or with large text.
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                if (constraints.maxWidth < 300 * textScale) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [invite, const SizedBox(height: AppSpacing.sm), rewards],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: rewards),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(child: invite),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: TextButton(
                key: const ValueKey('referral-sheet-later'),
                style: TextButton.styleFrom(foregroundColor: muted, minimumSize: const Size.square(AppSpacing.minTapTarget)),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.referralMaybeLater, style: AppTextStyles.bodyLarge.copyWith(color: muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.amount, required this.label});
  final String amount;
  final String label;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.line(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                amount,
                maxLines: 1,
                style: AppTextStyles.heading2.copyWith(color: AppColors.goldText(context)),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
          ],
        ),
      ),
    );
  }
}

class _HowRow extends StatelessWidget {
  const _HowRow({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: AppColors.gold(context)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
                const SizedBox(height: AppSpacing.xxs),
                Text(body, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps Home: shows the referral sheet once per install when it is due
/// ([referralSheetDueProvider]) and explains a referral link opened while
/// signed in ([referralLinkNoticeProvider]). Never throws when providers
/// are unavailable (e.g. no Firebase in tests).
class ReferralSheetGate extends ConsumerStatefulWidget {
  const ReferralSheetGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReferralSheetGate> createState() => _ReferralSheetGateState();
}

class _ReferralSheetGateState extends ConsumerState<ReferralSheetGate> {
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(referralSheetDueProvider, (_, due) {
      if (due) _scheduleSheet();
    }, fireImmediately: true);
    ref.listenManual<bool>(referralLinkNoticeProvider, (_, show) {
      if (show) _scheduleNotice();
    }, fireImmediately: true);
  }

  void _scheduleSheet() {
    if (_handled) return;
    _handled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final tracker = ref.read(referralSheetTrackerProvider);
      if (tracker == null || tracker.shown) return;
      await tracker.markShown();
      if (!mounted) return;
      await showReferralRewardSheet(context);
    });
  }

  void _scheduleNotice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(referralLinkNoticeProvider)) return;
      ref.read(referralLinkNoticeProvider.notifier).state = false;
      final l10n = AppLocalizations.of(context)!;
      final router = GoRouter.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(l10n.referralLinkSignedIn),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: l10n.inviteAndEarn,
            onPressed: () => router.push(AppRoutes.inviteAndEarn),
          ),
        ));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
