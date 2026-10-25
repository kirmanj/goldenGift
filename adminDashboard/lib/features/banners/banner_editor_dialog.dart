import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/banner_model.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/form_widgets.dart';
import '../categories/categories_data.dart';
import 'banner_widgets.dart';
import 'banners_data.dart';

/// Create ([banner] == null) or edit dialog. Resolves to true when saved.
Future<bool> showBannerEditor(BuildContext context,
    {BannerModel? banner, BannerPlacement? placement, required List<BannerModel> all}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BannerEditorDialog(banner: banner, initialPlacement: placement, all: all),
  );
  return saved ?? false;
}

final bannerDateFormat = DateFormat('d MMM yyyy, HH:mm', 'en_US');

/// Date then 24-hour time, local. [defaultTime] is offered when nothing is set yet.
Future<DateTime?> pickDateTime(BuildContext context, DateTime? initial,
    {String? helpText, TimeOfDay defaultTime = const TimeOfDay(hour: 0, minute: 0)}) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    helpText: helpText,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: initial == null ? defaultTime : TimeOfDay.fromDateTime(initial),
    builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class BannerEditorDialog extends ConsumerStatefulWidget {
  const BannerEditorDialog({super.key, this.banner, this.initialPlacement, required this.all});

  final BannerModel? banner;
  final BannerPlacement? initialPlacement;
  final List<BannerModel> all;

  @override
  ConsumerState<BannerEditorDialog> createState() => _BannerEditorDialogState();
}

class _BannerEditorDialogState extends ConsumerState<BannerEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final BannerModel? _original = widget.banner;
  late final String _id = _original?.id ?? ref.read(bannerAdminRepositoryProvider).newId();
  late BannerPlacement _placement = _original?.placement ?? widget.initialPlacement ?? BannerPlacement.homeTop;
  late String? _imageEn = _original?.imageUrl;
  late String? _imageAr = _original?.imageUrlAr;
  late String? _imageKu = _original?.imageUrlKu;
  late BannerActionType _actionType = _original?.actionType ?? BannerActionType.route;

  /// One remembered value per action type, so switching type back and forth keeps input.
  late final Map<BannerActionType, String> _values = {
    if (_original != null) _original!.actionType: _original!.actionValue,
  };
  late final _productId = TextEditingController(text: _values[BannerActionType.product] ?? '');
  late final _url = TextEditingController(text: _values[BannerActionType.url] ?? '');
  late String _lookupId = _productId.text.trim();
  Timer? _debounce;
  late bool _isActive = _original?.isActive ?? true;
  late DateTime? _startAt = _original?.startAt;
  late DateTime? _endAt = _original?.endAt;
  Map<String, String> _errors = const {};
  bool _saving = false;
  String? _error;

  bool get _isNew => _original == null;

  @override
  void dispose() {
    _debounce?.cancel();
    _productId.dispose();
    _url.dispose();
    super.dispose();
  }

  BannerModel _build() {
    String? opt(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    return BannerModel(
      id: _id,
      imageUrl: opt(_imageEn) ?? '',
      imageUrlAr: opt(_imageAr),
      imageUrlKu: opt(_imageKu),
      placement: _placement,
      actionType: _actionType,
      actionValue: (_values[_actionType] ?? '').trim(),
      sortOrder: _original?.sortOrder ?? 0,
      isActive: _isActive,
      startAt: _startAt,
      endAt: _endAt,
    );
  }

  Future<void> _save() async {
    final categories = ref.read(adminCategoriesProvider).valueOrNull;
    final model = _build();
    final errors = {...validateBanner(model, categoryIds: categories?.map((c) => c.id))};
    final formOk = _form.currentState!.validate();
    setState(() {
      _errors = errors;
      _error = null;
    });
    if (!formOk || errors.isNotEmpty) {
      setState(() => _error = errors.isEmpty ? 'Fix the highlighted fields.' : errors.values.join('\n'));
      return;
    }
    setState(() => _saving = true);
    try {
      if (model.actionType == BannerActionType.product) {
        final title = await ref.read(productTitleProvider(model.actionValue).future);
        if (title == null) {
          final message = 'No product with the id "${model.actionValue}"';
          if (mounted) {
            setState(() {
              _errors = {'action': message};
              _error = message;
            });
          }
          return;
        }
      }
      final repo = ref.read(bannerAdminRepositoryProvider);
      final all = ref.read(adminBannersProvider).valueOrNull ?? widget.all;
      final ids = categories?.map((c) => c.id);
      if (_isNew) {
        await repo.create(model, existing: all, categoryIds: ids);
      } else {
        await repo.update(_original!, model, existing: all, categoryIds: ids);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setValue(String v) => setState(() => _values[_actionType] = v);

  Widget _actionValueField(BuildContext context) {
    final error = _errors['action'];
    switch (_actionType) {
      case BannerActionType.category:
        final categories = ref.watch(adminCategoriesProvider).valueOrNull ?? const [];
        final current = _values[BannerActionType.category];
        final known = categories.any((c) => c.id == current);
        return DropdownButtonFormField<String>(
          key: const ValueKey('action-category'),
          initialValue: current == null || current.isEmpty ? null : current,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Category *', errorText: error),
          items: [
            for (final c in categories)
              DropdownMenuItem(
                value: c.id,
                child: Text('${c.title.en}${c.isActive ? '' : ' (inactive)'}', overflow: TextOverflow.ellipsis),
              ),
            if (current != null && current.isNotEmpty && !known)
              DropdownMenuItem(value: current, child: Text('$current (missing)')),
          ],
          onChanged: (v) => _setValue(v ?? ''),
        );
      case BannerActionType.product:
        final lookup = _lookupId.isEmpty ? null : ref.watch(productTitleProvider(_lookupId));
        final scheme = Theme.of(context).colorScheme;
        final helper = lookup?.when(
          loading: () => 'Looking up…',
          error: (e, _) => 'Lookup failed: $e',
          data: (title) => title ?? 'No product with this id',
        );
        final found = lookup?.valueOrNull != null;
        return TextFormField(
          key: const ValueKey('action-product'),
          controller: _productId,
          decoration: InputDecoration(
            labelText: 'Product id *',
            errorText: error,
            helperText: helper,
            helperStyle: TextStyle(color: found ? AppColors.success : (lookup?.hasValue ?? false) ? scheme.error : null),
            prefixIcon: Icon(found ? Icons.check_circle_outline : Icons.search, color: found ? AppColors.success : null),
          ),
          onChanged: (v) {
            _values[BannerActionType.product] = v.trim();
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), () {
              if (mounted) setState(() => _lookupId = v.trim());
            });
          },
        );
      case BannerActionType.url:
        return TextFormField(
          key: const ValueKey('action-url'),
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: 'Link *', hintText: 'https://…', errorText: error),
          validator: (v) => isHttpsUrl(v ?? '') ? null : 'Links must be full https:// URLs',
          onChanged: (v) => _values[BannerActionType.url] = v.trim(),
        );
      case BannerActionType.route:
        final current = _values[BannerActionType.route];
        final known = bannerRouteOptions.any((r) => r.$1 == current);
        return DropdownButtonFormField<String>(
          key: const ValueKey('action-route'),
          initialValue: known ? current : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'App screen *', errorText: error),
          items: [
            for (final (path, label) in bannerRouteOptions)
              DropdownMenuItem(value: path, child: Text('$label  ·  $path', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => _setValue(v ?? ''),
        );
    }
  }

  Widget _imageField(String label, String? value, String suffix, ValueChanged<String?> onChanged, String? error) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        ImageField(
          label: label,
          value: value,
          previewSize: 72,
          storagePath: () => 'banners/$_id$suffix.jpg',
          onChanged: (v) => setState(() => onChanged(v)),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: AppSpacing.md),
      ]);

  Widget _dateButton(String label, DateTime? value, ValueChanged<DateTime?> onChanged,
          {TimeOfDay defaultTime = const TimeOfDay(hour: 0, minute: 0)}) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await pickDateTime(context, value, helpText: label, defaultTime: defaultTime);
              if (picked != null) setState(() => onChanged(picked));
            },
            icon: const Icon(Icons.schedule),
            label: Text('$label: ${value == null ? 'not set' : bannerDateFormat.format(value)}'),
          ),
          if (value != null)
            IconButton(tooltip: 'Clear', onPressed: () => setState(() => onChanged(null)), icon: const Icon(Icons.clear)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = _build();
    final scheduleError = _errors['schedule'] ??
        ((_startAt != null && _endAt != null && !_endAt!.isAfter(_startAt!)) ? 'The end must be after the start' : null);

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
                    child: Text(_isNew ? 'New banner' : 'Edit banner',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  BannerStatusBadge(status: bannerStatus(draft, DateTime.now())),
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
                    DropdownButtonFormField<BannerPlacement>(
                      initialValue: _placement,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Placement', helperText: placementHint(_placement)),
                      items: [
                        for (final p in BannerPlacement.values) DropdownMenuItem(value: p, child: Text(placementLabel(p))),
                      ],
                      onChanged: (v) => setState(() => _placement = v ?? _placement),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Artwork (16:7). Arabic and Kurdish fall back to English when empty.',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context))),
                    const SizedBox(height: AppSpacing.sm),
                    _imageField('English *', _imageEn, '', (v) => _imageEn = v, _errors['imageUrl']),
                    _imageField('Arabic', _imageAr, '_ar', (v) => _imageAr = v, _errors['imageUrlAr']),
                    _imageField('Kurdish', _imageKu, '_ku', (v) => _imageKu = v, _errors['imageUrlKu']),
                    Text('On tap', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<BannerActionType>(
                      showSelectedIcon: false,
                      segments: [
                        for (final t in BannerActionType.values) ButtonSegment(value: t, label: Text(actionTypeLabel(t))),
                      ],
                      selected: {_actionType},
                      onSelectionChanged: (s) => setState(() {
                        _actionType = s.first;
                        _errors = {..._errors}..remove('action');
                      }),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _actionValueField(context),
                    const SizedBox(height: AppSpacing.md),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      subtitle: const Text('Inactive banners are never shown, whatever the schedule.'),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Schedule (optional, your local time)',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, children: [
                      _dateButton('Start', _startAt, (v) => _startAt = v),
                      _dateButton('End', _endAt, (v) => _endAt = v,
                          defaultTime: const TimeOfDay(hour: 23, minute: 59)),
                    ]),
                    if (scheduleError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(scheduleError, style: TextStyle(color: theme.colorScheme.error)),
                      ),
                  ]),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(children: [
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
