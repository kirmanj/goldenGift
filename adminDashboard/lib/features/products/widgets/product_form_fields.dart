import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import '../data/products_admin_repository.dart' show giftAudienceLabel;
import '../domain/product_draft.dart';

/// Whole number, empty = null (e.g. stock: empty = unlimited). [signed]
/// allows a leading minus (price deltas).
class IntField extends StatelessWidget {
  const IntField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.signed = false,
    this.helperText,
    this.hintText,
    this.validator,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool signed;
  final String? helperText;
  final String? hintText;
  final String? Function(int? value)? validator;

  static int? parse(String? text) {
    final t = text?.trim() ?? '';
    return (t.isEmpty || t == '-') ? null : int.tryParse(t);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: InputDecoration(labelText: label, helperText: helperText, hintText: hintText),
        keyboardType: TextInputType.numberWithOptions(signed: signed),
        inputFormatters: [
          signed ? FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')) : FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(signed ? 10 : 9),
        ],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validator == null ? null : (v) => validator!(parse(v)),
        onChanged: (v) => onChanged(parse(v)),
      );
}

Color? colorFromHex(String? hex) {
  final h = hex?.trim() ?? '';
  if (!hexColorPattern.hasMatch(h)) return null;
  return Color(0xFF000000 | int.parse(h.substring(1), radix: 16));
}

String hexFromColor(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// `#RRGGBB` text field + live swatch + colour-picker dialog.
class HexColorField extends StatefulWidget {
  const HexColorField({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<HexColorField> {
  late final _controller = TextEditingController(text: widget.value ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(String text) {
    setState(() {});
    widget.onChanged(text.trim().isEmpty ? null : text.trim().toUpperCase());
  }

  Future<void> _pick() async {
    var picked = colorFromHex(_controller.text) ?? Theme.of(context).colorScheme.primary;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a colour'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Use colour')),
        ],
      ),
    );
    if (ok != true) return;
    _controller.text = hexFromColor(picked);
    _set(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final colour = colorFromHex(_controller.text);
    final scheme = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            // The swatch preview is the one place a literal colour is shown.
            color: colour ?? scheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: colour == null ? Icon(Icons.question_mark, size: 16, color: scheme.onSurfaceVariant) : null,
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      SizedBox(
        width: 130,
        child: TextFormField(
          controller: _controller,
          decoration: const InputDecoration(labelText: 'Hex *', hintText: '#C9A227'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
            LengthLimitingTextInputFormatter(7),
          ],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) => hexColorPattern.hasMatch(v?.trim() ?? '') ? null : 'Use #RRGGBB',
          onChanged: _set,
        ),
      ),
      IconButton(tooltip: 'Pick colour', icon: const Icon(Icons.palette_outlined), onPressed: _pick),
    ]);
  }
}

/// Free-form tags as chips (they feed `searchKeywords`).
class TagsField extends StatefulWidget {
  const TagsField({super.key, required this.tags, required this.onChanged});
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  State<TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends State<TagsField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final next = [...widget.tags];
    for (final raw in _controller.text.split(',')) {
      final tag = raw.trim();
      if (tag.isNotEmpty && !next.any((t) => t.toLowerCase() == tag.toLowerCase())) next.add(tag);
    }
    _controller.clear();
    if (next.length != widget.tags.length) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Tags',
            helperText: 'Enter or comma to add; used for search',
            suffixIcon: IconButton(tooltip: 'Add tag', icon: const Icon(Icons.add), onPressed: _add),
          ),
          onSubmitted: (_) => _add(),
          onChanged: (v) {
            if (v.contains(',')) _add();
          },
        ),
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
            for (final tag in widget.tags)
              InputChip(
                label: Text(tag),
                onDeleted: () => widget.onChanged([...widget.tags.where((t) => t != tag)]),
              ),
          ]),
        ],
      ]);
}

/// Multi-select as filter chips. Selected ids missing from [options] (e.g. a
/// deleted category) are still shown so they can be removed.
class ChipMultiSelect extends StatelessWidget {
  const ChipMultiSelect({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.dimmed = const {},
  });

  /// id → label, in display order.
  final Map<String, String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  /// Ids shown greyed (inactive categories / cities); still selectable.
  final Set<String> dimmed;

  @override
  Widget build(BuildContext context) {
    final unknown = selected.where((id) => !options.containsKey(id));
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
      for (final e in options.entries)
        FilterChip(
          label: Text(e.value, style: dimmed.contains(e.key) ? TextStyle(color: muted) : null),
          selected: selected.contains(e.key),
          onSelected: (on) => onChanged(on ? [...selected, e.key] : [...selected.where((id) => id != e.key)]),
        ),
      for (final id in unknown)
        FilterChip(
          label: Text('$id (missing)'),
          selected: true,
          onSelected: (_) => onChanged([...selected.where((s) => s != id)]),
        ),
    ]);
  }
}

/// Required "Gift for" multi-select (SRS §5.8a): For him / For her / For
/// companies, at least one. A [FormField], so the editor's form validation
/// shows the error under the chips like the other required fields.
class GiftForField extends StatelessWidget {
  const GiftForField({super.key, required this.selected, required this.onChanged});
  final List<GiftAudience> selected;
  final void Function(GiftAudience audience, bool selected) onChanged;

  @override
  Widget build(BuildContext context) => FormField<List<GiftAudience>>(
        initialValue: List.of(selected),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) => (v ?? const []).isEmpty ? 'Choose at least one' : null,
        builder: (field) {
          final theme = Theme.of(context);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Gift for *', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
              for (final a in GiftAudience.values)
                FilterChip(
                  key: ValueKey('giftFor-${a.name}'),
                  label: Text(giftAudienceLabel(a)),
                  selected: selected.contains(a),
                  onSelected: (on) {
                    onChanged(a, on);
                    field.didChange([
                      for (final x in GiftAudience.values)
                        if (x == a ? on : selected.contains(x)) x,
                    ]);
                  },
                ),
            ]),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(field.errorText!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
          ]);
        },
      );
}
