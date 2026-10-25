import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/order_model.dart';
import '../../../cart/presentation/providers/cart_controller.dart';
import '../../../orders/data/orders_repository.dart';
import '../../../orders/presentation/providers/order_reorder.dart';
import '../../../orders/presentation/widgets/order_card.dart' show popOrGo;
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/payments_repository.dart';
import '../providers/payment_providers.dart';
import '../widgets/payment_ui.dart';

/// What the payment status page shows.
enum PaymentView {
  loading,

  /// No such session (or not the customer's).
  missing,

  /// Pending, before its expiry: pay on the gateway's page.
  waiting,

  /// Pending past its expiry: `expirePaymentSessions` checks with the gateway.
  timeUp,

  /// Order paid → Order Success.
  orderPaid,

  /// Top-up credited to the wallet balance.
  toppedUp,

  /// Paid, but the order no longer waited for it: the amount went to the wallet.
  paidToWallet,
  failed,
  expired,
}

/// The truth is `payment_sessions/{id}` and — for an order — the order itself
/// (paid by another session, or already cancelled); the deep link's `status`
/// is only a hint (SRS §7 `zainCashReturn`).
PaymentView paymentViewFor(PaymentSessionModel? session, OrderModel? order, DateTime now) {
  if (session == null) return PaymentView.missing;
  switch (session.status) {
    case PaymentSessionStatus.paid:
      if (session.purpose == PaymentPurpose.topUp) return PaymentView.toppedUp;
      return session.creditedToWallet ? PaymentView.paidToWallet : PaymentView.orderPaid;
    case PaymentSessionStatus.failed:
      return PaymentView.failed;
    case PaymentSessionStatus.expired:
      return PaymentView.expired;
    case PaymentSessionStatus.pending:
      if (session.purpose == PaymentPurpose.order && order != null) {
        if (order.paymentStatus == PaymentStatus.paid) return PaymentView.orderPaid;
        if (order.status.tab == OrderTab.cancelled) {
          return order.cancelReason == 'payment_expired' ? PaymentView.expired : PaymentView.failed;
        }
      }
      final expiresAt = session.expiresAt;
      return expiresAt != null && !now.isBefore(expiresAt) ? PaymentView.timeUp : PaymentView.waiting;
  }
}

/// Payment status (SRS §5.11, §5.18): shown while the customer pays a ZainCash
/// order or top-up on the gateway's page, and opened by the gateway's
/// `goldengift://payment?sid=…` link. Live on the session (+ order): amount,
/// time left, Open ZainCash again / I've paid — check status / Cancel; paid →
/// Order Success (or "Added X to your balance"); failed / expired → what
/// happened and Try again.
class PaymentStatusScreen extends ConsumerStatefulWidget {
  const PaymentStatusScreen({super.key, required this.sessionId, this.statusHint});

  final String sessionId;

  /// `status` from the deep link (paid | failed | pending | expired | error) —
  /// a hint only, never trusted.
  final String? statusHint;

  @override
  ConsumerState<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends ConsumerState<PaymentStatusScreen> {
  bool _leftForSuccess = false;
  bool _checking = false;
  bool _busy = false;

  PaymentSessionModel? get _session => ref.read(paymentSessionProvider(widget.sessionId)).valueOrNull;

  /// Order details for an order, My Wallet for a top-up.
  String _fallback(PaymentSessionModel? s) {
    if (s?.purpose == PaymentPurpose.topUp) return AppRoutes.wallet;
    final orderId = s?.orderId;
    return orderId == null ? AppRoutes.orders : AppRoutes.order(orderId);
  }

  /// Back / Cancel: nothing is cancelled — an unpaid session simply expires.
  void _leave() => popOrGo(context, _fallback(_session));

  Future<void> _openAgain(String? payUrl) async {
    final l10n = AppLocalizations.of(context)!;
    final opened = await openPaymentPage(ref.read(externalLinkOpenerProvider), payUrl);
    if (!opened && mounted) showOrderSnack(context, l10n.paymentOpenFailed);
  }

  /// "I've paid — check status": asks the gateway through the server (which
  /// settles a payment whose redirect never arrived), then re-reads the
  /// session and order. A missing / unavailable check just falls back to the re-read.
  Future<void> _checkStatus() async {
    final l10n = AppLocalizations.of(context)!;
    final orderId = _session?.orderId;
    setState(() => _checking = true);
    try {
      await ref.read(paymentsRepositoryProvider).checkStatus(widget.sessionId);
    } on PaymentFailure catch (f) {
      if (f.reason == PaymentFailureReason.rateLimited && mounted) {
        showOrderSnack(context, paymentFailureMessage(l10n, f.reason));
      }
    }
    if (!mounted) return;
    ref.invalidate(paymentSessionProvider(widget.sessionId));
    if (orderId != null) ref.invalidate(orderByIdProvider(orderId));
    try {
      final s = await ref.read(paymentSessionProvider(widget.sessionId).future);
      if (!mounted) return;
      final order = orderId == null ? null : ref.read(orderByIdProvider(orderId)).valueOrNull;
      final view = paymentViewFor(s, order, ref.read(paymentClockProvider).now());
      if (view == PaymentView.waiting || view == PaymentView.timeUp) showOrderSnack(context, l10n.paymentStillPending);
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Failed / expired: pay the order again while it still waits; otherwise put
  /// its lines back in the cart. A top-up goes back to My Wallet.
  Future<void> _tryAgain(PaymentSessionModel session, OrderModel? order) async {
    final l10n = AppLocalizations.of(context)!;
    final router = GoRouter.of(context);
    if (session.purpose == PaymentPurpose.topUp) {
      popOrGo(context, AppRoutes.wallet);
      return;
    }
    setState(() => _busy = true);
    try {
      if (order != null && orderAwaitsOnlinePayment(order, ref.read(paymentClockProvider).now())) {
        final next = await ref.read(paymentsRepositoryProvider).startOrderPayment(order.id);
        final opened = await openPaymentPage(ref.read(externalLinkOpenerProvider), next.payUrl);
        if (!mounted) return;
        if (!opened) showOrderSnack(context, l10n.paymentOpenFailed);
        unawaited(router.pushReplacement(AppRoutes.paymentFor(next.sessionId)));
        return;
      }
      if (order != null && order.orderType == OrderType.standard && order.items.isNotEmpty) {
        await addOrderLinesToCart(ref.read(cartControllerProvider.notifier), order);
      }
      router.go(AppRoutes.mainTab(1));
    } on PaymentFailure catch (f) {
      if (mounted) showOrderSnack(context, paymentFailureMessage(l10n, f.reason));
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToSuccess(String orderId) {
    if (_leftForSuccess) return;
    _leftForSuccess = true;
    // Online orders count as a purchase once paid (cash orders when placed).
    final order = ref.read(orderByIdProvider(orderId)).valueOrNull;
    if (order != null) {
      unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.purchase, {
        'currency': AppConstants.currencyCode,
        'value': order.total,
        'transaction_id': order.orderNumber.isEmpty ? order.id : order.orderNumber,
        'payment_type': order.paymentMethod.name,
      }));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(AppRoutes.orderSuccessFor(orderId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authStateProvider);
    final signedIn = ref.watch(isSignedInProvider);

    Widget body;
    if (auth.isLoading) {
      body = const _Checking();
    } else if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.account_balance_wallet_outlined);
    } else {
      body = _content(context, l10n);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: GGAppBar(title: l10n.paymentInfo, showBack: true, onBack: _leave),
        body: body,
      ),
    );
  }

  Widget _content(BuildContext context, AppLocalizations l10n) {
    final sessionAsync = ref.watch(paymentSessionProvider(widget.sessionId));
    if (sessionAsync.isLoading && !sessionAsync.hasValue) return const _Checking();
    final session = sessionAsync.valueOrNull;
    final orderId = session?.orderId;
    final orderAsync = orderId == null ? null : ref.watch(orderByIdProvider(orderId));
    final order = orderAsync?.valueOrNull;
    // Keeps the cart started, so "Try again" writes to the account's cart.
    final cartReady = !ref.watch(cartControllerProvider.select((s) => s.isLoading));
    final now = ref.watch(paymentClockProvider).now();

    if (sessionAsync.hasError) {
      return CenteredScroll(child: ErrorState(onRetry: () => ref.invalidate(paymentSessionProvider(widget.sessionId))));
    }
    // The order decides "paid elsewhere / cancelled" — wait for it.
    if (orderAsync != null && orderAsync.isLoading && !orderAsync.hasValue) return const _Checking();

    final view = paymentViewFor(session, order, now);
    if (session == null || view == PaymentView.missing) {
      return CenteredScroll(
        child: EmptyState(
          key: const ValueKey('payment-missing'),
          icon: Icons.receipt_long_rounded,
          title: l10n.paymentNotFound,
          ctaLabel: l10n.orders,
          onCta: () => context.go(AppRoutes.orders),
        ),
      );
    }
    if (view == PaymentView.orderPaid && orderId != null) {
      _goToSuccess(orderId);
      return const _Checking();
    }

    final number = session.orderNumber ?? order?.orderNumber ?? '';
    final isTopUp = session.purpose == PaymentPurpose.topUp;
    final amount = CurrencyFormatter.format(session.amount);
    final orderStillPayable = order != null && orderAwaitsOnlinePayment(order, now);
    const gap = SizedBox(height: AppSpacing.sm + AppSpacing.xs);

    final (_StatusTone tone, IconData icon, String title, String text) = switch (view) {
      PaymentView.waiting => (_StatusTone.gold, Icons.hourglass_top_rounded, l10n.paymentWaitingTitle, l10n.paymentWaitingBody),
      PaymentView.timeUp => (_StatusTone.gold, Icons.hourglass_bottom_rounded, l10n.paymentWaitingTitle, l10n.paymentTimeUp),
      PaymentView.toppedUp => (_StatusTone.success, Icons.check_rounded, l10n.topUpSuccessTitle, l10n.topUpSuccessBody(amount)),
      PaymentView.paidToWallet => (
          _StatusTone.success,
          Icons.account_balance_wallet_rounded,
          l10n.paymentLateCreditedTitle,
          l10n.paymentLateCreditedBody(amount),
        ),
      PaymentView.failed || PaymentView.expired => (
          _StatusTone.error,
          view == PaymentView.failed ? Icons.close_rounded : Icons.timer_off_rounded,
          view == PaymentView.failed ? l10n.paymentFailedTitle : l10n.paymentExpiredTitle,
          isTopUp || orderStillPayable || number.isEmpty ? l10n.paymentNothingCharged : l10n.paymentOrderCancelledBody(number),
        ),
      _ => (_StatusTone.gold, Icons.hourglass_top_rounded, l10n.paymentChecking, ''),
    };

    final pending = view == PaymentView.waiting || view == PaymentView.timeUp;
    final actions = <Widget>[
      if (view == PaymentView.waiting && session.payUrl != null) ...[
        PrimaryButton(
          key: const ValueKey('payment-open-again'),
          label: l10n.paymentOpenAgain,
          icon: Icons.open_in_new_rounded,
          onPressed: () => _openAgain(session.payUrl),
        ),
        gap,
      ],
      if (pending) ...[
        OutlineButton(
          key: const ValueKey('payment-check-status'),
          label: l10n.paymentCheckStatus,
          icon: Icons.refresh_rounded,
          isLoading: _checking,
          onPressed: _checking ? null : _checkStatus,
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton(
            key: const ValueKey('payment-cancel'),
            onPressed: _leave,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted(context),
              minimumSize: const Size(88, 48),
            ),
            child: Text(l10n.cancel, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
      if (view == PaymentView.toppedUp)
        PrimaryButton(
          key: const ValueKey('payment-back-to-wallet'),
          label: l10n.backToWallet,
          icon: Icons.account_balance_wallet_outlined,
          onPressed: () => popOrGo(context, AppRoutes.wallet),
        ),
      if (view == PaymentView.paidToWallet) ...[
        PrimaryButton(
          key: const ValueKey('payment-my-wallet'),
          label: l10n.myWallet,
          icon: Icons.account_balance_wallet_outlined,
          onPressed: () => context.go(AppRoutes.wallet),
        ),
        gap,
      ],
      if (view == PaymentView.failed || view == PaymentView.expired) ...[
        PrimaryButton(
          key: const ValueKey('payment-try-again'),
          label: l10n.paymentTryAgain,
          icon: Icons.replay_rounded,
          isLoading: _busy,
          onPressed: _busy || (!isTopUp && !cartReady) ? null : () => _tryAgain(session, order),
        ),
        if (!isTopUp) gap,
      ],
      if (!isTopUp && orderId != null && (view == PaymentView.failed || view == PaymentView.expired || view == PaymentView.paidToWallet))
        OutlineButton(
          key: const ValueKey('payment-order-details'),
          label: l10n.orderDetails,
          icon: Icons.receipt_long_outlined,
          onPressed: _busy ? null : () => context.go(AppRoutes.order(orderId)),
        ),
    ];

    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    return ListView(
      key: const ValueKey('payment-status-list'),
      padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.lg, AppSpacing.screenHorizontal, bottom),
      children: [
        Center(child: _StatusIllustration(tone: tone, icon: icon)),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            title,
            key: ValueKey('payment-view-${view.name}'),
            textAlign: TextAlign.center,
            style: AppTextStyles.heading2.copyWith(color: AppColors.text(context)),
          ),
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context)),
          ),
        ],
        if (pending) ...[
          const SizedBox(height: AppSpacing.lg),
          _AmountCard(
            amount: session.amount,
            subtitle: isTopUp ? l10n.paymentForTopUp : (number.isEmpty ? null : l10n.orderNumber(number)),
            deadline: view == PaymentView.waiting ? session.expiresAt : null,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        ...actions,
      ],
    );
  }
}

enum _StatusTone { gold, success, error }

class _StatusIllustration extends StatelessWidget {
  const _StatusIllustration({required this.tone, required this.icon});
  final _StatusTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final type = tone == _StatusTone.success ? InfoBannerType.success : InfoBannerType.error;
    final inner = switch (tone) {
      _StatusTone.gold => const BoxDecoration(gradient: AppColors.headerGradient, shape: BoxShape.circle),
      _StatusTone.success => const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
      _StatusTone.error => const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
    };
    return ExcludeSemantics(
      child: Container(
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          color: tone == _StatusTone.gold ? AppColors.soft(context) : InfoBanner.softColor(context, type),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: inner,
            child: Icon(
              icon,
              size: 44,
              color: tone == _StatusTone.gold ? AppColors.textOnPrimary : AppColors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Amount to pay · 75,000 IQD · Order GG-… · Time left to pay 24:05".
class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.amount, this.subtitle, this.deadline});
  final int amount;
  final String? subtitle;
  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final due = deadline;
    return OrderSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.paymentAmountToPay, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium.copyWith(color: muted)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CurrencyFormatter.format(amount),
            key: const ValueKey('payment-amount'),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: AppTextStyles.heading1.copyWith(fontWeight: FontWeight.w800, color: AppColors.goldText(context)),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle!, textAlign: TextAlign.center, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
          ],
          if (due != null) ...[
            Divider(height: AppSpacing.lg, color: AppColors.line(context)),
            PaymentCountdown(
              deadline: due,
              builder: (context, remaining) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: AppColors.gold(context)),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      l10n.paymentTimeLeft(formatCountdown(remaining)),
                      key: const ValueKey('payment-time-left'),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CenteredScroll(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 36,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.gold(context)),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.paymentChecking,
                key: const ValueKey('payment-checking'),
                textAlign: TextAlign.center,
                style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
