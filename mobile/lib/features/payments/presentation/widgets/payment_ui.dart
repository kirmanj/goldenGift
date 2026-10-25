import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../data/payments_repository.dart';
import '../providers/payment_providers.dart';

/// Shared bits of the online-payment UI (Checkout, Order Details, My Wallet,
/// the payment status page).

/// Localized text for a [PaymentFailureReason].
String paymentFailureMessage(AppLocalizations l10n, PaymentFailureReason reason) => switch (reason) {
      PaymentFailureReason.gatewayDisabled => l10n.paymentErrorDisabled,
      PaymentFailureReason.notPayable => l10n.paymentErrorNotPayable,
      PaymentFailureReason.alreadyPaid => l10n.paymentErrorAlreadyPaid,
      PaymentFailureReason.expired => l10n.paymentErrorExpired,
      PaymentFailureReason.unavailable => l10n.paymentErrorUnavailable,
      PaymentFailureReason.rateLimited => l10n.authErrorTooManyRequests,
      PaymentFailureReason.network => l10n.authErrorNetwork,
      PaymentFailureReason.unknown => l10n.somethingWentWrong,
    };

final _lri = String.fromCharCode(0x2066);
final _pdi = String.fromCharCode(0x2069);

/// "24:05" (minutes:seconds; hours first past an hour), isolated left-to-right
/// so it reads the same inside Arabic / Kurdish text.
String formatCountdown(Duration remaining) {
  final d = remaining.isNegative ? Duration.zero : remaining;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return '$_lri${h > 0 ? '$h:${two(m)}' : two(d.inMinutes)}:${two(s)}$_pdi';
}

/// Rebuilds [builder] with the time left until [deadline] on every tick of
/// [paymentClockProvider]; calls [onExpired] once when it reaches zero.
class PaymentCountdown extends ConsumerStatefulWidget {
  const PaymentCountdown({super.key, required this.deadline, required this.builder, this.onExpired});

  final DateTime deadline;
  final Widget Function(BuildContext context, Duration remaining) builder;
  final VoidCallback? onExpired;

  @override
  ConsumerState<PaymentCountdown> createState() => _PaymentCountdownState();
}

class _PaymentCountdownState extends ConsumerState<PaymentCountdown> {
  Timer? _timer;
  bool _expiredSent = false;

  @override
  void initState() {
    super.initState();
    final tick = ref.read(paymentClockProvider).tick;
    if (tick != null) {
      _timer = Timer.periodic(tick, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadline.difference(ref.watch(paymentClockProvider).now());
    if (remaining <= Duration.zero) {
      _timer?.cancel();
      if (!_expiredSent && widget.onExpired != null) {
        _expiredSent = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onExpired!();
        });
      }
    }
    return widget.builder(context, remaining.isNegative ? Duration.zero : remaining);
  }
}
