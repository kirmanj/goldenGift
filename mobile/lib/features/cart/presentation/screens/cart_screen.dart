import 'dart:async';
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
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../providers/cart_controller.dart';
import '../providers/cart_lines.dart';
import '../widgets/cart_line_tile.dart';
import '../widgets/cart_summary_card.dart';

/// Cart tab (SRS §5.10, IMG_4480). Lives in MainShell's IndexedStack: no
/// back button, and the floating bottom nav overlaps the body, so content
/// keeps ≥ 100 px of bottom padding.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  static double bottomPadding(BuildContext context) =>
      math.max(100.0, MediaQuery.paddingOf(context).bottom + AppSpacing.lg);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cart = ref.watch(cartControllerProvider);

    final Widget body;
    if (cart.isLoading) {
      body = const _CartSkeleton();
    } else if (cart.items.isEmpty) {
      body = _Centered(
        child: cart.error != null
            ? ErrorState(onRetry: () => ref.invalidate(cartControllerProvider))
            : EmptyState(
                title: l10n.emptyCartTitle,
                subtitle: l10n.emptyCartSubtitle,
                icon: Icons.shopping_bag_outlined,
                ctaLabel: l10n.startShopping,
                onCta: () => context.go(AppRoutes.mainTab(0)),
              ),
      );
    } else {
      body = const _CartContent();
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.myCart, showBack: false),
      body: body,
    );
  }
}

/// Centres a non-scrolling state and lets it scroll on short screens /
/// large text, clear of the floating nav.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = CartScreen.bottomPadding(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - bottom)),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _CartSkeleton extends StatelessWidget {
  const _CartSkeleton();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
        child: SkeletonLoader.list(count: 3),
      );
}

class _CartContent extends ConsumerWidget {
  const _CartContent();

  Future<void> _checkout(BuildContext context, WidgetRef ref) async {
    if (!await requireSignIn(context, ref)) return;
    if (context.mounted) unawaited(context.push(AppRoutes.checkout));
  }

  void _run(BuildContext context, Future<void> Function() action) {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context)!.somethingWentWrong;
    action().catchError((Object _) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(cartControllerProvider.select((s) => s.items));
    final summaryAsync = ref.watch(cartSummaryProvider);
    final productsAsync = ref.watch(cartProductsProvider);
    final products = productsAsync.valueOrNull;

    // While product docs reload (a product left the cart), keep showing the
    // last summary as long as every line's product is in it — no skeleton
    // flash on remove.
    final staleButComplete = summaryAsync.isLoading &&
        summaryAsync.hasValue &&
        products != null &&
        items.every((i) => products.containsKey(i.productId));
    final summary =
        summaryAsync.hasValue && (!summaryAsync.isLoading || staleButComplete) ? summaryAsync.requireValue : null;

    if (summary == null) {
      if (summaryAsync.hasError && !summaryAsync.isLoading) {
        return _Centered(child: ErrorState(onRetry: () => ref.invalidate(cartProductsProvider)));
      }
      return const _CartSkeleton();
    }

    final controller = ref.read(cartControllerProvider.notifier);
    final showStores = summary.groups.length > 1;
    final children = <Widget>[];
    for (final group in summary.groups) {
      if (showStores) {
        final name = group.store?.name.of(context) ?? '';
        children.add(Padding(
          padding: EdgeInsets.only(
            top: children.isEmpty ? 0 : AppSpacing.md,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.storefront_outlined, size: 18, color: AppColors.gold(context)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    name.isEmpty ? '' : l10n.soldBy(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
                  ),
                ),
              ),
            ],
          ),
        ));
      }
      for (final line in group.lines) {
        final product = products?[line.item.productId];
        final stockCap = product?.stock;
        final maxQty = math.max(
          1,
          math.min(CartController.maxQty, stockCap ?? CartController.maxQty),
        );
        children.add(Padding(
          key: ValueKey(line.item.id),
          padding: const EdgeInsets.only(bottom: AppSpacing.sm + AppSpacing.xs),
          child: CartLineTile(
            line: line,
            maxQty: maxQty,
            onQtyChanged: (qty) => _run(context, () => controller.setQty(line.item.id, qty)),
            onRemove: () => _run(context, () => controller.remove(line.item.id)),
          ),
        ));
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
        AppSpacing.screenHorizontal,
        CartScreen.bottomPadding(context),
      ),
      children: [
        ...children,
        const SizedBox(height: AppSpacing.sm),
        CartSummaryCard(summary: summary, onCheckout: () => _checkout(context, ref)),
      ],
    );
  }
}
