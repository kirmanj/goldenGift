import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/gift_card_model.dart';

import '../../core/session/admin_session.dart';
import '../../core/widgets/form_widgets.dart';
import '../stores/data/callable_errors.dart';
import '../stores/data/phone_input.dart';
import 'data/gift_cards_admin_repository.dart';
import 'gift_card_ui.dart';

/// "Manual issue" (SRS §9 Gift cards) → `adminIssueGiftCard`; shows the new
/// code with a copy button.
Future<void> showIssueGiftCardDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const IssueGiftCardDialog(),
    );

class IssueGiftCardDialog extends ConsumerStatefulWidget {
  const IssueGiftCardDialog({super.key, this.now});

  /// Clock for tests.
  final DateTime? now;

  @override
  ConsumerState<IssueGiftCardDialog> createState() => _IssueGiftCardDialogState();
}

class _IssueGiftCardDialogState extends ConsumerState<IssueGiftCardDialog> {
  final _form = GlobalKey<FormState>();
  String? _templateId;
  final _amount = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();
  late DateTime _expiresAt = ManualGiftCardIssue.defaultExpiry(_now);
  bool _override = false;
  bool _sending = false;
  List<String> _errors = const [];
  IssuedGiftCard? _issued;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void dispose() {
    for (final c in [_amount, _name, _phone, _email, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  ManualGiftCardIssue _build() => ManualGiftCardIssue(
        templateId: _templateId ?? '',
        amount: int.tryParse(_amount.text.trim()) ?? 0,
        recipientName: _name.text,
        recipientPhone: _phone.text,
        recipientEmail: _email.text,
        message: _message.text,
        expiresAt: _expiresAt,
      );

  void _pickTemplate(GiftCardTemplateModel? t) => setState(() {
        _templateId = t?.id;
        if (t != null && (int.tryParse(_amount.text) == null || !t.accepts(int.parse(_amount.text)))) {
          _amount.text = t.presetAmounts.isNotEmpty ? '${t.presetAmounts.first}' : (t.allowsCustomAmount ? '${t.minAmount}' : '');
        }
      });

  Future<void> _submit(List<GiftCardTemplateModel> templates) async {
    final session = ref.read(adminSessionProvider);
    if (session == null) return;
    final fieldsOk = _form.currentState!.validate();
    final request = _build();
    final template = templates.where((t) => t.id == _templateId).firstOrNull;
    final errors = request.validate(
      template: template,
      overrideAmount: _override && GiftCardsAccess.canOverrideAmount(session.role),
      now: _now,
    );
    if (!fieldsOk || errors.isNotEmpty) {
      setState(() => _errors = errors.isEmpty ? const ['Fix the highlighted fields.'] : errors);
      return;
    }
    setState(() {
      _sending = true;
      _errors = const [];
    });
    try {
      final issued = await ref.read(giftCardsAdminRepositoryProvider).issue(request);
      if (mounted) setState(() => _issued = issued);
    } catch (e) {
      if (mounted) setState(() => _errors = [callableErrorMessage('adminIssueGiftCard', e, action: 'issue the card')]);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt,
      firstDate: _now.add(const Duration(days: 1)),
      lastDate: DateTime(_now.year + 5),
      helpText: 'Expires on',
    );
    if (picked != null) setState(() => _expiresAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issued = _issued;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: issued != null ? _result(context, issued) : _formBody(context, theme),
      ),
    );
  }

  Widget _result(BuildContext context, IssuedGiftCard issued) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, size: 48, color: AppColors.success),
          const SizedBox(height: AppSpacing.md),
          Text('Gift card issued', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          Text('Give this code to ${_name.text.trim()} (it was also sent to the contact you entered).',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted(context))),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(color: AppColors.soft(context), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SelectableText(issued.formattedCode,
                  key: const ValueKey('issuedCode'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: AppColors.goldText(context),
                    fontFamily: 'monospace',
                  )),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Copy code',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: issued.formattedCode));
                  showMessage(context, 'Code copied');
                },
                icon: const Icon(Icons.copy),
              ),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ]),
      );

  Widget _formBody(BuildContext context, ThemeData theme) {
    final session = ref.watch(adminSessionProvider);
    final canOverride = session != null && GiftCardsAccess.canOverrideAmount(session.role);
    final templates = ref.watch(adminGiftCardTemplatesProvider).valueOrNull ?? const <GiftCardTemplateModel>[];
    final template = templates.where((t) => t.id == _templateId).firstOrNull;
    final muted = TextStyle(color: AppColors.textMuted(context));
    return Form(
      key: _form,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, 0),
          child: Row(children: [
            Expanded(
              child: Text('Issue a gift card', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_errors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(_errors.map((e) => '• $e').join('\n'), style: TextStyle(color: theme.colorScheme.error)),
                ),
              DropdownButtonFormField<String>(
                key: const ValueKey('issueTemplate'),
                initialValue: _templateId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Template *'),
                items: [
                  for (final t in templates)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(t.isActive ? t.name.en : '${t.name.en} (inactive)', overflow: TextOverflow.ellipsis),
                    ),
                ],
                validator: (v) => v == null ? 'Required' : null,
                onChanged: (id) => _pickTemplate(templates.where((t) => t.id == id).firstOrNull),
              ),
              if (template != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(templateAmountsLabel(template), style: muted),
              ],
              const SizedBox(height: AppSpacing.md),
              if (template != null && template.presetAmounts.isNotEmpty) ...[
                Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                  for (final a in template.presetAmounts)
                    ChoiceChip(
                      label: Text(CurrencyFormatter.format(a)),
                      selected: _amount.text == '$a',
                      onSelected: (_) => setState(() => _amount.text = '$a'),
                    ),
                ]),
                const SizedBox(height: AppSpacing.sm),
              ],
              TextFormField(
                key: const ValueKey('issueAmount'),
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Amount (IQD) *'),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Required' : null,
                onChanged: (_) => setState(() {}),
              ),
              if (canOverride)
                CheckboxListTile(
                  key: const ValueKey('issueOverride'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _override,
                  onChanged: (v) => setState(() => _override = v ?? false),
                  title: const Text('Allow an amount this template does not offer (super admin)'),
                ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('issueName'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Recipient name *'),
                validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, children: [
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    key: const ValueKey('issuePhone'),
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Recipient phone', helperText: 'SMS with the code'),
                    validator: (v) => validateStaffPhone(v),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    key: const ValueKey('issueEmail'),
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Recipient email'),
                    validator: validateStaffEmail,
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const ValueKey('issueMessage'),
                controller: _message,
                maxLength: GiftCardRules.maxMessage,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: 'Message (optional)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                Text('Expires on ${AppDates.display(_expiresAt)}', key: const ValueKey('issueExpiry')),
                const SizedBox(width: AppSpacing.sm),
                TextButton(onPressed: _pickExpiry, child: const Text('Change')),
              ]),
              if (template != null) ...[
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: GiftCardPreview(
                    name: template.name.en,
                    amount: int.tryParse(_amount.text),
                    gradientStart: template.gradientStart,
                    gradientEnd: template.gradientEnd,
                    artworkUrl: template.artworkUrl,
                    width: 260,
                  ),
                ),
              ],
            ]),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: _sending ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: _sending ? null : () => _submit(templates),
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Issue card'),
            ),
          ]),
        ),
      ]),
    );
  }
}
