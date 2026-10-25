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
import '../../../orders/presentation/widgets/order_section.dart' show CenteredScroll;
import '../../data/gift_cards_repository.dart';
import '../widgets/gift_card_face.dart';

/// Gift-card shop (SRS §5.22): every active template as a card; a tap opens
/// the Designer ("Design Your Gift Card — Make it personal").
class GiftCardShopScreen extends ConsumerWidget {
  const GiftCardShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(giftCardTemplatesProvider);
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);

    Widget body;
    if (async.hasError && !async.hasValue) {
      body = CenteredScroll(child: ErrorState(onRetry: () => ref.invalidate(giftCardTemplatesProvider)));
    } else if (!async.hasValue) {
      body = const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
        child: Column(
          children: [
            AspectRatio(aspectRatio: 1.6, child: SkeletonLoader.box(radius: AppRadius.lg)),
            SizedBox(height: AppSpacing.md),
            AspectRatio(aspectRatio: 1.6, child: SkeletonLoader.box(radius: AppRadius.lg)),
          ],
        ),
      );
    } else if (async.requireValue.isEmpty) {
      body = CenteredScroll(
        child: EmptyState(
          key: const ValueKey('gift-shop-empty'),
          title: l10n.giftCardShopEmptyTitle,
          subtitle: l10n.giftCardShopEmptyBody,
          icon: Icons.card_giftcard_rounded,
        ),
      );
    } else {
      final templates = async.requireValue;
      body = ListView.separated(
        key: const ValueKey('gift-shop-list'),
        padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
        itemCount: templates.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Text(
              l10n.giftCardDesignTagline,
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context)),
            );
          }
          final t = templates[i - 1];
          final name = t.name.of(context);
          final amount = templateAmountLabel(l10n, t);
          return Semantics(
            button: true,
            label: [name, if (amount != null) amount].join(', '),
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('shop-template-${t.id}'),
              onTap: () => context.push(AppRoutes.giftCardDesign(t.id)),
              child: GiftCardFace(
                gradient: templateGradient(t),
                title: name.isEmpty ? l10n.giftCards : name,
                amount: amount,
                artworkUrl: t.artworkUrl,
                aspectRatio: 1.75,
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.giftCardShopTitle),
      body: body,
    );
  }
}
