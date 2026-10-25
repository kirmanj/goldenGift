import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/address_model.dart';
import '../../../../models/app_settings_model.dart';
import '../../../../models/special_request_model.dart';
import '../../../../models/wallet_model.dart';
import '../../../addresses/data/address_repository.dart';
import '../../../addresses/presentation/widgets/address_card.dart';
import '../../../checkout/presentation/providers/checkout_providers.dart';
import '../../../checkout/presentation/widgets/checkout_delivery_section.dart';
import '../../../checkout/presentation/widgets/checkout_options_sections.dart';
import '../../../orders/data/orders_repository.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../wallet/data/wallet_repository.dart';
import '../../data/special_requests_repository.dart';

/// Accept a quote (SRS §5.17): delivery address (default + change), date &
/// slot, payment (cash on delivery, or the wallet balance when it covers the
/// total) → `acceptQuote` creates the order. One clientRequestId per visit.
class AcceptQuoteScreen extends ConsumerStatefulWidget {
  const AcceptQuoteScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<AcceptQuoteScreen> createState() => _AcceptQuoteScreenState();
}

class _AcceptQuoteScreenState extends ConsumerState<AcceptQuoteScreen> {
  final String _clientRequestId = const Uuid().v4();
  AddressModel? _address;
  DateTime? _date;
  String? _slotId;
  PaymentMethod _method = PaymentMethod.cashOnDelivery;
  bool _placing = false;

  Future<void> _changeAddress() async {
    final picked = await context.push<AddressModel>('${AppRoutes.addresses}?select=1');
    if (picked != null && mounted) setState(() => _address = picked);
  }

  Future<void> _addAddress() async {
    final saved = await context.push<AddressModel>(AppRoutes.addressForm);
    if (saved != null && mounted) setState(() => _address = saved);
  }

  Future<void> _confirm({
    required AddressModel address,
    required DeliveryChoice delivery,
    required PaymentMethod method,
  }) async {
    if (_placing) return;
    final l10n = AppLocalizations.of(context)!;
    final router = GoRouter.of(context);
    setState(() => _placing = true);
    try {
      final placed = await ref.read(specialRequestsRepositoryProvider).acceptQuote(AcceptQuoteRequest(
            requestId: widget.requestId,
            clientRequestId: _clientRequestId,
            addressId: address.id,
            deliveryDate: delivery.date!,
            deliverySlot: delivery.slot?.id,
            paymentMethod: method,
          ));
      router.go(AppRoutes.orderSuccessFor(placed.orderId));
    } on OrderFailure catch (failure) {
      if (!mounted) return;
      showOrderSnack(context, switch (failure.reason) {
        OrderFailureReason.cityNotAllowed => l10n.orderFailedCity,
        OrderFailureReason.unavailable => l10n.orderFailedUnavailable,
        OrderFailureReason.insufficientFunds => l10n.walletInsufficient,
        _ => l10n.somethingWentWrong,
      });
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final auth = ref.watch(authStateProvider);

    Widget body;
    Widget? bar;
    if (auth.isLoading) {
      body = const _Skeleton();
    } else if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.request_quote_outlined);
    } else {
      final async = ref.watch(specialRequestProvider(widget.requestId));
      final addresses = ref.watch(addressesProvider);
      final cities = ref.watch(citiesProvider);
      final settings = ref.watch(generalSettingsProvider);
      if ((async.hasError && !async.hasValue) || addresses.hasError || cities.hasError) {
        body = CenteredScroll(
          child: ErrorState(onRetry: () {
            ref.invalidate(specialRequestProvider(widget.requestId));
            ref.invalidate(addressesProvider);
            ref.invalidate(citiesProvider);
          }),
        );
      } else if (!async.hasValue || !addresses.hasValue || !cities.hasValue || settings.isLoading) {
        body = const _Skeleton();
      } else {
        final request = async.requireValue;
        if (request == null || !request.canAcceptQuote) {
          body = CenteredScroll(
            child: EmptyState(
              key: const ValueKey('quote-not-acceptable'),
              title: l10n.srQuoteUnavailable,
              icon: Icons.request_quote_outlined,
              ctaLabel: l10n.srBackToRequest,
              onCta: () => context.go(AppRoutes.specialRequest(widget.requestId)),
            ),
          );
        } else {
          final content = _content(
            context,
            l10n,
            request,
            addresses.requireValue,
            cities.requireValue,
            settings.valueOrNull ?? const GeneralSettings(),
          );
          body = content.$1;
          bar = content.$2;
        }
      }
    }

    return PopScope(
      canPop: !_placing,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppColors.bg(context),
            appBar: GGAppBar(title: l10n.srAcceptQuote),
            body: body,
            bottomNavigationBar: bar,
          ),
          if (_placing) const PlacingOrderOverlay(),
        ],
      ),
    );
  }

  (Widget, Widget) _content(
    BuildContext context,
    AppLocalizations l10n,
    SpecialRequestModel request,
    List<AddressModel> addresses,
    List<CityModel> cities,
    GeneralSettings settings,
  ) {
    final now = ref.watch(checkoutClockProvider)();
    final payments = ref.watch(paymentSettingsProvider).valueOrNull ?? const PaymentSettings();
    final wallet = ref.watch(walletProvider).valueOrNull ?? WalletModel.empty;

    final picked = _address;
    final address = picked == null
        ? ref.watch(defaultAddressProvider)
        : (addresses.where((a) => a.id == picked.id).firstOrNull ?? picked);
    final city = address == null ? null : cities.where((c) => c.id == address.city && c.isActive).firstOrNull;
    final cityOk = address != null && city != null;

    final delivery = DeliveryChoice.resolve(
      now: now,
      maxPreparationDays: 0,
      settings: settings,
      selectedDate: _date,
      selectedSlotId: _slotId,
    );

    final quote = request.quoteAmount ?? 0;
    final fee = city?.deliveryFee ?? 0;
    final total = quote + fee;
    final walletCovers = wallet.balance >= total;
    final methods = [
      if (payments.cashOnDelivery) (PaymentMethod.cashOnDelivery, true),
      if (payments.wallet) (PaymentMethod.wallet, walletCovers),
    ];
    final usable = methods.where((m) => m.$2).map((m) => m.$1).toList();
    final method = usable.contains(_method) ? _method : usable.firstOrNull;

    final canConfirm = cityOk &&
        delivery.date != null &&
        (delivery.slots.isEmpty || delivery.slot != null) &&
        method != null &&
        !_placing;

    final list = ListView(
      key: const ValueKey('accept-quote-list'),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, AppSpacing.lg),
      children: [
        OrderSection(
          title: l10n.srQuoteTitle,
          icon: Icons.request_quote_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                request.text.trim().split('\n').first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
              ),
              if ((request.quoteNote ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(request.quoteNote!.trim(), style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text(context))),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OrderSection(
          title: l10n.deliveryAddress,
          icon: Icons.local_shipping_outlined,
          trailing: address == null
              ? null
              : TextButton(
                  key: const ValueKey('change-address'),
                  onPressed: _changeAddress,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.goldText(context),
                    minimumSize: const Size.square(AppSpacing.minTapTarget),
                  ),
                  child: Text(l10n.changeAddress),
                ),
          child: address == null
              ? OutlineButton(
                  key: const ValueKey('quote-add-address'),
                  label: l10n.addAddress,
                  icon: Icons.add_location_alt_outlined,
                  onPressed: _addAddress,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AddressCard(
                      key: ValueKey('quote-address-${address.id}'),
                      address: address,
                      cityName: cityDisplayName(context, cities, address.city),
                      outlined: false,
                      showDefaultChip: false,
                    ),
                    if (!cityOk) CheckoutErrorLine(key: const ValueKey('quote-city-error'), message: l10n.srCityNotServed),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        CheckoutDeliverySection(
          choice: delivery,
          now: now,
          onDate: (d) => setState(() {
            _date = d;
            _slotId = null;
          }),
          onSlot: (s) => setState(() => _slotId = s.id),
        ),
        const SizedBox(height: AppSpacing.md),
        if (methods.isNotEmpty) ...[
          CheckoutPaymentSection(
            methods: methods,
            selected: method ?? _method,
            onChanged: (m) => setState(() => _method = m),
          ),
          if (payments.wallet && !walletCovers)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.md, top: AppSpacing.xs),
              child: Text(
                l10n.srWalletShort(CurrencyFormatter.format(wallet.balance)),
                key: const ValueKey('quote-wallet-short'),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
        OrderSection(
          title: l10n.orderSummary,
          icon: Icons.receipt_long_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmountRow(label: l10n.srQuoteRow, amount: quote),
              AmountRow(label: l10n.deliveryFee, amount: fee),
              const Divider(),
              AmountRow(label: l10n.total, amount: total, emphasized: true),
            ],
          ),
        ),
      ],
    );

    final bar = Container(
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
                key: const ValueKey('confirm-quote'),
                label: l10n.srConfirmOrder,
                icon: Icons.check_circle_outline_rounded,
                onPressed: canConfirm ? () => _confirm(address: address, delivery: delivery, method: method) : null,
              ),
            ],
          ),
        ),
      ),
    );
    return (list, bar);
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
        child: Column(
          children: [
            SkeletonLoader.box(height: 100, radius: AppRadius.lg),
            SizedBox(height: AppSpacing.md),
            SkeletonLoader.box(height: 140, radius: AppRadius.lg),
            SizedBox(height: AppSpacing.md),
            SkeletonLoader.box(height: 100, radius: AppRadius.lg),
          ],
        ),
      );
}
