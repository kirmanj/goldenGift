import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cart/presentation/providers/cart_controller.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/reels/presentation/screens/reels_screen.dart';
import '../../l10n/l10n.dart';
import '../router/app_router.dart';
import '../services/push_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// Bottom navigation shell: Home · Reels · Cart · Profile (SRS §5.3).
/// IndexedStack keeps each tab's state. Not a GoRouter ShellRoute (BB convention).
/// The state holds [MainTab] ids, not positions; Reels is built the first time
/// it is opened (no reads or video downloads before) and turns the nav dark.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _index = widget.initialIndex;
  late bool _reelsOpened = _index == MainTab.reels;

  /// Visual order of the tabs (ids).
  static const _order = [MainTab.home, MainTab.reels, MainTab.cart, MainTab.profile];

  /// `context.go(AppRoutes.mainTab(n))` from anywhere (e.g. "View cart") reuses
  /// this page with a new `?tab=` — follow it. Tab taps keep the URL in sync
  /// (see [_select]), so a later `go` to any other tab is always a change.
  @override
  void didUpdateWidget(MainShell old) {
    super.didUpdateWidget(old);
    if (old.initialIndex != widget.initialIndex && widget.initialIndex != _index) {
      _index = widget.initialIndex;
      if (_index == MainTab.reels) _reelsOpened = true;
    }
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      if (i == MainTab.reels) _reelsOpened = true;
    });
    final router = GoRouter.maybeOf(context);
    if (router != null && router.state.uri.path == AppRoutes.main) router.go(AppRoutes.mainTab(i));
  }

  @override
  Widget build(BuildContext context) {
    // Registers this device for order / broadcast pushes once someone signs in (SRS §4.5).
    ref.watch(pushRegistrationProvider);
    final l10n = AppLocalizations.of(context)!;
    final icons = {
      MainTab.home: (Icons.home_outlined, Icons.home_rounded, l10n.home),
      MainTab.reels: (Icons.slow_motion_video_outlined, Icons.slow_motion_video_rounded, l10n.reels),
      MainTab.cart: (Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, l10n.cart),
      MainTab.profile: (Icons.person_outline_rounded, Icons.person_rounded, l10n.profile),
    };
    final onReels = _index == MainTab.reels;
    // A builder, so the colours resolve under the dark theme on Reels.
    Widget nav(BuildContext context) => SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm + AppSpacing.xs),
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppElevation.card,
        ),
        child: Row(
          children: [
            for (final i in _order)
              Expanded(
                // Screen readers announce which tab is active (SRS §8).
                child: Semantics(
                  selected: _index == i,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    onTap: () => _select(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CartBadge(
                          count: i == MainTab.cart ? ref.watch(cartCountProvider) : 0,
                          child: Icon(
                            _index == i ? icons[i]!.$2 : icons[i]!.$1,
                            color: _index == i ? AppColors.gold(context) : AppColors.textMuted(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          icons[i]!.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _index == i ? AppColors.goldText(context) : AppColors.textMuted(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 3,
                          width: _index == i ? 28 : 0,
                          decoration: BoxDecoration(
                            color: AppColors.gold(context),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        // Children in MainTab id order.
        index: _index,
        children: [
          const HomeScreen(),
          const CartScreen(),
          const ProfileScreen(),
          if (_reelsOpened) ReelsScreen(active: onReels) else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: onReels
          ? Theme(
              data: AppTheme.darkTheme(Localizations.localeOf(context)),
              child: Builder(builder: nav),
            )
          : Builder(builder: nav),
    );
  }
}

/// Gold count badge on the Cart tab when it holds items (SRS §5.3).
class _CartBadge extends StatelessWidget {
  const _CartBadge({required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      backgroundColor: AppColors.gold(context),
      textColor: AppColors.textOnPrimary,
      child: child,
    );
  }
}
