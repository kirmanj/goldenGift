import 'dart:async';
import 'dart:math' as math;

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
import '../../../../models/app_settings_model.dart';
import '../../../../models/order_model.dart';
import '../../../addresses/presentation/widgets/address_card.dart';
import '../../../cart/presentation/providers/cart_controller.dart';
import '../../../cart/presentation/widgets/cart_line_tile.dart' show cartSelectionSummary;
import '../../../payments/data/payments_repository.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../../payments/presentation/widgets/payment_ui.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../reviews/presentation/providers/review_providers.dart';
import '../../data/orders_repository.dart';
import '../providers/order_reorder.dart';
import '../widgets/order_card.dart';
import '../widgets/order_dialogs.dart';
import '../widgets/order_extras.dart';
import '../widgets/order_labels.dart';
import '../widgets/order_review_action.dart';
import '../widgets/order_section.dart';
import '../widgets/order_status_chip.dart';
import '../widgets/order_timeline.dart';

/// Order Details (SRS §5.12): status timeline, personalized items with their
/// photos, address, delivery, gift message, payment and totals; Cancel (while
/// pending / confirmed, through `cancelOrder`), Reorder, Contact support and
/// Rate per delivered product (§5.26).
class OrderDetailsScreen extends ConsumerStatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  bool _cancelling = false;
  bool _reordering = false;
  bool _paying = false;

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context)!;
    final reason = await showCancelOrderDialog(context);
    if (reason == null || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(ordersRepositoryProvider).cancelOrder(widget.orderId, reason: reason.isEmpty ? null : reason);
      if (mounted) showOrderSnack(context, l10n.orderCancelled);
    } on OrderFailure catch (f) {
      if (!mounted) return;
      showOrderSnack(
        context,
        switch (f.reason) {
          OrderFailureReason.notCancellable => l10n.orderNotCancellable,
          OrderFailureReason.unavailable => l10n.orderFailedUnavailable,
          _ => l10n.somethingWentWrong,
        },
      );
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  /// Every line goes back into the cart as a new line (new id, same
  /// personalization); the cart re-checks price and stock.
  Future<void> _reorder(OrderModel order) async {
    final l10n = AppLocalizations.of(context)!;
    final router = GoRouter.of(context);
    final cart = ref.read(cartControllerProvider.notifier);
    setState(() => _reordering = true);
    try {
      await addOrderLinesToCart(cart, order);
      if (!mounted) return;
      showOrderSnack(context, l10n.reorderAdded);
      router.go(AppRoutes.mainTab(1));
    } catch (_) {
      if (mounted) {
        showOrderSnack(context, l10n.somethingWentWrong);
        setState(() => _reordering = false);
      }
    }
  }

  /// "Pay now" (SRS §5.11): a new ZainCash session for this unpaid order →
  /// ZainCash's page → the payment status page.
  Future<void> _payNow(OrderModel order) async {
    final l10n = AppLocalizations.of(context)!;
    final router = GoRouter.of(context);
    setState(() => _paying = true);
    try {
      final session = await ref.read(paymentsRepositoryProvider).startOrderPayment(order.id);
      final opened = await openPaymentPage(ref.read(externalLinkOpenerProvider), session.payUrl);
      if (!mounted) return;
      if (!opened) showOrderSnack(context, l10n.paymentOpenFailed);
      unawaited(router.push(AppRoutes.paymentFor(session.sessionId)));
    } on PaymentFailure catch (f) {
      if (mounted) showOrderSnack(context, paymentFailureMessage(l10n, f.reason));
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final appBar = GGAppBar(
      title: l10n.orderDetails,
      showBack: true,
      onBack: () => popOrGo(context, AppRoutes.orders),
    );

    Widget body;
    if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.receipt_long_rounded);
    } else {
      body = ref.watch(orderByIdProvider(widget.orderId)).when(
            loading: () => const SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
              child: SkeletonLoader.list(count: 4),
            ),
            error: (_, __) => CenteredScroll(
              child: ErrorState(onRetry: () => ref.invalidate(orderByIdProvider(widget.orderId))),
            ),
            data: (order) => order == null
                ? CenteredScroll(
                    child: ErrorState(onRetry: () => ref.invalidate(orderByIdProvider(widget.orderId))),
                  )
                : _details(context, l10n, order),
          );
    }
    return Scaffold(backgroundColor: AppColors.bg(context), appBar: appBar, body: body);
  }

  Widget _details(BuildContext context, AppLocalizations l10n, OrderModel order) {
    final history = ref.watch(orderHistoryProvider(widget.orderId)).valueOrNull ?? const <StatusHistoryEntry>[];
    final cities = ref.watch(citiesProvider).valueOrNull ?? const <CityModel>[];
    final slots = ref.watch(generalSettingsProvider).valueOrNull?.deliverySlots ?? DeliverySlot.defaults;
    final muted = AppColors.textMuted(context);
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    const gap = SizedBox(height: AppSpacing.md);
    final address = order.address;
    final when = deliveryWhen(context, order.deliveryDate, order.deliverySlot, slots);
    final paidWithBalance = order.creditsUsed + order.walletUsed;
    // Keeps the cart started (it attaches to the account asynchronously);
    // Reorder waits until lines can be written to the right store.
    final cartReady = !ref.watch(cartControllerProvider.select((s) => s.isLoading));
    final reviewable = reviewableLineIds(order);
    final awaitingPayment = orderAwaitsOnlinePayment(order, ref.watch(paymentClockProvider).now());

    return ListView(
      key: const ValueKey('order-details-list'),
      padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
      children: [
        // Header
        OrderSection(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.orderNumber(order.orderNumber),
                      style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                    ),
                    if (order.createdAt != null)
                      Text(AppDates.display(order.createdAt!), style: AppTextStyles.bodyMedium.copyWith(color: muted)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: OrderStatusChip(status: order.status)),
            ],
          ),
        ),
        gap,
        OrderSection(
          title: l10n.orderStatus,
          icon: Icons.timeline_rounded,
          child: OrderTimeline(steps: orderTimeline(order, history)),
        ),
        gap,
        OrderSection(
          title: l10n.items,
          icon: Icons.card_giftcard_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < order.items.length; i++) ...[
                if (i > 0) Divider(height: AppSpacing.lg, color: AppColors.line(context)),
                _OrderItemRow(
                  item: order.items[i],
                  orderStatus: order.status,
                  orderId: order.id,
                  reviewable: reviewable.contains(order.items[i].line.id),
                ),
              ],
            ],
          ),
        ),
        gap,
        // Gift cards ship nothing: the recipient instead of an address.
        if (order.orderType == OrderType.giftCard) GiftCardRecipientSection(orderId: order.id),
        if (address != null) ...[
          OrderSection(
            title: l10n.deliveryAddress,
            icon: Icons.local_shipping_outlined,
            child: AddressCard(
              address: address,
              cityName: cityDisplayName(context, cities, address.city),
              outlined: false,
              showDefaultChip: false,
            ),
          ),
          gap,
        ],
        if (when.isNotEmpty) ...[
          OrderSection(
            title: l10n.deliveryDateAndTime,
            icon: Icons.event_outlined,
            child: Text(
              when,
              key: const ValueKey('order-delivery-when'),
              style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
            ),
          ),
          gap,
        ],
        if (order.isGift && (order.giftMessage?.trim().isNotEmpty ?? false)) ...[
          OrderSection(
            title: l10n.giftMessage,
            icon: Icons.mail_outline_rounded,
            child: Text(order.giftMessage!, style: AppTextStyles.bodyLarge.copyWith(color: AppColors.text(context))),
          ),
          gap,
        ],
        OrderSection(
          title: l10n.paymentInfo,
          icon: Icons.payments_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Text(
                    paymentMethodLabel(l10n, order.paymentMethod),
                    style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
                  ),
                  PaymentStatusChip(key: const ValueKey('payment-status'), status: order.paymentStatus),
                ],
              ),
              // An unpaid ZainCash order: pay before paymentDueBy or it is cancelled.
              if (awaitingPayment) ...[
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                PaymentCountdown(
                  deadline: order.paymentDueBy!,
                  onExpired: () {
                    if (mounted) setState(() {});
                  },
                  builder: (context, remaining) => InfoBanner(
                    key: const ValueKey('pay-within'),
                    type: InfoBannerType.warning,
                    icon: Icons.timer_outlined,
                    message: l10n.payWithinNote(formatCountdown(remaining)),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                PrimaryButton(
                  key: const ValueKey('pay-now'),
                  label: l10n.payNow,
                  icon: Icons.smartphone_rounded,
                  isLoading: _paying,
                  onPressed: _paying || _cancelling ? null : () => _payNow(order),
                ),
              ],
            ],
          ),
        ),
        gap,
        OrderSection(
          title: l10n.orderSummary,
          icon: Icons.receipt_long_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmountRow(label: l10n.subtotal, amount: order.subtotal),
              if (order.discount > 0) AmountRow(label: l10n.discount, amount: order.discount, negative: true),
              AmountRow(label: l10n.deliveryFee, amount: order.deliveryFee),
              if (paidWithBalance > 0) AmountRow(label: l10n.walletPayment, amount: paidWithBalance, negative: true),
              AmountRow(label: l10n.total, amount: order.total, emphasized: true),
              if (order.refundedTotal > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                OrderRefundRow(order: order),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Gift-card / special-request lines are synthetic (no product to re-add).
        if (order.items.isNotEmpty && order.orderType == OrderType.standard) ...[
          PrimaryButton(
            key: const ValueKey('reorder'),
            label: l10n.reorder,
            icon: Icons.replay_rounded,
            isLoading: _reordering,
            onPressed: _cancelling || !cartReady ? null : () => _reorder(order),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        ],
        OutlineButton(
          key: const ValueKey('contact-support'),
          label: l10n.contactSupport,
          icon: Icons.support_agent_rounded,
          onPressed: () => unawaited(context.push(AppRoutes.contactUs)),
        ),
        if (order.status.customerCanCancel) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton.icon(
              key: const ValueKey('cancel-order'),
              onPressed: _cancelling || _reordering ? null : _cancel,
              style: TextButton.styleFrom(foregroundColor: errorText(context), minimumSize: const Size(44, 48)),
              icon: _cancelling
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: errorText(context)),
                    )
                  : const Icon(Icons.cancel_outlined),
              label: Text(l10n.cancelOrder, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }
}

/// A line: image, title, personalization summary, quantity × price, its own
/// status when it differs (multi-vendor) and the uploaded photos.
class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({
    required this.item,
    required this.orderStatus,
    required this.orderId,
    this.reviewable = false,
  });

  final OrderItem item;
  final OrderStatus orderStatus;
  final String orderId;

  /// Shows the Rate / review status row (SRS §5.12, §5.26).
  final bool reviewable;

  @override
  Widget build(BuildContext context) {
    final line = item.line;
    final summary = cartSelectionSummary(context, line);
    final photos = [for (final s in line.selections) ...s.urls];
    final muted = AppColors.textMuted(context);
    return Column(
      key: ValueKey('order-item-${line.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox.square(dimension: 64, child: GGNetworkImage(url: line.imageSnapshot)),
            ),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.titleSnapshot.of(context),
                    style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                  ),
                  if (summary.isNotEmpty) Text(summary, style: AppTextStyles.bodySmall.copyWith(color: muted)),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${line.qty} × ${CurrencyFormatter.format(line.unitPrice)}',
                        textDirection: TextDirection.ltr,
                        style: AppTextStyles.bodyMedium.copyWith(color: muted),
                      ),
                      Text(
                        CurrencyFormatter.format(line.lineTotal),
                        textDirection: TextDirection.ltr,
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.goldText(context),
                        ),
                      ),
                      if (item.status != orderStatus) OrderStatusChip(status: item.status, compact: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < photos.length; i++)
                Semantics(
                  button: true,
                  label: AppLocalizations.of(context)!.photosCount(photos.length),
                  child: InkWell(
                    key: ValueKey('order-photo-${line.id}-$i'),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => showPhotoViewer(context, photos, initialIndex: i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: SizedBox.square(dimension: 56, child: GGNetworkImage(url: photos[i])),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (reviewable) ...[
          const SizedBox(height: AppSpacing.sm),
          OrderLineReviewAction(
            target: ReviewTarget(
              productId: line.productId,
              orderId: orderId,
              storeId: line.storeId,
              productTitle: line.titleSnapshot,
              image: line.imageSnapshot,
            ),
            lineId: line.id,
          ),
        ],
      ],
    );
  }
}
