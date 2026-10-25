import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../profile/presentation/providers/profile_platform_providers.dart' show ExternalLinkOpener;
export '../../../profile/presentation/providers/profile_platform_providers.dart' show externalLinkOpenerProvider;

/// "Now" and how often the payment countdowns refresh (SRS §5.11: 30 minutes
/// to pay a ZainCash order). Tests pin [now] and switch the ticker off
/// ([tick] null) so `pumpAndSettle` can settle.
class PaymentClock {
  const PaymentClock({this.now = DateTime.now, this.tick = const Duration(seconds: 1)});
  final DateTime Function() now;
  final Duration? tick;
}

final paymentClockProvider = Provider<PaymentClock>((ref) => const PaymentClock());

/// Opens the gateway's pay page in the browser (outside the app, so the
/// gateway's `goldengift://payment?…` link brings the customer back). Only
/// http(s) URLs are opened. False when nothing could open it. Pass
/// `ref.read(externalLinkOpenerProvider)` (a seam the tests replace).
Future<bool> openPaymentPage(ExternalLinkOpener open, String? payUrl) async {
  final uri = Uri.tryParse(payUrl ?? '');
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) return false;
  try {
    return await open(uri);
  } catch (_) {
    return false;
  }
}
