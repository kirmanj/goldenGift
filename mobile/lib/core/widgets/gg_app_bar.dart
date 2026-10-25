import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'gg_circle_button.dart';

/// Golden Gift app bar: circular back button · centred title · optional
/// circular cart button with a gold count badge (SRS §5.7–§5.10, IMG_4481,
/// IMG_4494).
///
/// Back pops the current route (`Navigator.maybePop`, which also pops
/// GoRouter pages) unless [onBack] is given; the chevron mirrors in RTL.
/// [showBack] defaults to "only when there is something to pop".
/// The cart button appears when [onCartTap] is set; [actions] are extra
/// trailing circle buttons placed before it.
class GGAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GGAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.showBack,
    this.onBack,
    this.cartCount = 0,
    this.onCartTap,
    this.actions = const [],
    this.backgroundColor,
  });

  final String? title;

  /// Replaces [title] with a custom widget.
  final Widget? titleWidget;

  /// null = automatic (shown when the route can be popped).
  final bool? showBack;
  final VoidCallback? onBack;
  final int cartCount;
  final VoidCallback? onCartTap;
  final List<Widget> actions;

  /// Defaults to the page background (`AppColors.bg(context)`).
  final Color? backgroundColor;

  static const double height = 68;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final back = (showBack ?? canPop)
        ? GGCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack ?? () => Navigator.maybePop(context),
          )
        : null;

    final trailing = [
      ...actions,
      if (onCartTap != null)
        GGCircleButton(
          icon: Icons.shopping_bag_outlined,
          iconColor: AppColors.gold(context),
          tooltip: l10n.cart,
          badgeCount: cartCount,
          onPressed: onCartTap,
        ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppColors.isDark(context) ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Material(
        color: backgroundColor ?? AppColors.bg(context),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: NavigationToolbar(
                leading: back,
                middle: titleWidget ??
                    (title == null
                        ? null
                        : Semantics(
                            header: true,
                            child: Text(
                              title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                            ),
                          )),
                trailing: trailing.isEmpty
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < trailing.length; i++) ...[
                            if (i > 0) const SizedBox(width: AppSpacing.sm),
                            trailing[i],
                          ],
                        ],
                      ),
                middleSpacing: AppSpacing.sm,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
