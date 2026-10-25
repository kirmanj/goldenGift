import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/gift_card_model.dart';
import '../../../home/presentation/widgets/home_sections.dart' show HomeLayout;
import '../../data/gift_cards_repository.dart';
import 'gift_card_face.dart';

/// Home section 6 (SRS §5.4): a horizontal row of gold-shimmer gift-card
/// tiles from `gift_card_templates` by `sortOrder`; "View All" opens the
/// gift-card shop and a tile opens the Designer. Hidden when there are no
/// templates or the stream fails (one section never blanks Home).
class HomeGiftCardsSection extends ConsumerWidget {
  const HomeGiftCardsSection({super.key});

  static const double tileWidth = 184;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(homeGiftCardTemplatesProvider);
    final height = GiftCardFace.compactHeight(context);

    Widget row(int count, Widget Function(BuildContext, int) tile) => SizedBox(
          height: height,
          child: ListView.separated(
            key: const ValueKey('home-gift-cards-row'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.h),
            itemCount: count,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
            itemBuilder: (context, i) => SizedBox(width: tileWidth, child: tile(context, i)),
          ),
        );

    Widget section({required List<Widget> children}) => SliverPadding(
          padding: const EdgeInsets.only(top: HomeLayout.sectionGap),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        );

    if (!async.hasValue) {
      if (async.hasError) return const SliverToBoxAdapter();
      return section(children: [
        SectionHeader(title: l10n.giftCards, padding: const EdgeInsets.symmetric(horizontal: HomeLayout.h)),
        const SizedBox(height: AppSpacing.sm),
        row(3, (_, __) => const SkeletonLoader.box(radius: AppRadius.md)),
      ]);
    }
    final templates = async.requireValue;
    if (templates.isEmpty) return const SliverToBoxAdapter();

    return section(children: [
      SectionHeader(
        key: const ValueKey('home-gift-cards-header'),
        title: l10n.giftCards,
        padding: const EdgeInsets.symmetric(horizontal: HomeLayout.h),
        onViewAll: () => context.push(AppRoutes.giftCardsShop),
      ),
      const SizedBox(height: AppSpacing.sm),
      row(templates.length, (context, i) => HomeGiftCardTile(template: templates[i])),
    ]);
  }
}

class HomeGiftCardTile extends StatelessWidget {
  const HomeGiftCardTile({super.key, required this.template});
  final GiftCardTemplateModel template;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = template.name.of(context);
    final amount = templateAmountLabel(l10n, template);
    return Semantics(
      button: true,
      label: [l10n.giftCardLabel, name, if (amount != null) amount].join(', '),
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('home-gift-card-${template.id}'),
        onTap: () => context.push(AppRoutes.giftCardDesign(template.id)),
        child: GiftCardFace(
          compact: true,
          gradient: templateGradient(template),
          title: name.isEmpty ? l10n.giftCards : name,
          amount: amount,
          artworkUrl: template.artworkUrl,
        ),
      ),
    );
  }
}
