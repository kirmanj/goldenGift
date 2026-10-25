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
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/wallet_model.dart';
import '../../../product_details/presentation/widgets/option_formatting.dart' show errorTextColor;
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../payments/presentation/widgets/top_up_sheet.dart';
import '../../../profile/presentation/widgets/profile_header.dart' show ProfileMessageCard;
import '../../data/wallet_repository.dart';
import '../widgets/wallet_ui.dart';

/// My Wallet (SRS §5.18, IMG_4493): gold header, "Available Balance" card
/// (balance + credits = spendable), Top up (ZainCash, when enabled), transaction
/// history or the empty state. Only Cloud Functions / admins write wallets (§6.11).
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  static const patternIcons = [
    Icons.account_balance_wallet_outlined,
    Icons.credit_card_rounded,
    Icons.radio_button_checked_rounded,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final topUpEnabled = ref.watch(paymentSettingsProvider).valueOrNull?.zainCash ?? false;
    final bottom = MediaQuery.paddingOf(context).bottom + AppSpacing.lg;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: GoldPatternHeader(
              title: l10n.myWallet,
              patternIcons: patternIcons,
              overlapCard: signedIn ? const WalletBalanceCard() : null,
            ),
          ),
          if (!signedIn)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
              sliver: SliverToBoxAdapter(
                child: ProfileMessageCard(
                  key: const ValueKey('wallet-guest-card'),
                  icon: Icons.lock_outline_rounded,
                  title: l10n.signInToContinue,
                  body: l10n.walletSignInBody,
                  primaryLabel: l10n.signIn,
                  onPrimary: () => context.push(AppRoutes.signIn),
                  secondaryLabel: l10n.signUp,
                  onSecondary: () => context.push(AppRoutes.signUp),
                ),
              ),
            )
          else ...[
            // Top up (SRS §5.18): only while an online gateway (ZainCash) is on.
            if (topUpEnabled)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenHorizontal, AppSpacing.md, AppSpacing.screenHorizontal, 0),
                sliver: SliverToBoxAdapter(
                  child: PrimaryButton(
                    key: const ValueKey('wallet-top-up'),
                    label: l10n.walletTopUp,
                    icon: Icons.add_card_rounded,
                    onPressed: () => startWalletTopUp(context, ref),
                  ),
                ),
              ),
            const _Transactions(),
          ],
          SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ),
    );
  }
}

/// "Available Balance" with the spendable total and its Balance · Credits split.
class WalletBalanceCard extends ConsumerWidget {
  const WalletBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final wallet = ref.watch(walletProvider);
    final expiryDays = ref.watch(referralSettingsProvider).valueOrNull?.creditsExpiryDays ?? 0;
    final muted = AppColors.textMuted(context);
    final value = wallet.valueOrNull;

    final Widget amount;
    if (value != null) {
      amount = Text(
        CurrencyFormatter.format(value.spendable),
        key: const ValueKey('wallet-spendable'),
        textAlign: TextAlign.center,
        style:
            AppTextStyles.heading1.copyWith(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.text(context)),
      );
    } else if (wallet.hasError) {
      amount = Text('—', style: AppTextStyles.heading1.copyWith(color: AppColors.text(context)));
    } else {
      amount = const Center(child: SkeletonLoader.line(width: 160, height: 34));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line(context)),
        boxShadow: AppColors.isDark(context) ? null : AppElevation.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.availableBalance,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600, color: muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          amount,
          if (value != null) ...[
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _SplitPill(
                  key: const ValueKey('wallet-balance'),
                  icon: Icons.account_balance_wallet_rounded,
                  label: l10n.walletBalance,
                  amount: value.balance,
                ),
                _SplitPill(
                  key: const ValueKey('wallet-credits'),
                  icon: Icons.stars_rounded,
                  label: l10n.walletCredits,
                  amount: value.credits,
                ),
              ],
            ),
          ],
          if (expiryDays > 0) ...[
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline_rounded, size: 16, color: muted),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.creditsExpiryNote(expiryDays),
                    style: AppTextStyles.bodySmall.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SplitPill extends StatelessWidget {
  const _SplitPill({super.key, required this.icon, required this.label, required this.amount});
  final IconData icon;
  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs, vertical: AppSpacing.xs + AppSpacing.xxs),
        decoration: BoxDecoration(
          color: AppColors.soft(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.gold(context)),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              CurrencyFormatter.format(amount),
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Transaction history (newest first) with loading / error / empty states.
class _Transactions extends ConsumerWidget {
  const _Transactions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    const padding = EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.lg, AppSpacing.screenHorizontal, 0);
    return ref.watch(walletTransactionsProvider).when(
          loading: () => const SliverPadding(
            padding: padding,
            sliver: SliverToBoxAdapter(child: SkeletonLoader.list(count: 4)),
          ),
          error: (_, __) => SliverPadding(
            padding: padding,
            sliver: SliverToBoxAdapter(
              child: ErrorState(onRetry: () => ref.invalidate(walletTransactionsProvider)),
            ),
          ),
          data: (txns) {
            if (txns.isEmpty) {
              return SliverPadding(
                padding: padding,
                sliver: SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: l10n.noTransactionsYet,
                    subtitle: l10n.transactionHistoryHint,
                  ),
                ),
              );
            }
            return SliverPadding(
              padding: padding,
              sliver: SliverList.separated(
                itemCount: txns.length + 1,
                separatorBuilder: (_, i) => SizedBox(height: i == 0 ? AppSpacing.sm : AppSpacing.sm + AppSpacing.xxs),
                itemBuilder: (context, i) => i == 0
                    ? Semantics(
                        header: true,
                        child: Text(
                          l10n.walletTransactions,
                          style: AppTextStyles.sectionTitle.copyWith(color: AppColors.text(context)),
                        ),
                      )
                    : WalletTxnTile(txn: txns[i - 1]),
              ),
            );
          },
        );
  }
}

/// Localized name of a transaction type (used when the txn has no title).
String walletTxnTypeLabel(AppLocalizations l10n, WalletTxnType type) => switch (type) {
      WalletTxnType.topUp => l10n.txnTopUp,
      WalletTxnType.orderPayment => l10n.txnOrderPayment,
      WalletTxnType.refund => l10n.txnRefund,
      WalletTxnType.referralCredit => l10n.txnReferralCredit,
      WalletTxnType.giftCardRedeem => l10n.txnGiftCardRedeem,
      WalletTxnType.adminAdjustment => l10n.txnAdminAdjustment,
      WalletTxnType.creditExpiry => l10n.txnCreditExpiry,
    };

IconData walletTxnIcon(WalletTxnType type) => switch (type) {
      WalletTxnType.topUp => Icons.add_card_rounded,
      WalletTxnType.orderPayment => Icons.shopping_bag_rounded,
      WalletTxnType.refund => Icons.replay_rounded,
      WalletTxnType.referralCredit => Icons.group_add_rounded,
      WalletTxnType.giftCardRedeem => Icons.card_giftcard_rounded,
      WalletTxnType.adminAdjustment => Icons.tune_rounded,
      WalletTxnType.creditExpiry => Icons.timer_off_rounded,
    };

/// One wallet movement: type icon, title, date, bucket tag and the signed
/// amount (success green for +, error red for −).
class WalletTxnTile extends StatelessWidget {
  const WalletTxnTile({super.key, required this.txn});
  final WalletTxn txn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = txn.title.of(context);
    final amountColor = txn.amount > 0
        ? successTextColor(context)
        : txn.amount < 0
            ? errorTextColor(context)
            : AppColors.textMuted(context);
    final isCredits = txn.bucket == WalletBucket.credits;
    final amount = AmountText(
      signedAmount(txn.amount),
      style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w800, color: amountColor),
    );

    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.line(context)),
        ),
        // Narrow tile / large text: the amount moves under the details.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 260 * MediaQuery.textScalerOf(context).scale(1);
            return Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
                    child: Icon(walletTxnIcon(txn.type), size: 22, color: AppColors.gold(context)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? walletTxnTypeLabel(l10n, txn.type) : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.label.copyWith(height: 1.3, color: AppColors.text(context)),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (txn.createdAt != null)
                            Text(
                              AppDates.displayWithTime(txn.createdAt!),
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
                            ),
                          SoftTag(
                            label: isCredits ? l10n.walletCredits : l10n.walletBalance,
                            color: isCredits ? AppColors.primaryDark : AppColors.info,
                          ),
                        ],
                      ),
                      if (stacked) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Align(alignment: AlignmentDirectional.centerEnd, child: amount),
                      ],
                    ],
                  ),
                ),
                if (!stacked) ...[
                  const SizedBox(width: AppSpacing.sm),
                  amount,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
