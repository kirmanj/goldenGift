import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../gift_cards/data/gift_cards_repository.dart';
import '../../../gift_cards/presentation/widgets/home_gift_cards_section.dart';
import '../../../products/presentation/widgets/product_list_slivers.dart';
import '../../../referrals/presentation/widgets/referral_reward_sheet.dart';
import '../providers/home_providers.dart';
import '../widgets/discover_section.dart';
import '../widgets/home_header.dart';
import '../widgets/home_sections.dart';
import '../widgets/profile_completion_card.dart';

/// Home — the first MainShell tab (SRS §5.4, IMG_4476–4479).
///
/// One vertical scroll of independent sections, in SRS order. Each section is
/// its own widget watching its own provider: it shows a skeleton while
/// loading and disappears when empty or failed, so one failure never blanks
/// the page. Pull-to-refresh reloads every section.
///
/// Not yet: Gift Cards row (Phase 8), unread dot on the bell (Phase 6),
/// wishlist hearts (Phase 4). The referral sheet (item 13) and the
/// "referral codes are for new accounts" notice come from [ReferralSheetGate].
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Discover's selected chip (null = All).
  String? _discoverCategoryId;

  Future<void> _refresh() async {
    ref
      ..invalidate(homeBannersProvider)
      ..invalidate(homeCategoriesProvider)
      ..invalidate(popularProductsProvider)
      ..invalidate(featuredProductsProvider)
      ..invalidate(forYouProductsProvider)
      ..invalidate(homeGiftCardTemplatesProvider);
    Future<void> settle(Future<Object?> future) => future.then((_) {}, onError: (Object _) {});
    await Future.wait([
      settle(ref.read(homeBannersProvider.future)),
      settle(ref.read(homeCategoriesProvider.future)),
      settle(ref.read(popularProductsProvider.future)),
      settle(ref.read(featuredProductsProvider.future)),
      settle(ref.read(forYouProductsProvider.future)),
      if (DiscoverSection.comingSoonFor(ref, _discoverCategoryId) == null)
        refreshProductList(ref, DiscoverSection.queryFor(_discoverCategoryId)),
    ]).timeout(const Duration(seconds: 10), onTimeout: () => const []);
  }

  @override
  Widget build(BuildContext context) {
    // The floating bottom nav overlaps the body (extendBody).
    final bottomPadding = math.max(100.0, MediaQuery.paddingOf(context).bottom + AppSpacing.lg);

    return ReferralSheetGate(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppColors.isDark(context) ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        // A Material (not a ColoredBox) so tiles' ink stays visible.
        child: Material(
          color: AppColors.bg(context),
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.gold(context),
              backgroundColor: AppColors.card(context),
              onRefresh: _refresh,
              child: CustomScrollView(
                key: const PageStorageKey('home-scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: HomeHeader()),
                  const HomeOfflineChip(),
                  const HomeBannerSection(placement: BannerPlacement.homeTop),
                  const HomeCategoryGrid(),
                  const HomeShopForSection(),
                  const HomeProductSection(HomeProductKind.popular),
                  const HomeBannerSection(placement: BannerPlacement.homeMid1),
                const HomeGiftCardsSection(),
                  const HomeProductSection(HomeProductKind.featured),
                  const HomeBannerSection(placement: BannerPlacement.homeMid2),
                  const HomeProductSection(HomeProductKind.forYou),
                  const HomeBannerSection(placement: BannerPlacement.homeBottom),
                  const ProfileCompletionCard(),
                  DiscoverSection(
                    categoryId: _discoverCategoryId,
                    onCategoryChanged: (id) {
                      if (id != _discoverCategoryId) setState(() => _discoverCategoryId = id);
                    },
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
