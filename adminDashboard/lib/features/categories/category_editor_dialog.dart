import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/form_widgets.dart';
import 'categories_data.dart';
import 'categories_screen.dart' show CategoryStatusMenu;
import 'slug.dart';

/// Create ([category] == null) or edit dialog. Resolves to true when saved.
Future<bool> showCategoryEditor(BuildContext context, {CategoryModel? category, required List<CategoryModel> all}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CategoryEditorDialog(category: category, all: all),
  );
  return saved ?? false;
}

class CategoryEditorDialog extends ConsumerStatefulWidget {
  const CategoryEditorDialog({super.key, this.category, required this.all});

  final CategoryModel? category;

  /// The list when the dialog opened (the live list is preferred once loaded).
  final List<CategoryModel> all;

  @override
  ConsumerState<CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends ConsumerState<CategoryEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final CategoryModel? _original = widget.category;
  late LocalizedText _title = _original?.title ?? LocalizedText.empty;
  late final _id = TextEditingController(text: _original?.id ?? '');
  bool _idEdited = false;
  late String? _iconUrl = _original?.iconUrl;
  late CategoryType _type = _original?.type ?? CategoryType.productType;
  late CategoryStatus _status = _original?.status ?? CategoryStatus.available;
  late LocalizedText _note = _original?.comingSoonNote ?? LocalizedText.empty;
  late bool _isSeasonal = _original?.isSeasonal ?? false;
  late DateTime? _from = _original?.activeFrom;
  late DateTime? _to = _original?.activeTo;
  late String? _parentId = _original?.parentId;
  bool _submitted = false;
  bool _saving = false;
  String? _error;

  bool get _isNew => _original == null;
  String get _currentId => _isNew ? _id.text.trim() : _original!.id;

  static final _dateFormat = DateFormat('d MMM yyyy', 'en_US');

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  List<CategoryModel> get _all => ref.watch(adminCategoriesProvider).valueOrNull ?? widget.all;

  CategoryModel _build() => CategoryModel(
        id: _currentId,
        title: _title,
        iconUrl: _iconUrl,
        type: _type,
        sortOrder: _original?.sortOrder ?? 0,
        isActive: _status != CategoryStatus.hidden,
        comingSoon: _status == CategoryStatus.comingSoon,
        comingSoonNote: _status == CategoryStatus.comingSoon ? _note : LocalizedText.empty,
        comingSoonSince: _original?.comingSoonSince,
        isSeasonal: _isSeasonal,
        activeFrom: _isSeasonal && _from != null ? startOfDay(_from!) : null,
        activeTo: _isSeasonal && _to != null ? endOfDay(_to!) : null,
        parentId: _parentId,
        productCount: _original?.productCount ?? 0,
      );

  Future<void> _save() async {
    final all = ref.read(adminCategoriesProvider).valueOrNull ?? widget.all;
    setState(() => _submitted = true);
    final formOk = _form.currentState!.validate();
    final model = _build();
    final errors = validateCategory(model, existing: all, isNew: _isNew);
    if (!formOk || errors.isNotEmpty) {
      setState(() => _error = errors.isEmpty ? 'Fix the highlighted fields.' : errors.join('\n'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(categoryAdminRepositoryProvider);
      if (_isNew) {
        await repo.create(model, existing: all);
      } else {
        await repo.update(_original!, model, existing: all);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final current = from ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (from ? DateTime.now() : (_from ?? DateTime.now())),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: from ? 'Active from' : 'Active to',
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final theme = Theme.of(context);
    final excluded = {if (!_isNew) _original!.id, if (!_isNew) ...descendantsOf(_original!.id, all)};
    final parentOptions = all.where((c) => !excluded.contains(c.id)).toList();
    final seasonError = validateSeasonWindow(isSeasonal: _isSeasonal, from: _from, to: _to);
    final showSeasonError = seasonError != null && (_submitted || (_from != null && _to != null));

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, 0),
                child: Row(children: [
                  Expanded(
                    child: Text(_isNew ? 'New category' : 'Edit category',
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
                    TrilingualField(
                      label: 'Title',
                      value: _title,
                      maxLength: 40,
                      onChanged: (v) => setState(() {
                        _title = v;
                        if (_isNew && !_idEdited) _id.text = slugify(v.en);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const ValueKey('category-id'),
                      controller: _id,
                      enabled: _isNew,
                      decoration: InputDecoration(
                        labelText: 'Id *',
                        helperText: _isNew
                            ? 'Made from the English title. Lowercase letters, digits and dashes; it cannot change later.'
                            : 'The id cannot change — products refer to it.',
                      ),
                      validator: _isNew ? (v) => validateSlugId(v, takenIds: all.map((c) => c.id)) : null,
                      onChanged: (_) => setState(() => _idEdited = true),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SegmentedButton<CategoryType>(
                          segments: const [
                            ButtonSegment(
                                value: CategoryType.occasion,
                                label: Text('Occasion'),
                                icon: Icon(Icons.celebration_outlined)),
                            ButtonSegment(
                                value: CategoryType.productType,
                                label: Text('Product type'),
                                icon: Icon(Icons.inventory_2_outlined)),
                          ],
                          selected: {_type},
                          onSelectionChanged: (s) => setState(() => _type = s.first),
                        ),
                        SizedBox(
                          width: 300,
                          child: DropdownButtonFormField<String?>(
                            initialValue: _parentId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Parent category (optional)'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('None — top level')),
                              for (final c in parentOptions)
                                DropdownMenuItem<String?>(value: c.id, child: Text(c.title.en, overflow: TextOverflow.ellipsis)),
                              if (_parentId != null && !parentOptions.any((c) => c.id == _parentId))
                                DropdownMenuItem<String?>(value: _parentId, child: Text('$_parentId (missing)')),
                            ],
                            onChanged: (v) => setState(() => _parentId = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ImageField(
                      label: 'Icon',
                      value: _iconUrl,
                      storagePath: () => 'categories/${_currentId.isEmpty ? 'unnamed' : _currentId}.png',
                      onChanged: (v) => _iconUrl = v,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Status', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<CategoryStatus>(
                      key: const ValueKey('category-status'),
                      segments: [
                        for (final s in CategoryStatus.values)
                          ButtonSegment(value: s, label: Text(s.label), icon: Icon(CategoryStatusMenu.iconOf(s))),
                      ],
                      selected: {_status},
                      onSelectionChanged: (s) => setState(() => _status = s.first),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _status.description,
                      key: const ValueKey('category-status-hint'),
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context)),
                    ),
                    if (_status == CategoryStatus.comingSoon) ...[
                      const SizedBox(height: AppSpacing.md),
                      TrilingualField(
                        key: const ValueKey('coming-soon-note'),
                        label: 'Coming-soon note (optional)',
                        value: _note,
                        required: false,
                        maxLength: CategoryModel.comingSoonNoteMaxLength,
                        onChanged: (v) => setState(() => _note = v),
                      ),
                      Text(
                        'Shown under the message on the coming-soon page, e.g. "Arriving before Ramadan". '
                        'Cleared when the category leaves Coming soon.',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context)),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Seasonal'),
                      subtitle: const Text('Shown only between the dates below, e.g. Mother\'s Day.'),
                      value: _isSeasonal,
                      onChanged: (v) => setState(() => _isSeasonal = v),
                    ),
                    if (_isSeasonal) ...[
                      Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, children: [
                        OutlinedButton.icon(
                          onPressed: () => _pickDate(from: true),
                          icon: const Icon(Icons.event_outlined),
                          label: Text('Active from: ${_from == null ? 'pick a date' : _dateFormat.format(_from!)}'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _pickDate(from: false),
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text('Active to: ${_to == null ? 'pick a date' : _dateFormat.format(_to!)}'),
                        ),
                      ]),
                      if (showSeasonError)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(seasonError, style: TextStyle(color: theme.colorScheme.error)),
                        ),
                    ],
                  ]),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    child: _error == null
                        ? const SizedBox.shrink()
                        : Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
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
            ],
          ),
        ),
      ),
    );
  }
}
