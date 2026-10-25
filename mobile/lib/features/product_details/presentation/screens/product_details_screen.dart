import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/cart_item_model.dart';
import '../../../../models/product_model.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../../cart/presentation/providers/cart_controller.dart';
import '../../../products/presentation/widgets/gift_audience_widgets.dart';
import '../../../reviews/presentation/widgets/product_reviews_section.dart';
import '../../data/photo_service.dart';
import '../../data/product_repository.dart';
import '../../domain/product_configuration.dart';
import '../providers/product_details_controller.dart';
import '../widgets/add_to_cart_bar.dart';
import '../widgets/option_group_section.dart';
import '../widgets/product_image_carousel.dart';
import '../widgets/product_summary.dart';

/// Product Details (SRS §5.9, IMG_4494, IMG_4501 … 4509): carousel,
/// availability banner, title, price + Share, About, Reviews (§5.26), one
/// input per option group, and the sticky quantity + Add to Cart bar.
///
/// The configuration lives in [productDetailsControllerProvider]; this
/// widget only rebuilds when the product document itself changes.
class ProductDetailsScreen extends ConsumerStatefulWidget {
  const ProductDetailsScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen> {
  final _scrollController = ScrollController();
  final _groupKeys = <String, GlobalKey>{};
  bool _viewRecorded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // view_item + viewing history, once per screen open (SRS §4.7, §5.4 "For you").
    ref.listenManual<AsyncValue<ProductModel?>>(productByIdProvider(widget.productId), (_, next) {
      final product = next.valueOrNull;
      if (product == null || !product.isActive || _viewRecorded) return;
      _viewRecorded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) recordProductView(ref, product);
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Option groups in display order (`quantity` lives in the bottom bar).
  static List<OptionGroup> _inputGroups(ProductModel product) {
    final groups = product.optionGroups.where((g) => g.type != OptionType.quantity).toList();
    // Stable sort: equal sortOrder keeps the document order.
    final indexed = groups.asMap().entries.toList()
      ..sort((a, b) {
        final bySort = a.value.sortOrder.compareTo(b.value.sortOrder);
        return bySort != 0 ? bySort : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  GlobalKey _keyFor(String groupId) => _groupKeys.putIfAbsent(groupId, GlobalKey.new);

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToFirstIssue(ProductModel product, List<OptionIssue> issues) {
    final withIssue = {for (final i in issues) i.groupId};
    final first = _inputGroups(product).where((g) => withIssue.contains(g.id)).firstOrNull;
    if (first == null) return;
    // After the frame that shows the hints, so the target includes them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _groupKeys[first.id]?.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// SRS §5.9 Add to Cart: validate → (photos need an account) → upload
  /// photos to `uploads/{uid}/{cartItemId}/…` → snapshot line into the cart.
  Future<void> _addToCart(ProductModel product) async {
    if (_busy || product.isOutOfStock) return;
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(productDetailsControllerProvider(product.id).notifier);
    final cart = ref.read(cartControllerProvider.notifier);
    final photoService = ref.read(photoServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final config = notifier.config;
    if (config == null) return;

    final issues = notifier.revealIssues();
    if (issues.isNotEmpty) {
      _scrollToFirstIssue(product, issues);
      return;
    }

    _busy = true;
    try {
      final cartItemId = const Uuid().v4();
      var uploadedUrls = const <String, List<String>>{};
      if (config.hasPhotos) {
        // Customer photos are stored under the account (SRS §6.16).
        if (!await requireSignIn(context, ref)) return;
        if (!mounted) return;
        final uid = ref.read(authStateProvider).valueOrNull?.uid;
        if (uid == null) {
          _showSnack(l10n.photoUploadFailed);
          return;
        }
        notifier.setUploadProgress(0);
        try {
          uploadedUrls = await photoService.upload(
            uid: uid,
            cartItemId: cartItemId,
            photosByGroup: config.photosByGroup,
            onProgress: (p) {
              if (notifier.mounted) notifier.setUploadProgress(p.clamp(0.0, 1.0));
            },
          );
        } catch (_) {
          if (mounted) _showSnack(l10n.photoUploadFailed);
          return;
        } finally {
          if (notifier.mounted) notifier.setUploadProgress(null);
        }
      }

      await cart.add(CartItemModel(
        id: cartItemId,
        productId: product.id,
        storeId: product.storeId,
        titleSnapshot: product.title,
        imageSnapshot: product.mainImage,
        unitPrice: config.unitPrice,
        qty: config.qty,
        selections: config.toCartSelections(uploadedUrls: uploadedUrls),
        preparationDays: config.preparationDays,
      ));
    } catch (_) {
      if (mounted) _showSnack(l10n.somethingWentWrong);
      return;
    } finally {
      _busy = false;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.addedToCart),
        persist: false,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: l10n.viewCart,
          onPressed: () => router.go(AppRoutes.mainTab(1)),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final productAsync = ref.watch(productByIdProvider(widget.productId));

    Widget page(Widget body, {Widget? bottom}) => Scaffold(
          backgroundColor: AppColors.bg(context),
          appBar: const _DetailsAppBar(),
          bottomNavigationBar: bottom,
          body: body,
        );

    return productAsync.when(
      skipLoadingOnRefresh: false,
      loading: () => page(const _DetailsSkeleton()),
      error: (_, __) => page(ErrorState(
        onRetry: () => ref.invalidate(productByIdProvider(widget.productId)),
      )),
      data: (product) {
        // Hidden by the seller / admin = no longer available (e.g. an old share link).
        if (product == null || !product.isActive) {
          return page(EmptyState(
            title: l10n.productNotFound,
            icon: Icons.search_off_rounded,
            ctaLabel: l10n.startShopping,
            onCta: () => context.go(AppRoutes.mainTab(0)),
          ));
        }
        return page(
          Stack(
            children: [
              _DetailsBody(
                product: product,
                groups: _inputGroups(product),
                controller: _scrollController,
                keyFor: _keyFor,
              ),
              Positioned.fill(child: UploadProgressOverlay(productId: product.id)),
            ],
          ),
          bottom: AddToCartBar(
            productId: product.id,
            outOfStock: product.isOutOfStock,
            onAddToCart: () => unawaited(_addToCart(product)),
          ),
        );
      },
    );
  }
}

/// App bar with the live cart badge; only this rebuilds when the cart changes.
class _DetailsAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _DetailsAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(GGAppBar.height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GGAppBar(
      title: AppLocalizations.of(context)!.productDetails,
      cartCount: ref.watch(cartCountProvider),
      onCartTap: () => context.go(AppRoutes.mainTab(1)),
    );
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({
    required this.product,
    required this.groups,
    required this.controller,
    required this.keyFor,
  });

  final ProductModel product;
  final List<OptionGroup> groups;
  final ScrollController controller;
  final GlobalKey Function(String groupId) keyFor;

  @override
  Widget build(BuildContext context) {
    // A Column (not a lazy list): every group is laid out, so Add to Cart can
    // scroll to any of them; the page is short enough for that.
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
        AppSpacing.screenHorizontal,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProductImageCarousel(product: product),
          const SizedBox(height: AppSpacing.md),
          AvailabilityBanner(product: product),
          const SizedBox(height: AppSpacing.md),
          Text(
            product.title.of(context),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.heading2.copyWith(color: AppColors.text(context)),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          PriceShareRow(product: product),
          if (product.giftFor.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            GiftForPills(audiences: product.giftFor),
          ],
          const SizedBox(height: AppSpacing.lg),
          AboutProductSection(text: product.description.of(context)),
          // Reviews below About (SRS §5.26); watches only its own stream.
          ProductReviewsSection(product: product),
          for (final group in groups)
            Padding(
              key: keyFor(group.id),
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: OptionGroupSection(productId: product.id, group: group),
            ),
        ],
      ),
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
        AppSpacing.screenHorizontal,
        AppSpacing.xl,
      ),
      child: Semantics(
        label: AppLocalizations.of(context)!.loading,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: ProductImageCarousel.aspectRatio,
              child: SkeletonLoader.box(radius: AppRadius.lg),
            ),
            SizedBox(height: AppSpacing.md),
            SkeletonLoader.box(height: 44, radius: AppRadius.md),
            SizedBox(height: AppSpacing.md),
            SkeletonLoader.line(height: 22),
            SizedBox(height: AppSpacing.sm),
            SkeletonLoader.line(width: 180, height: 22),
            SizedBox(height: AppSpacing.md),
            SkeletonLoader.line(width: 140, height: 28),
            SizedBox(height: AppSpacing.lg),
            SkeletonLoader.line(),
            SizedBox(height: AppSpacing.sm),
            SkeletonLoader.line(),
          ],
        ),
      ),
    );
  }
}
