import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/secret_santa_model.dart';
import '../../../auth/presentation/widgets/auth_messages.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/secret_santa_repository.dart';
import '../providers/secret_santa_providers.dart';

/// "Create group" (SRS §5.16): your name, group name, type, budget (presets
/// or custom) and an exchange date from tomorrow on. Resolves to the new
/// group's id, null when dismissed.
Future<String?> showSecretSantaCreateSheet(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card(context),
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => const SecretSantaCreateSheet(),
    );

class SecretSantaCreateSheet extends ConsumerStatefulWidget {
  const SecretSantaCreateSheet({super.key});

  static const maxName = 60;

  @override
  ConsumerState<SecretSantaCreateSheet> createState() => _SecretSantaCreateSheetState();
}

enum _Field { yourName, name, budget, date }

class _SecretSantaCreateSheetState extends ConsumerState<SecretSantaCreateSheet> {
  final _yourName = TextEditingController();
  final _name = TextEditingController();
  final _customBudget = TextEditingController();
  final _dateText = TextEditingController();
  SecretSantaType _type = SecretSantaType.friends;

  /// A preset amount, or null for "Custom".
  int? _budget = 25000;
  DateTime? _date;
  bool _saving = false;
  Map<_Field, String?> _errors = const {};

  @override
  void initState() {
    super.initState();
    _yourName.text = _profileName();
    // The profile may still be loading: fill the name once it arrives,
    // unless the customer already typed one.
    ref.listenManual(currentUserProfileProvider, (_, next) {
      final name = next.valueOrNull?.name.trim() ?? '';
      if (name.isNotEmpty && _yourName.text.trim().isEmpty) _yourName.text = name;
    });
  }

  @override
  void dispose() {
    for (final c in [_yourName, _name, _customBudget, _dateText]) {
      c.dispose();
    }
    super.dispose();
  }

  String _profileName() {
    try {
      final name = ref.read(currentUserProfileProvider).valueOrNull?.name.trim() ?? '';
      if (name.isNotEmpty) return name;
    } catch (_) {
      // No profile available (e.g. not loaded): fall back to the auth name.
    }
    return ref.read(authStateProvider).valueOrNull?.displayName?.trim() ?? '';
  }

  String? _profilePhone() {
    try {
      final phone = ref.read(currentUserProfileProvider).valueOrNull?.phone.trim() ?? '';
      return phone.isEmpty ? null : phone;
    } catch (_) {
      return null;
    }
  }

  DateTime get _tomorrow {
    final now = ref.read(secretSantaClockProvider)();
    return DateTime(now.year, now.month, now.day + 1);
  }

  int get _amount => _budget ?? int.tryParse(_customBudget.text.trim()) ?? 0;

  Future<void> _pickDate() async {
    final first = _tomorrow;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date != null && !_date!.isBefore(first) ? _date! : first,
      firstDate: first,
      lastDate: DateTime(first.year + 2, first.month, first.day),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: AppLocalizations.of(context)!.secretSantaExchangeDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _dateText.text = AppDates.display(picked);
      _errors = {..._errors, _Field.date: null};
    });
  }

  Map<_Field, String?> _validate(AppLocalizations l10n) => {
        _Field.yourName: l10n.validation(Validators.name(_yourName.text)),
        _Field.name: _name.text.trim().isEmpty ? l10n.errorRequired : null,
        _Field.budget: _budget == null && _amount <= 0 ? l10n.secretSantaBudgetError : null,
        _Field.date: _date == null
            ? l10n.errorRequired
            : (_date!.isBefore(_tomorrow) ? l10n.secretSantaDateError : null),
      };

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    final errors = _validate(l10n);
    setState(() => _errors = errors);
    if (errors.values.any((e) => e != null)) return;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      final id = await ref.read(secretSantaRepositoryProvider).create(
            uid: uid,
            organiserName: _yourName.text,
            organiserPhone: _profilePhone(),
            name: _name.text,
            type: _type,
            budget: _amount,
            exchangeDate: _date!,
          );
      navigator.pop(id);
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clear(_Field f) {
    if (_errors[f] != null) setState(() => _errors = {..._errors, f: null});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const gap = SizedBox(height: AppSpacing.md);
    TextStyle label() => AppTextStyles.label.copyWith(color: AppColors.text(context));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const ValueKey('santa-create-form'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, 0, AppSpacing.screenHorizontal, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.secretSantaCreateGroup,
                style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
              ),
            ),
            gap,
            GGInput(
              key: const ValueKey('santa-your-name'),
              label: l10n.yourName,
              hint: l10n.enterYourName,
              controller: _yourName,
              errorText: _errors[_Field.yourName],
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              onChanged: (_) => _clear(_Field.yourName),
            ),
            gap,
            GGInput(
              key: const ValueKey('santa-group-name'),
              label: l10n.secretSantaGroupName,
              hint: l10n.secretSantaGroupNameHint,
              controller: _name,
              maxLength: SecretSantaCreateSheet.maxName,
              errorText: _errors[_Field.name],
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _clear(_Field.name),
            ),
            gap,
            Text(l10n.secretSantaType, style: label()),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final type in SecretSantaType.values)
                  CategoryChip(
                    key: ValueKey('santa-type-${type.name}'),
                    label: secretSantaTypeLabel(l10n, type),
                    icon: secretSantaTypeIcon(type),
                    selected: _type == type,
                    onTap: () => setState(() => _type = type),
                  ),
              ],
            ),
            gap,
            Text(l10n.secretSantaBudget, style: label()),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final amount in secretSantaBudgetPresets)
                  CategoryChip(
                    key: ValueKey('santa-budget-$amount'),
                    label: CurrencyFormatter.format(amount),
                    selected: _budget == amount,
                    onTap: () => setState(() {
                      _budget = amount;
                      _errors = {..._errors, _Field.budget: null};
                    }),
                  ),
                CategoryChip(
                  key: const ValueKey('santa-budget-custom'),
                  label: l10n.secretSantaCustomBudget,
                  icon: Icons.edit_outlined,
                  selected: _budget == null,
                  onTap: () => setState(() => _budget = null),
                ),
              ],
            ),
            if (_budget == null) ...[
              const SizedBox(height: AppSpacing.sm),
              GGInput(
                key: const ValueKey('santa-budget-amount'),
                hint: l10n.secretSantaCustomBudgetHint,
                controller: _customBudget,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                errorText: _errors[_Field.budget],
                suffix: Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                  child: Text('IQD', style: AppTextStyles.label.copyWith(color: AppColors.textMuted(context))),
                ),
                onChanged: (_) => _clear(_Field.budget),
              ),
            ],
            gap,
            GGInput(
              key: const ValueKey('santa-date'),
              label: l10n.secretSantaExchangeDate,
              hint: l10n.selectADate,
              controller: _dateText,
              readOnly: true,
              onTap: _pickDate,
              errorText: _errors[_Field.date],
              suffix: Icon(Icons.event_outlined, color: AppColors.gold(context)),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              key: const ValueKey('santa-create'),
              label: l10n.secretSantaCreateGroup,
              isLoading: _saving,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}
