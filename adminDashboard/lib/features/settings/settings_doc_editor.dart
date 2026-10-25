import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import '../../core/widgets/form_widgets.dart';
import 'settings_data.dart';

/// What a tab's form sees: the working copy, the saved copy, and how to change it.
class SettingsDraft<T> {
  const SettingsDraft({required this.value, required this.saved, required this.exists, required this.update});

  final T value;
  final T saved;

  /// False until the document is first saved (the app runs on defaults).
  final bool exists;
  final void Function(T Function(T current) change) update;
}

/// Loads one `app_settings/{docId}` through the shared model's `fromMap`,
/// keeps a draft with an "unsaved changes" state, and saves the draft in one
/// batch with its audit entry. Kept alive inside the settings tabs.
class SettingsDocEditor<T> extends ConsumerStatefulWidget {
  const SettingsDocEditor({
    super.key,
    required this.docId,
    required this.fromMap,
    required this.toMap,
    required this.builder,
    this.validate,
    this.onDirtyChanged,
  });

  final String docId;
  final T Function(Map<String, dynamic> map) fromMap;
  final Map<String, dynamic> Function(T value) toMap;
  final Widget Function(BuildContext context, SettingsDraft<T> draft) builder;
  final List<String> Function(T value)? validate;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  ConsumerState<SettingsDocEditor<T>> createState() => _SettingsDocEditorState<T>();
}

class _SettingsDocEditorState<T> extends ConsumerState<SettingsDocEditor<T>> with AutomaticKeepAliveClientMixin {
  final _form = GlobalKey<FormState>();
  late final ProviderSubscription<AsyncValue<Map<String, dynamic>?>> _sub;
  T? _saved;
  T? _draft;
  bool _exists = false;

  /// Bumped to rebuild the form fields from the draft (load, discard, save).
  int _epoch = 0;
  bool _saving = false;
  bool _changedElsewhere = false;
  bool _lastDirty = false;
  Object? _loadError;
  List<String> _errors = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual(settingsDocProvider(widget.docId), (_, next) => _onDoc(next, notify: true));
    _onDoc(_sub.read(), notify: false);
  }

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }

  String _key(T value) => jsonEncode(widget.toMap(value));

  bool get _dirty => _draft != null && _saved != null && _key(_draft as T) != _key(_saved as T);

  void _apply(VoidCallback change, {required bool notify}) {
    if (notify && mounted) {
      setState(change);
    } else {
      change();
    }
    _reportDirty();
  }

  void _reportDirty() {
    final dirty = _dirty;
    if (dirty == _lastDirty) return;
    _lastDirty = dirty;
    widget.onDirtyChanged?.call(dirty);
  }

  void _onDoc(AsyncValue<Map<String, dynamic>?> next, {required bool notify}) {
    if (next.hasError && _saved == null) {
      _apply(() => _loadError = next.error, notify: notify);
      return;
    }
    if (!next.hasValue) return;
    final data = next.value;
    final parsed = widget.fromMap(data ?? const <String, dynamic>{});
    _apply(() {
      _loadError = null;
      _exists = data != null;
      if (_saved == null || !_dirty) {
        final changed = _saved == null || _key(parsed) != _key(_saved as T);
        _saved = parsed;
        if (changed) {
          _draft = parsed;
          _epoch++;
        }
      } else {
        // Editing: keep the draft. Our own save echoes back equal to the draft.
        if (_key(parsed) != _key(_saved as T) && _key(parsed) != _key(_draft as T)) _changedElsewhere = true;
        _saved = parsed;
      }
    }, notify: notify);
  }

  void _update(T Function(T current) change) {
    final draft = _draft;
    if (draft == null) return;
    _apply(() {
      _draft = change(draft);
      _errors = const [];
    }, notify: true);
  }

  void _discard() => _apply(() {
        _draft = _saved;
        _errors = const [];
        _changedElsewhere = false;
        _epoch++;
      }, notify: true);

  Future<void> _save() async {
    final draft = _draft;
    final saved = _saved;
    if (draft == null || saved == null) return;
    final formOk = _form.currentState?.validate() ?? true;
    final errors = widget.validate?.call(draft) ?? const <String>[];
    setState(() => _errors = errors);
    if (!formOk || errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(settingsAdminRepositoryProvider).save(
            widget.docId,
            before: _exists ? widget.toMap(saved) : null,
            after: widget.toMap(draft),
          );
      if (!mounted) return;
      _apply(() {
        _saved = draft;
        _exists = true;
        _changedElsewhere = false;
        _epoch++;
      }, notify: true);
      showMessage(context, 'Saved');
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loadError != null) return Center(child: Text('Could not load app_settings/${widget.docId}: $_loadError'));
    final draft = _draft;
    final saved = _saved;
    if (draft == null || saved == null) return const Center(child: CircularProgressIndicator());
    final dirty = _dirty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StatusBar(
        dirty: dirty,
        exists: _exists,
        saving: _saving,
        changedElsewhere: _changedElsewhere,
        onDiscard: dirty && !_saving ? _discard : null,
        onSave: (dirty || !_exists) && !_saving ? _save : null,
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_errors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _ErrorList(errors: _errors),
                    ),
                  KeyedSubtree(
                    key: ValueKey(_epoch),
                    child: widget.builder(
                      context,
                      SettingsDraft<T>(value: draft, saved: saved, exists: _exists, update: _update),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.dirty,
    required this.exists,
    required this.saving,
    required this.changedElsewhere,
    required this.onDiscard,
    required this.onSave,
  });

  final bool dirty;
  final bool exists;
  final bool saving;
  final bool changedElsewhere;
  final VoidCallback? onDiscard;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = dirty
        ? (Icons.edit_note, 'Unsaved changes', AppColors.warning)
        : !exists
            ? (Icons.info_outline, 'Not saved yet — the app is using its defaults', AppColors.info)
            : (Icons.check_circle_outline, 'All changes saved', AppColors.success);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line(context)))),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              changedElsewhere ? '$text · this document changed elsewhere — discard to load the latest' : text,
              key: const ValueKey('settings-status'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: dirty ? color : null, fontWeight: dirty ? FontWeight.w700 : null),
            ),
          ),
          TextButton(onPressed: onDiscard, child: const Text('Discard')),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            onPressed: onSave,
            icon: saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ]),
      ),
    );
  }
}

class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.errors});
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: error.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in errors) Text('• $e', style: TextStyle(color: error)),
      ]),
    );
  }
}

/// Lays fields out in two columns when there is room.
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.children, this.minColumnWidth = 300});
  final List<Widget> children;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final twoColumns = c.maxWidth >= minColumnWidth * 2 + AppSpacing.md;
        final width = twoColumns ? (c.maxWidth - AppSpacing.md) / 2 : c.maxWidth;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      });
}

/// A muted explanatory note inside a section.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key, this.icon = Icons.info_outline, this.color});
  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.textMuted(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: (color ?? AppColors.gold(context)).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg))),
      ]),
    );
  }
}
