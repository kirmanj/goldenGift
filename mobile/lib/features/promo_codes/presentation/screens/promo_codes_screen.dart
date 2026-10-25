import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/promo_code_model.dart';
import '../../data/promo_repository.dart';
import '../widgets/promo_ticket.dart';

/// Promo Codes (SRS §5.23, IMG_4491): "Love a Good Deal?" card and the
/// public, active, unexpired codes (the repository filters them; private
/// codes only work when typed in the cart). Guests can browse and apply.
class PromoCodesScreen extends ConsumerWidget {
  const PromoCodesScreen({super.key});

  static Future<void> copyCode(BuildContext context, String code) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = AppLocalizations.of(context)!.codeCopied;
    await Clipboard.setData(ClipboardData(text: code));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copied)));
  }

  /// Applies [promo] to the cart and opens the Cart tab.
  static void use(BuildContext context, WidgetRef ref, PromoCodeModel promo) {
    final l10n = AppLocalizations.of(context)!;
    ref.read(appliedPromoProvider.notifier).apply(promo.code);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.promoAppliedSnack(promo.code))));
    context.go(AppRoutes.mainTab(1));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final promos = ref.watch(publicPromosProvider);
    final applied = ref.watch(appliedPromoProvider);

    final Widget content = promos.when(
      loading: () => const SkeletonLoader.list(count: 3),
      error: (_, __) => ErrorState(onRetry: () => ref.invalidate(publicPromosProvider)),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.local_offer_outlined,
              title: l10n.noPromoCodesTitle,
              subtitle: l10n.noPromoCodesBody,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final promo in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: PromoTicket(
                      key: ValueKey('promo-${promo.code}'),
                      promo: promo,
                      applied: promo.code == applied,
                      onCopy: () => copyCode(context, promo.code),
                      onUse: () => use(context, ref, promo),
                    ),
                  ),
              ],
            ),
    );

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.promoCodes),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.sm,
          AppSpacing.screenHorizontal,
          MediaQuery.paddingOf(context).bottom + AppSpacing.lg,
        ),
        children: [
          const _DealsCard(),
          const SizedBox(height: AppSpacing.lg),
          content,
        ],
      ),
    );
  }
}

/// "Love a Good Deal? We Do Too! 🎉" with an illustration placeholder
/// (final artwork: SRS §12 item 1).
class _DealsCard extends StatelessWidget {
  const _DealsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line(context)),
        boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                l10n.promoHeaderTitle,
                style: AppTextStyles.heading2.copyWith(height: 1.4, color: AppColors.text(context)),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          ExcludeSemantics(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.card_giftcard_rounded, size: 44, color: AppColors.gold(context)),
                  PositionedDirectional(
                    top: 10,
                    end: 8,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.gold(context), width: 1.5),
                      ),
                      child: Icon(Icons.percent_rounded, size: 16, color: AppColors.goldText(context)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
