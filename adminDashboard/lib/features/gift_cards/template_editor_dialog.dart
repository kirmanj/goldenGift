import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/gift_card_model.dart';
import 'package:golden_gift/models/localized_text.dart';

import '../../core/session/admin_session.dart';
import '../../core/widgets/form_widgets.dart';
import 'data/gift_cards_admin_repository.dart';
import 'gift_card_ui.dart';

/// Create ([template] == null) or edit a gift-card template. Resolves to true when saved.
Future<bool> showTemplateEditor(BuildContext context, {GiftCardTemplateModel? template, required int nextSortOrder}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TemplateEditorDialog(template: template, nextSortOrder: nextSortOrder),
  );
  return saved ?? false;
}

/// Swatches offered for the gradient (brand golds, black, white tint, a few accents).
const templateSwatches = ['#9C7A14', '#C9A227', '#E3C04A', '#FBF4DC', '#1A1A1C', '#8E2C48', '#2F6FD3', '#2E9E5B'];

class TemplateEditorDialog extends ConsumerStatefulWidget {
  const TemplateEditorDialog({super.key, this.template, required this.nextSortOrder});
  final GiftCardTemplateModel? template;
  final int nextSortOrder;

  @override
  ConsumerState<TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends ConsumerState<TemplateEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final GiftCardTemplateModel? _original = widget.template;
  late final String _id = _original?.id ?? ref.read(giftCardsAdminRepositoryProvider).newTemplateId();
  late LocalizedText _name = _original?.name ?? LocalizedText.empty;
  late String? _artwork = _original?.artworkUrl;
  late final _start = TextEditingController(text: _original?.gradientStart ?? '');
  late final _end = TextEditingController(text: _original?.gradientEnd ?? '');
  late List<int> _presets = normalizePresetAmounts(_original?.presetAmounts ?? const []);
  final _presetInput = TextEditingController();
  late final _min = TextEditingController(text: '${_original?.minAmount ?? 0}');
  late final _max = TextEditingController(text: '${_original?.maxAmount ?? 0}');
  late final _sort = TextEditingController(text: '${_original?.sortOrder ?? widget.nextSortOrder}');
  late bool _active = _original?.isActive ?? true;
  bool _saving = false;
  List<String> _errors = const [];

  bool get _isNew => _original == null;

  @override
  void dispose() {
    for (final c in [_start, _end, _presetInput, _min, _max, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  GiftCardTemplateModel _build() => GiftCardTemplateModel(
        id: _id,
        name: _name,
        artworkUrl: (_artwork?.trim().isEmpty ?? true) ? null : _artwork!.trim(),
        gradientStart: normalizeHex(_start.text),
        gradientEnd: normalizeHex(_end.text),
        presetAmounts: _presets,
        minAmount: _int(_min),
        maxAmount: _int(_max),
        sortOrder: _int(_sort),
        isActive: _active,
      );

  void _addPreset() {
    final v = int.tryParse(_presetInput.text.trim());
    if (v == null || v <= 0) return;
    setState(() {
      _presets = normalizePresetAmounts([..._presets, v]);
      _presetInput.clear();
      if (_errors.isNotEmpty) _errors = validateTemplate(_build());
    });
  }

  Future<void> _save() async {
    final uid = ref.read(adminSessionProvider)?.uid ?? '';
    final fieldsOk = _form.currentState!.validate();
    final t = _build();
    final errors = validateTemplate(t);
    if (!fieldsOk || errors.isNotEmpty) {
      setState(() => _errors = errors.isEmpty ? const ['Fix the highlighted fields.'] : errors);
      return;
    }
    setState(() {
      _saving = true;
      _errors = const [];
    });
    try {
      final repo = ref.read(giftCardsAdminRepositoryProvider);
      if (_isNew) {
        await repo.createTemplate(t, adminUid: uid);
      } else {
        await repo.updateTemplate(_original!, t, adminUid: uid);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _errors = ['Could not save: $e']);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _hexField(String label, TextEditingController c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 220,
          child: TextFormField(
            key: ValueKey('hex:$label'),
            controller: c,
            decoration: InputDecoration(
              labelText: label,
              hintText: '#C9A227',
              prefixIcon: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: colorFromHex(normalizeHex(c.text)) ?? AppColors.field(context),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.line(context)),
                  ),
                ),
              ),
            ),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[#0-9A-Fa-f]')), LengthLimitingTextInputFormatter(7)],
            validator: (v) => (v ?? '').trim().isEmpty || isHexColor(normalizeHex(v)) ? null : '#RRGGBB',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(spacing: AppSpacing.xs, children: [
          for (final hex in templateSwatches)
            Tooltip(
              message: hex,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => c.text = hex),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: colorFromHex(hex),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: normalizeHex(c.text) == hex ? AppColors.gold(context) : AppColors.line(context),
                      width: normalizeHex(c.text) == hex ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _build();
    final muted = TextStyle(color: AppColors.textMuted(context));
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
                  child: Text(_isNew ? 'New gift card template' : 'Edit gift card template',
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
                  if (_errors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(_errors.map((e) => '• $e').join('\n'), style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  Center(
                    child: GiftCardPreview(
                      key: const ValueKey('templatePreview'),
                      name: preview.name.en,
                      amount: _presets.isNotEmpty ? _presets.first : (preview.allowsCustomAmount ? preview.minAmount : null),
                      gradientStart: isHexColor(preview.gradientStart) && isHexColor(preview.gradientEnd) ? preview.gradientStart : null,
                      gradientEnd: isHexColor(preview.gradientStart) && isHexColor(preview.gradientEnd) ? preview.gradientEnd : null,
                      artworkUrl: preview.artworkUrl,
                      code: 'XXXX-XXXX-XXXX',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TrilingualField(label: 'Name', value: _name, maxLength: 40, onChanged: (v) => setState(() => _name = v)),
                  const SizedBox(height: AppSpacing.sm),
                  ImageField(
                    label: 'Artwork',
                    value: _artwork,
                    storagePath: () => '${FirestorePaths.giftCardTemplates}/$_id.jpg',
                    onChanged: (v) => setState(() => _artwork = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Gradient', style: theme.textTheme.titleSmall),
                  Text('Leave both empty for the gold shimmer.', style: muted),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.md, crossAxisAlignment: WrapCrossAlignment.end, children: [
                    _hexField('Gradient start', _start),
                    _hexField('Gradient end', _end),
                    TextButton(
                      onPressed: () => setState(() {
                        _start.clear();
                        _end.clear();
                      }),
                      child: const Text('Use gold shimmer'),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  Text('Preset amounts', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final a in _presets)
                      InputChip(
                        label: Text(CurrencyFormatter.format(a)),
                        onDeleted: () => setState(() => _presets = [..._presets]..remove(a)),
                      ),
                    if (_presets.isEmpty) Text('None — customers type an amount.', style: muted),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  Row(children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        key: const ValueKey('presetInput'),
                        controller: _presetInput,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Add amount (IQD)'),
                        onSubmitted: (_) => _addPreset(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(onPressed: _addPreset, icon: const Icon(Icons.add), label: const Text('Add')),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  Text('Custom amount', style: theme.textTheme.titleSmall),
                  Text('Both 0 = customers can only pick a preset. Otherwise the minimum is at least 1,000 IQD.', style: muted),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, children: [
                    for (final (label, c) in [('Minimum (IQD)', _min), ('Maximum (IQD)', _max), ('Sort order', _sort)])
                      SizedBox(
                        width: 180,
                        child: TextFormField(
                          key: ValueKey('tpl:$label'),
                          controller: c,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: label),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text('Inactive templates are hidden from the shop; issued cards keep working.'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ]),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
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
}
