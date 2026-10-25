import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/wallet_model.dart';

import '../../core/widgets/form_widgets.dart';
import 'data/function_errors.dart';
import 'data/users_admin_repository.dart';

/// Opens the adjust-wallet dialog; resolves to the function's result when applied.
Future<WalletAdjustResult?> showWalletAdjustDialog(BuildContext context,
        {required String uid, required String userName, required WalletModel wallet}) =>
    showDialog<WalletAdjustResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WalletAdjustDialog(uid: uid, userName: userName, wallet: wallet),
    );

/// SRS §9 Users "adjust wallet or credits (with reason)": bucket, + / − amount,
/// reason, and a preview of the resulting amount. Negative results are refused
/// here; `adjustWallet` re-checks atomically and writes the transaction + audit.
class WalletAdjustDialog extends ConsumerStatefulWidget {
  const WalletAdjustDialog({super.key, required this.uid, required this.userName, required this.wallet});
  final String uid;
  final String userName;

  /// The wallet when the dialog opened (the live one is preferred once loaded).
  final WalletModel wallet;

  @override
  ConsumerState<WalletAdjustDialog> createState() => _WalletAdjustDialogState();
}

class _WalletAdjustDialogState extends ConsumerState<WalletAdjustDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  WalletBucket _bucket = WalletBucket.balance;
  bool _deduct = false;
  int? _amount;
  bool _saving = false;
  List<String> _errors = const [];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  WalletModel get _wallet => ref.watch(adminWalletProvider(widget.uid)).valueOrNull ?? widget.wallet;

  WalletAdjustment get _adjustment => WalletAdjustment(
        uid: widget.uid,
        bucket: _bucket,
        amount: (_amount ?? 0) * (_deduct ? -1 : 1),
        reason: _reason.text,
        requestId: _requestIds.putIfAbsent(
            '${_bucket.name}|${(_amount ?? 0) * (_deduct ? -1 : 1)}|${_reason.text.trim()}', () => const Uuid().v4()),
      );

  /// One idempotency key per distinct adjustment typed in this dialog, so
  /// re-submitting the same one after an error can't apply it twice.
  final _requestIds = <String, String>{};

  Future<void> _apply() async {
    final wallet = ref.read(adminWalletProvider(widget.uid)).valueOrNull ?? widget.wallet;
    final formOk = _form.currentState!.validate();
    final a = _adjustment;
    final errors = a.validate(wallet);
    if (!formOk || errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _errors = const [];
    });
    try {
      final result = await ref.read(usersAdminRepositoryProvider).adjustWallet(a, current: wallet);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      final message = switch (e) {
        WalletAdjustmentInvalid(:final errors) => errors.join('\n'),
        _ when functionErrorReason(e) == 'insufficient_funds' =>
          'Insufficient funds: the ${bucketLabel(a.bucket).toLowerCase()} would go below zero. '
              'It may have changed since this dialog opened — check the amounts and try again.',
        _ => functionErrorMessage('adjustWallet', e, action: 'adjust the wallet'),
      };
      setState(() => _errors = [message]);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallet = _wallet;
    final a = _adjustment;
    final now = _bucket == WalletBucket.balance ? wallet.balance : wallet.credits;
    final after = a.resultFor(wallet);
    final negative = after < 0;

    return AlertDialog(
      title: Text('Adjust wallet — ${widget.userName}'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Bucket', style: theme.textTheme.labelLarge),
              RadioGroup<WalletBucket>(
                groupValue: _bucket,
                onChanged: (v) => setState(() => _bucket = v ?? _bucket),
                child: Column(children: [
                  RadioListTile<WalletBucket>(
                    value: WalletBucket.balance,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Balance — real money (${CurrencyFormatter.format(wallet.balance)})'),
                  ),
                  RadioListTile<WalletBucket>(
                    value: WalletBucket.credits,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Credits — promotional (${CurrencyFormatter.format(wallet.credits)})'),
                  ),
                ]),
              ),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Add'), icon: Icon(Icons.add)),
                  ButtonSegment(value: true, label: Text('Deduct'), icon: Icon(Icons.remove)),
                ],
                selected: {_deduct},
                onSelectionChanged: (s) => setState(() => _deduct = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              MoneyField(
                key: const ValueKey('adjust-amount'),
                label: 'Amount',
                value: _amount,
                onChanged: (v) => setState(() => _amount = v),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('adjust-reason'),
                controller: _reason,
                maxLength: WalletAdjustment.reasonMax,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  helperText: 'Kept on the transaction and in the audit log; not shown to the customer.',
                ),
                validator: (v) => (v?.trim().length ?? 0) < WalletAdjustment.reasonMin ? 'At least 3 characters' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                key: const ValueKey('adjust-preview'),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: (negative ? AppColors.error : AppColors.gold(context)).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${bucketLabel(_bucket)}: ${CurrencyFormatter.format(now)} → ${CurrencyFormatter.format(after)}'
                  '${negative ? '  (below zero — not allowed)' : ''}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: negative ? AppColors.error : null),
                ),
              ),
              if (_errors.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                for (final e in _errors) Text(e, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || negative ? null : _apply,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Apply adjustment'),
        ),
      ],
    );
  }
}
