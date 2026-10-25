import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/core/utils/promo_rules.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/promo_code_model.dart';

import '../../core/widgets/form_widgets.dart';
import '../banners/banner_editor_dialog.dart' show bannerDateFormat, pickDateTime;
import '../categories/categories_data.dart' show adminCategoriesProvider;
import '../orders/data/admin_orders_repository.dart' show orderStoreFilterProvider;
import 'data/promo_codes_data.dart';

/// Create ([promo] == null) or edit dialog. Resolves to true when saved.
Future<bool> showPromoEditor(BuildContext context, {PromoCodeModel? promo, required List<PromoCodeModel> all}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PromoEditorDialog(promo: promo, all: all),
  );
  return saved ?? false;
}

/// Every §6.9 field, plus a live preview through the shared [PromoRules] on
/// a sample cart so ops see exactly what the app and `placeOrder` will apply.
class PromoEditorDialog extends ConsumerStatefulWidget {
  const PromoEditorDialog({super.key, this.promo, required this.all});
  final PromoCodeModel? promo;

  /// Codes when the dialog opened (for the duplicate check).
  final List<PromoCodeModel> all;

  @override
  ConsumerState<PromoEditorDialog> createState() => _PromoEditorDialogState();
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class _PromoEditorDialogState extends ConsumerState<PromoEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final PromoCodeModel? _original = widget.promo;
  late final _code = TextEditingController(text: _original?.code ?? '');
  late LocalizedText _title = _original?.title ?? LocalizedText.empty;
  late LocalizedText _description = _original?.description ?? LocalizedText.empty;
  late PromoType _type = _original?.type ?? PromoType.percent;
  late int? _value = _original?.value;
  late int? _maxDiscount = _original?.maxDiscount;
  late int? _minOrder = _original?.minOrder;
  late int? _usageLimit = _original?.usageLimit;
  late int _perUserLimit = _original?.perUserLimit ?? 1;
  late bool _firstOrderOnly = _original?.firstOrderOnly ?? false;
  late final Set<String> _categoryIds = {...?_original?.categoryIds};
  late final Set<String> _storeIds = {...?_original?.storeIds};
  late bool _isPublic = _original?.isPublic ?? false;
  late bool _isActive = _original?.isActive ?? true;
  late DateTime? _expiresAt = _original?.expiresAt;

  // Preview cart.
  int? _sampleSubtotal = 50000;
  bool _sampleMatches = true;
  bool _sampleFirstOrder = true;

  bool _saving = false;
  String? _error;

  bool get _isNew => _original == null;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  PromoCodeModel _build() => PromoCodeModel(
        code: _isNew ? PromoCodeModel.normalize(_code.text) : _original!.code,
        title: _title,
        description: _description,
        type: _type,
        value: _value ?? 0,
        maxDiscount: _type == PromoType.percent ? _maxDiscount : null,
        minOrder: _minOrder,
        usageLimit: _usageLimit,
        usageCount: _original?.usageCount ?? 0,
        perUserLimit: _perUserLimit,
        firstOrderOnly: _firstOrderOnly,
        categoryIds: _categoryIds.toList()..sort(),
        storeIds: _storeIds.toList()..sort(),
        isPublic: _isPublic,
        isActive: _isActive,
        expiresAt: _expiresAt,
      );

  Iterable<String> get _taken => widget.all.map((p) => p.code);

  Future<void> _save() async {
    final formOk = _form.currentState!.validate();
    final model = _build();
    final errors = validatePromo(model, isNew: _isNew, now: DateTime.now(), takenCodes: _taken);
    if (!formOk || errors.isNotEmpty) {
      setState(() => _error = errors.isEmpty ? 'Fix the highlighted fields.' : errors.join('\n'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(promoAdminRepositoryProvider);
      if (_isNew) {
        await repo.create(model, takenCodes: _taken);
      } else {
        await repo.update(_original!, model);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickExpiry() async {
    final picked = await pickDateTime(context, _expiresAt,
        helpText: 'Expires at', defaultTime: const TimeOfDay(hour: 23, minute: 59));
    if (picked != null) setState(() => _expiresAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.textMuted(context);
    final categories = ref.watch(adminCategoriesProvider).valueOrNull ?? const [];
    final stores = ref.watch(orderStoreFilterProvider).valueOrNull ?? const [];
    final percent = _type == PromoType.percent;

    Widget gap() => const SizedBox(height: AppSpacing.md);

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, 0),
              child: Row(children: [
                Expanded(
                  child: Text(_isNew ? 'New promo code' : 'Edit ${_original!.code}',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    key: const ValueKey('promo-code'),
                    controller: _code,
                    enabled: _isNew,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                      LengthLimitingTextInputFormatter(20),
                      _UpperCase(),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Code *',
                      helperText: _isNew
                          ? 'Customers type this at checkout. A–Z, 0–9 and dashes, 3–20 characters; it cannot change later.'
                          : 'The code cannot change — orders refer to it.',
                    ),
                    validator: _isNew ? (v) => validatePromoCode(v, taken: _taken) : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  gap(),
                  TrilingualField(label: 'Title', value: _title, maxLength: 40, onChanged: (v) => setState(() => _title = v)),
                  TrilingualField(
                    label: 'Description',
                    value: _description,
                    required: false,
                    maxLines: 2,
                    maxLength: 160,
                    onChanged: (v) => setState(() => _description = v),
                  ),
                  Text('Discount', style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  SegmentedButton<PromoType>(
                    segments: const [
                      ButtonSegment(value: PromoType.percent, label: Text('Percent'), icon: Icon(Icons.percent)),
                      ButtonSegment(value: PromoType.fixed, label: Text('Fixed amount'), icon: Icon(Icons.payments_outlined)),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                  gap(),
                  _Grid(children: [
                    if (percent)
                      _IntField(
                        key: const ValueKey('promo-value-percent'),
                        label: 'Percent off *',
                        helper: '1–100',
                        value: _value,
                        onChanged: (v) => setState(() => _value = v),
                        validator: (v) => v == null ? 'Required' : (v < 1 || v > 100 ? 'Between 1 and 100' : null),
                      )
                    else
                      _IntField(
                        key: const ValueKey('promo-value-fixed'),
                        label: 'Amount off (IQD) *',
                        helper: 'At least ${CurrencyFormatter.format(minFixedDiscount)}',
                        value: _value,
                        onChanged: (v) => setState(() => _value = v),
                        validator: (v) => v == null
                            ? 'Required'
                            : (v < minFixedDiscount ? 'At least ${CurrencyFormatter.format(minFixedDiscount)}' : null),
                      ),
                    if (percent)
                      _IntField(
                        key: const ValueKey('promo-max-discount'),
                        label: 'Max discount (IQD)',
                        helper: 'Optional cap. Empty = no cap.',
                        value: _maxDiscount,
                        onChanged: (v) => setState(() => _maxDiscount = v),
                        validator: (v) => v != null && v <= 0 ? 'More than 0, or empty' : null,
                      ),
                    _IntField(
                      key: const ValueKey('promo-min-order'),
                      label: 'Minimum order (IQD)',
                      helper: 'Compared with the whole cart subtotal. Empty = none.',
                      value: _minOrder,
                      onChanged: (v) => setState(() => _minOrder = v),
                    ),
                    _IntField(
                      key: const ValueKey('promo-usage-limit'),
                      label: 'Total uses',
                      helper: _isNew
                          ? 'All customers together. Empty = unlimited.'
                          : 'Used ${_original!.usageCount} time(s) so far. Empty = unlimited.',
                      value: _usageLimit,
                      onChanged: (v) => setState(() => _usageLimit = v),
                      validator: (v) => v != null && v < 1 ? 'At least 1, or empty' : null,
                    ),
                    _IntField(
                      key: const ValueKey('promo-per-user'),
                      label: 'Uses per customer *',
                      helper: '0 = unlimited.',
                      value: _perUserLimit,
                      onChanged: (v) => setState(() => _perUserLimit = v ?? 0),
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                  ]),
                  gap(),
                  Row(children: [
                    Expanded(
                      child: Text(
                        _expiresAt == null ? 'Expires: not set *' : 'Expires: ${bannerDateFormat.format(_expiresAt!)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _expiresAt == null ? theme.colorScheme.error : null,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('promo-expiry'),
                      onPressed: _pickExpiry,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_expiresAt == null ? 'Pick date & time' : 'Change'),
                    ),
                  ]),
                  gap(),
                  Text('Applies to categories', style: theme.textTheme.labelLarge),
                  Text(_categoryIds.isEmpty ? 'No restriction — every category counts.' : 'Only lines in these categories are discounted.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
                    for (final c in categories)
                      FilterChip(
                        label: Text(c.title.en),
                        selected: _categoryIds.contains(c.id),
                        onSelected: (on) => setState(() => on ? _categoryIds.add(c.id) : _categoryIds.remove(c.id)),
                      ),
                    for (final id in _categoryIds.where((id) => !categories.any((c) => c.id == id)))
                      InputChip(label: Text('$id (missing)'), onDeleted: () => setState(() => _categoryIds.remove(id))),
                  ]),
                  gap(),
                  Text('Applies to stores', style: theme.textTheme.labelLarge),
                  Text(_storeIds.isEmpty ? 'No restriction — every store counts.' : 'Only lines from these stores are discounted.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
                    for (final s in stores)
                      FilterChip(
                        label: Text(s.name.en),
                        selected: _storeIds.contains(s.id),
                        onSelected: (on) => setState(() => on ? _storeIds.add(s.id) : _storeIds.remove(s.id)),
                      ),
                    for (final id in _storeIds.where((id) => !stores.any((s) => s.id == id)))
                      InputChip(label: Text('$id (missing)'), onDeleted: () => setState(() => _storeIds.remove(id))),
                  ]),
                  gap(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('First order only'),
                    subtitle: const Text('Only customers without a previous (non-cancelled) order.'),
                    value: _firstOrderOnly,
                    onChanged: (v) => setState(() => _firstOrderOnly = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Public'),
                    subtitle: const Text('Listed on the app\'s Promo Codes page. Private codes still work when typed.'),
                    value: _isPublic,
                    onChanged: (v) => setState(() => _isPublic = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text('Inactive codes are refused at checkout.'),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                  gap(),
                  _preview(context),
                ]),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(children: [
                Expanded(
                  child: _error == null ? const SizedBox.shrink() : Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
                TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_isNew ? 'Create' : 'Save'),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final model = _build();
    final subtotal = _sampleSubtotal ?? 0;
    final matches = !model.isRestricted || _sampleMatches;
    final result = PromoRules.evaluate(
      model,
      lines: [
        PromoLine(
          productId: 'sample',
          storeId: matches ? (model.storeIds.firstOrNull ?? 'sample-store') : '-',
          categoryIds: [matches ? (model.categoryIds.firstOrNull ?? 'sample-category') : '-'],
          lineTotal: subtotal,
        ),
      ],
      now: DateTime.now(),
      userOrderCount: _sampleFirstOrder ? 0 : 1,
    );
    final ok = result.isValid;
    final message = subtotal <= 0
        ? 'Type a sample cart subtotal to see the discount.'
        : ok
            ? 'Discount ${CurrencyFormatter.format(result.discount)} — the customer pays '
                '${CurrencyFormatter.format(subtotal - result.discount)} before delivery.'
            : 'Not applied: ${promoRejectionLabel(result.rejection!, model)}.';
    final color = subtotal <= 0 ? AppColors.textMuted(context) : (ok ? AppColors.success : AppColors.error);

    return SectionCard(title: 'Preview', children: [
      Text('Runs the same rules as checkout on a sample cart.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context))),
      const SizedBox(height: AppSpacing.sm),
      SizedBox(
        width: 280,
        child: MoneyField(
          key: const ValueKey('preview-subtotal'),
          label: 'Sample cart subtotal',
          value: _sampleSubtotal,
          required: false,
          onChanged: (v) => setState(() => _sampleSubtotal = v),
        ),
      ),
      if (model.isRestricted)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cart lines match the category / store restriction'),
          value: _sampleMatches,
          onChanged: (v) => setState(() => _sampleMatches = v),
        ),
      if (model.firstOrderOnly)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('This is the customer\'s first order'),
          value: _sampleFirstOrder,
          onChanged: (v) => setState(() => _sampleFirstOrder = v),
        ),
      const SizedBox(height: AppSpacing.xs),
      Text(message, key: const ValueKey('preview-result'), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    ]);
  }
}

/// Two columns when there is room.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final two = c.maxWidth >= 560;
        final width = two ? (c.maxWidth - AppSpacing.md) / 2 : c.maxWidth;
        return Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
          for (final child in children) SizedBox(width: width, child: child),
        ]);
      });
}

/// Whole non-negative number; empty = null.
class _IntField extends StatelessWidget {
  const _IntField({super.key, required this.label, required this.value, required this.onChanged, this.helper, this.validator});
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? helper;
  final String? Function(int?)? validator;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 2),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
        validator: validator == null ? null : (v) => validator!(v == null || v.isEmpty ? null : int.tryParse(v)),
        onChanged: (v) => onChanged(v.isEmpty ? null : int.tryParse(v)),
      );
}
