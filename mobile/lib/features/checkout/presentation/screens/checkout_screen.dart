import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/address_model.dart';
import '../../../../models/app_settings_model.dart';
import '../../../addresses/data/address_repository.dart';
import '../../../addresses/presentation/widgets/address_card.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../../cart/presentation/providers/cart_controller.dart';
import '../../../cart/presentation/providers/cart_lines.dart';
import '../../../orders/data/orders_repository.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../payments/data/payments_repository.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../../payments/presentation/widgets/payment_ui.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../promo_codes/data/promo_repository.dart';
import '../../../wallet/data/wallet_repository.dart';
import '../../domain/checkout_rules.dart';
import '../providers/checkout_providers.dart';
import '../widgets/checkout_delivery_section.dart';
import '../widgets/checkout_options_sections.dart';
import '../widgets/checkout_summary_section.dart';

/// Checkout (SRS §5.11): one scrolling page — address, delivery date & slot,
/// gift options, payment, summary — and a sticky Place order button. The
/// `placeOrder` function re-validates everything server-side.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _giftMessage = TextEditingController();
  bool _guardStarted = false;
  bool _loggedBegin = false;
  bool _leaving = false;

  /// Set once `placeOrder` succeeded: the cart empties, but that must not
  /// bounce the customer back to the cart.
  bool _placed = false;

  /// ZainCash: the order exists, `createPaymentSession` is running.
  bool _startingPayment = false;

  @override
  void dispose() {
    _giftMessage.dispose();
    super.dispose();
  }

  void _leave() {
    if (_leaving || !mounted) return;
    _leaving = true;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go(AppRoutes.mainTab(1));
    }
  }

  /// Guests: "Sign in to continue"; closing the sheet leaves checkout.
  Future<void> _guard() async {
    if (await requireSignIn(context, ref)) return;
    // "Sign in" pushes the sign-in page; let that navigation land first.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || ref.read(isSignedInProvider)) return;
    // Still a guest and still on top (the sheet was dismissed, not "Sign in").
    if (ModalRoute.of(context)?.isCurrent ?? false) _leave();
  }

  void _backToCart() {
    if (_leaving || !mounted) return;
    _leaving = true;
    context.go(AppRoutes.mainTab(1));
  }

  Future<void> _changeAddress() async {
    final picked = await context.push<AddressModel>('${AppRoutes.addresses}?select=1');
    if (picked != null && mounted) ref.read(checkoutControllerProvider.notifier).selectAddress(picked);
  }

  Future<void> _addAddress() async {
    final saved = await context.push<AddressModel>(AppRoutes.addressForm);
    if (saved != null && mounted) ref.read(checkoutControllerProvider.notifier).selectAddress(saved);
  }

  void _logBegin(CartSummary summary) {
    if (_loggedBegin) return;
    _loggedBegin = true;
    unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.beginCheckout, {
      'currency': AppConstants.currencyCode,
      'value': summary.subtotal,
      'items': [
        for (final l in summary.lines.where((l) => l.counts))
          {'item_id': l.item.productId, 'price': l.currentUnitPrice ?? l.item.unitPrice, 'quantity': l.item.qty},
      ],
    }));
  }

  Future<void> _placeOrder({
    required AddressModel address,
    required DeliveryChoice delivery,
    required int minOrder,
    required PaymentMethod method,
    String? promoCode,
    required bool useCredits,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final router = GoRouter.of(context);
    final controller = ref.read(checkoutControllerProvider.notifier);
    final analytics = ref.read(analyticsServiceProvider);
    final cart = ref.read(cartControllerProvider.notifier);
    try {
      final placed = await controller.place(
        addressId: address.id,
        date: delivery.date!,
        slotId: delivery.slot?.id,
        paymentMethod: method,
        promoCode: promoCode,
        useCredits: useCredits,
      );
      _placed = true;
      if (promoCode != null) ref.read(appliedPromoProvider.notifier).remove();
      // ZainCash orders are logged as a purchase once paid (payment screen).
      if (method != PaymentMethod.zainCash) {
        unawaited(analytics.log(AnalyticsEvents.purchase, {
          'currency': AppConstants.currencyCode,
          'value': placed.total,
          'transaction_id': placed.orderNumber.isEmpty ? placed.orderId : placed.orderNumber,
        }));
      }
      // placeOrder empties carts/{uid} server-side; clear the local view too.
      unawaited(cart.clear().catchError((Object _) {}));
      if (method == PaymentMethod.zainCash) {
        await _startOnlinePayment(placed, router, l10n);
        return;
      }
      router.go(AppRoutes.orderSuccessFor(placed.orderId));
    } on OrderFailure catch (failure) {
      if (!mounted) return;
      switch (failure.reason) {
        case OrderFailureReason.cartChanged:
          showOrderSnack(context, l10n.orderFailedCartChanged);
          _backToCart();
        case OrderFailureReason.outOfStock:
          showOrderSnack(context, l10n.orderFailedOutOfStock);
          _backToCart();
        case OrderFailureReason.emptyCart:
          showOrderSnack(context, l10n.orderFailedCartChanged);
          _backToCart();
        case OrderFailureReason.cityNotAllowed:
          showOrderSnack(context, l10n.orderFailedCity);
        case OrderFailureReason.minimumNotMet:
          showOrderSnack(context, l10n.minimumOrderNotMet(CurrencyFormatter.format(minOrder)));
        case OrderFailureReason.unavailable:
          showOrderSnack(context, l10n.orderFailedUnavailable);
        case OrderFailureReason.promoInvalid:
          ref.read(appliedPromoProvider.notifier).remove();
          showOrderSnack(context, l10n.orderFailedPromo);
        case OrderFailureReason.insufficientFunds:
          showOrderSnack(context, l10n.walletInsufficient);
        case OrderFailureReason.invalidChoice:
          showOrderSnack(context, l10n.orderFailedInvalidChoice);
        case OrderFailureReason.notCancellable || OrderFailureReason.network || OrderFailureReason.unknown:
          showOrderSnack(context, l10n.somethingWentWrong);
      }
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
    }
  }

  /// ZainCash (SRS §5.11): the order was created unpaid; start its gateway
  /// session, open ZainCash's page and wait on the payment status page. If the
  /// session can't start, the order stays payable until `paymentDueBy` — Order
  /// details has "Pay now".
  Future<void> _startOnlinePayment(PlacedOrder placed, GoRouter router, AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final payments = ref.read(paymentsRepositoryProvider);
    final opener = ref.read(externalLinkOpenerProvider);
    setState(() => _startingPayment = true);
    try {
      final session = await payments.startOrderPayment(placed.orderId);
      final opened = await openPaymentPage(opener, session.payUrl);
      router.go(AppRoutes.paymentFor(session.sessionId));
      if (!opened) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.paymentOpenFailed)));
      }
    } on PaymentFailure catch (f) {
      router.go(AppRoutes.order(placed.orderId));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${paymentFailureMessage(l10n, f.reason)} ${l10n.paymentOrderSaved}')));
    } finally {
      if (mounted) setState(() => _startingPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authStateProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final placing = ref.watch(checkoutControllerProvider.select((s) => s.placing));

    if (!auth.isLoading && !signedIn && !_guardStarted) {
      _guardStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_guard());
      });
    }

    Widget body;
    Widget? bottomBar;
    if (auth.isLoading) {
      body = const _CheckoutSkeleton();
    } else if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.shopping_bag_rounded);
    } else {
      final content = _content(context, l10n);
      body = content.$1;
      bottomBar = content.$2;
    }

    return PopScope(
      canPop: !placing && !_startingPayment,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppColors.bg(context),
            appBar: GGAppBar(title: l10n.checkout),
            body: body,
            bottomNavigationBar: bottomBar,
          ),
          if (placing || _startingPayment)
            PlacingOrderOverlay(message: _startingPayment ? l10n.paymentConnecting : null),
        ],
      ),
    );
  }

  (Widget, Widget?) _content(BuildContext context, AppLocalizations l10n) {
    final cart = ref.watch(cartControllerProvider);
    final summaryAsync = ref.watch(cartSummaryProvider);
    final productsAsync = ref.watch(cartProductsProvider);
    final settingsAsync = ref.watch(generalSettingsProvider);
    final citiesAsync = ref.watch(citiesProvider);
    final addressesAsync = ref.watch(addressesProvider);
    final payments = ref.watch(paymentSettingsProvider).valueOrNull ?? const PaymentSettings();
    final form = ref.watch(checkoutControllerProvider);
    final controller = ref.read(checkoutControllerProvider.notifier);

    void retry() {
      ref.invalidate(cartProductsProvider);
      ref.invalidate(citiesProvider);
      ref.invalidate(generalSettingsProvider);
      ref.invalidate(addressesProvider);
    }

    if (summaryAsync.hasError || citiesAsync.hasError || addressesAsync.hasError) {
      return (CenteredScroll(child: ErrorState(onRetry: retry)), null);
    }
    final summary = summaryAsync.valueOrNull;
    final cities = citiesAsync.valueOrNull;
    final addresses = addressesAsync.valueOrNull;
    if (cart.isLoading || summary == null || cities == null || addresses == null || settingsAsync.isLoading) {
      return (const _CheckoutSkeleton(), null);
    }
    if (!summary.canCheckout) {
      if (!_placed) WidgetsBinding.instance.addPostFrameCallback((_) => _backToCart());
      return (const _CheckoutSkeleton(), null);
    }
    _logBegin(summary);

    final settings = settingsAsync.valueOrNull ?? const GeneralSettings();
    final products = productsAsync.valueOrNull ?? const {};
    final now = ref.watch(checkoutClockProvider)();

    // (1) Address: the explicit pick (refreshed from the live list) or the default.
    final picked = form.address;
    final address = picked == null
        ? ref.watch(defaultAddressProvider)
        : (addresses.where((a) => a.id == picked.id).firstOrNull ?? picked);
    final cityCheck = address == null
        ? null
        : CityCheck.resolve(address: address, cities: cities, summary: summary, products: products);

    // (2) Date & slot.
    final delivery = DeliveryChoice.resolve(
      now: now,
      maxPreparationDays: summary.maxPreparationDays,
      settings: settings,
      selectedDate: form.date,
      selectedSlotId: form.slotId,
    );

    // (4) Payment.
    final methods = offeredPaymentMethods(payments);
    final usable = methods.where((m) => m.$2).map((m) => m.$1).toList();
    final method = usable.contains(form.paymentMethod) ? form.paymentMethod : usable.firstOrNull;

    // (5) Totals: promo (previewed with the shared rules; placeOrder re-checks),
    // then credits (toggle in the cart), then the wallet balance when "Wallet"
    // is the payment method (SRS §5.11, §5.18).
    final promo = ref.watch(promoEvaluationProvider).valueOrNull;
    final promoCode = promo != null && promo.$2.isValid ? promo.$1?.code : null;
    final wallet = ref.watch(walletProvider).valueOrNull;
    final useCredits = ref.watch(useCreditsProvider) && (wallet?.credits ?? 0) > 0;
    final totals = CheckoutRules.totals(
      subtotal: summary.subtotal,
      deliveryFee: cityCheck?.deliveryFee ?? 0,
      discount: promoCode == null ? 0 : promo!.$2.discount,
      credits: useCredits ? wallet!.credits : 0,
      wallet: method == PaymentMethod.wallet ? (wallet?.balance ?? 0) : 0,
    );
    final walletShort = method == PaymentMethod.wallet && totals.total > 0;
    // The gateway collects at least 1,000 IQD (placeOrder: invalid-argument otherwise).
    final gatewayShort = method == PaymentMethod.zainCash && totals.total < PaymentLimits.minGatewayAmount;
    final meetsMinimum = CheckoutRules.meetsMinimum(summary.subtotal, settings.minOrder);

    final canPlace = address != null &&
        (cityCheck?.ok ?? false) &&
        delivery.date != null &&
        (delivery.slots.isEmpty || delivery.slot != null) &&
        meetsMinimum &&
        method != null &&
        !walletShort &&
        !gatewayShort &&
        !summary.hasUnavailable &&
        !form.placing;

    final list = ListView(
      key: const ValueKey('checkout-list'),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, AppSpacing.lg),
      children: [
        _AddressSection(
          address: address,
          cityName: address == null ? '' : cityDisplayName(context, cities, address.city),
          blockedTitles: [
            for (final l in cityCheck?.blockedLines ?? const <CartLine>[]) l.item.titleSnapshot.of(context)
          ],
          onChange: _changeAddress,
          onAdd: _addAddress,
        ),
        const SizedBox(height: AppSpacing.md),
        CheckoutDeliverySection(
          choice: delivery,
          now: now,
          onDate: controller.selectDate,
          onSlot: (s) => controller.selectSlot(s.id),
        ),
        const SizedBox(height: AppSpacing.md),
        CheckoutGiftSection(
          isGift: form.isGift,
          hidePrices: form.hidePrices,
          messageController: _giftMessage,
          onGiftChanged: controller.setGift,
          onHidePricesChanged: controller.setHidePrices,
          onMessageChanged: controller.setGiftMessage,
        ),
        const SizedBox(height: AppSpacing.md),
        if (methods.isNotEmpty) ...[
          CheckoutPaymentSection(
            methods: methods,
            selected: method ?? form.paymentMethod,
            onChanged: controller.setPaymentMethod,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        CheckoutSummarySection(
          summary: summary,
          totals: totals,
          minimumMessage: meetsMinimum ? null : l10n.minimumOrderNotMet(CurrencyFormatter.format(settings.minOrder)),
        ),
        if (summary.hasUnavailable) ...[
          const SizedBox(height: AppSpacing.sm),
          CheckoutErrorLine(key: const ValueKey('remove-unavailable'), message: l10n.checkoutRemoveUnavailable),
        ],
        if (gatewayShort) ...[
          const SizedBox(height: AppSpacing.sm),
          CheckoutErrorLine(
            key: const ValueKey('gateway-minimum'),
            message: l10n.zainCashMinimum(CurrencyFormatter.format(PaymentLimits.minGatewayAmount)),
          ),
        ],
        if (walletShort) ...[
          const SizedBox(height: AppSpacing.sm),
          CheckoutErrorLine(key: const ValueKey('wallet-short'), message: l10n.walletInsufficient),
        ],
      ],
    );

    final bar = _PlaceOrderBar(
      total: totals.total,
      onPressed: canPlace
          ? () => _placeOrder(
                address: address,
                delivery: delivery,
                minOrder: settings.minOrder,
                method: method,
                promoCode: promoCode,
                useCredits: useCredits,
              )
          : null,
    );
    return (list, bar);
  }
}

/// Step 1 — delivery address (SRS §5.11, §4.3).
class _AddressSection extends StatelessWidget {
  const _AddressSection({
    required this.address,
    required this.cityName,
    required this.blockedTitles,
    required this.onChange,
    required this.onAdd,
  });

  final AddressModel? address;
  final String cityName;
  final List<String> blockedTitles;
  final VoidCallback onChange;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final a = address;
    return OrderSection(
      title: l10n.deliveryAddress,
      icon: Icons.local_shipping_outlined,
      trailing: a == null
          ? null
          : TextButton(
              key: const ValueKey('change-address'),
              onPressed: onChange,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.goldText(context),
                minimumSize: const Size.square(AppSpacing.minTapTarget),
              ),
              child: Text(l10n.changeAddress),
            ),
      child: a == null
          ? OutlineButton(
              key: const ValueKey('checkout-add-address'),
              label: l10n.addAddress,
              icon: Icons.add_location_alt_outlined,
              onPressed: onAdd,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AddressCard(address: a, cityName: cityName, outlined: false, showDefaultChip: false),
                for (final title in blockedTitles)
                  CheckoutErrorLine(
                    key: ValueKey('city-blocked-$title'),
                    message: l10n.itemNotDeliverableToCity(title),
                  ),
              ],
            ),
    );
  }
}

class _PlaceOrderBar extends StatelessWidget {
  const _PlaceOrderBar({required this.total, required this.onPressed});
  final int total;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        border: Border(top: BorderSide(color: AppColors.line(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, AppSpacing.sm + AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmountRow(label: l10n.total, amount: total, emphasized: true),
              const SizedBox(height: AppSpacing.xs),
              PrimaryButton(
                key: const ValueKey('place-order'),
                label: l10n.placeOrder,
                icon: Icons.check_circle_outline_rounded,
                onPressed: onPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutSkeleton extends StatelessWidget {
  const _CheckoutSkeleton();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
        child: Column(
          children: [
            SkeletonLoader.box(height: 120, radius: AppRadius.lg),
            SizedBox(height: AppSpacing.md),
            SkeletonLoader.box(height: 140, radius: AppRadius.lg),
            SizedBox(height: AppSpacing.md),
            SkeletonLoader.box(height: 100, radius: AppRadius.lg),
          ],
        ),
      );
}
