import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../checkout/presentation/widgets/checkout_options_sections.dart' show CheckoutErrorLine;
import '../../../gift_cards/presentation/screens/gift_card_designer_screen.dart' show parseAmountInput;
import '../../data/payments_repository.dart';
import '../providers/payment_providers.dart';
import 'payment_ui.dart';

/// My Wallet ▸ Top up (SRS §5.18): pick an amount (presets or 5,000–1,000,000
/// IQD) → `createPaymentSession {purpose: 'topUp'}` → ZainCash's page → the
/// payment status page, which says "Added X to your balance" once paid.
Future<void> startWalletTopUp(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final opener = ref.read(externalLinkOpenerProvider);
  final session = await showModalBottomSheet<PaymentSession>(
    context: context,
    backgroundColor: AppColors.card(context),
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const TopUpSheet(),
  );
  if (session == null) return;
  final opened = await openPaymentPage(opener, session.payUrl);
  if (!opened) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.paymentOpenFailed)));
  }
  unawaited(router.push(AppRoutes.paymentFor(session.sessionId)));
}

/// The amount picker; pops with the started [PaymentSession].
class TopUpSheet extends ConsumerStatefulWidget {
  const TopUpSheet({super.key});

  @override
  ConsumerState<TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<TopUpSheet> {
  final _custom = TextEditingController();
  int? _preset = PaymentLimits.topUpPresets.first;
  bool _isCustom = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  int? get _amount => _isCustom ? parseAmountInput(_custom.text) : _preset;

  Future<void> _continue() async {
    final l10n = AppLocalizations.of(context)!;
    final amount = _amount;
    if (!PaymentLimits.validTopUp(amount)) {
      setState(() => _error = l10n.topUpAmountRange(
            CurrencyFormatter.format(PaymentLimits.topUpMin),
            CurrencyFormatter.format(PaymentLimits.topUpMax),
          ));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref.read(paymentsRepositoryProvider).startTopUp(amount!);
      if (mounted) Navigator.of(context).pop(session);
    } on PaymentFailure catch (f) {
      if (mounted) setState(() => _error = paymentFailureMessage(l10n, f.reason));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final min = CurrencyFormatter.format(PaymentLimits.topUpMin);
    final max = CurrencyFormatter.format(PaymentLimits.topUpMax);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('top-up-sheet'),
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, 0, AppSpacing.screenHorizontal, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.topUpTitle,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.topUpBody,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final a in PaymentLimits.topUpPresets)
                    CategoryChip(
                      key: ValueKey('top-up-$a'),
                      label: CurrencyFormatter.format(a),
                      selected: !_isCustom && _preset == a,
                      onTap: _busy
                          ? null
                          : () => setState(() {
                                _isCustom = false;
                                _preset = a;
                                _error = null;
                              }),
                    ),
                  CategoryChip(
                    key: const ValueKey('top-up-custom'),
                    label: l10n.topUpOtherAmount,
                    icon: Icons.edit_outlined,
                    selected: _isCustom,
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _isCustom = true;
                              _error = null;
                            }),
                  ),
                ],
              ),
              if (_isCustom) ...[
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                GGInput(
                  key: const ValueKey('top-up-amount'),
                  hint: l10n.topUpAmountHint(min, max),
                  controller: _custom,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
                    LengthLimitingTextInputFormatter(9),
                  ],
                  suffix: Text(
                    AppConstants.currencyCode,
                    style: AppTextStyles.label.copyWith(color: AppColors.textMuted(context)),
                  ),
                  errorText: _error,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _continue(),
                ),
              ] else if (_error != null)
                CheckoutErrorLine(key: const ValueKey('top-up-error'), message: _error!),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                key: const ValueKey('top-up-continue'),
                label: l10n.topUpContinue,
                icon: Icons.smartphone_rounded,
                isLoading: _busy,
                onPressed: _busy ? null : _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
