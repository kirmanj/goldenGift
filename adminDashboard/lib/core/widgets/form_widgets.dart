import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// A titled card grouping form fields.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                if (trailing != null) trailing!,
              ]),
              const SizedBox(height: AppSpacing.md),
              ...children,
            ],
          ),
        ),
      );
}

/// English / العربية / کوردی inputs for one catalogue string (SRS §4.2:
/// trilingual content; Arabic & Kurdish fall back to English when empty).
class TrilingualField extends StatefulWidget {
  const TrilingualField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = true,
    this.maxLines = 1,
    this.maxLength,
  });

  final String label;
  final LocalizedText value;
  final ValueChanged<LocalizedText> onChanged;
  final bool required;
  final int maxLines;
  final int? maxLength;

  @override
  State<TrilingualField> createState() => _TrilingualFieldState();
}

class _TrilingualFieldState extends State<TrilingualField> {
  late final _en = TextEditingController(text: widget.value.en);
  late final _ar = TextEditingController(text: widget.value.ar ?? '');
  late final _ku = TextEditingController(text: widget.value.ku ?? '');

  @override
  void dispose() {
    _en.dispose();
    _ar.dispose();
    _ku.dispose();
    super.dispose();
  }

  void _emit() {
    String? opt(String v) => v.trim().isEmpty ? null : v.trim();
    widget.onChanged(LocalizedText(_en.text.trim(), ar: opt(_ar.text), ku: opt(_ku.text)));
  }

  Widget _field(TextEditingController c, String lang, TextDirection dir, {bool required = false}) => TextFormField(
        controller: c,
        textDirection: dir,
        maxLines: widget.maxLines,
        minLines: 1,
        maxLength: widget.maxLength,
        decoration: InputDecoration(labelText: '${widget.label} · $lang${required ? ' *' : ''}'),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
        onChanged: (_) => _emit(),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final fields = [
        _field(_en, 'English', TextDirection.ltr, required: widget.required),
        _field(_ar, 'العربية', TextDirection.rtl),
        _field(_ku, 'کوردی', TextDirection.rtl),
      ];
      if (c.maxWidth < 700 || widget.maxLines > 1) {
        return Column(children: [
          for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: f),
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: fields[i]),
        ],
      ]);
    });
  }
}

/// Whole-IQD amount (SRS: IQD, 0 decimals).
class MoneyField extends StatelessWidget {
  const MoneyField({super.key, required this.label, required this.value, required this.onChanged, this.required = true});
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: InputDecoration(labelText: '$label (IQD)${required ? ' *' : ''}'),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: required ? (v) => (v == null || v.isEmpty) ? 'Required' : null : null,
        onChanged: (v) => onChanged(v.isEmpty ? null : int.tryParse(v)),
      );
}

/// Image by URL, or uploaded to Storage at [storagePath] (SRS §6.16). Upload
/// needs the project's Storage bucket; when it's missing the URL field still works.
class ImageField extends ConsumerStatefulWidget {
  const ImageField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.storagePath,
    this.previewSize = 96,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Where an upload goes, e.g. `categories/mugs.png`.
  final String Function() storagePath;
  final double previewSize;

  @override
  ConsumerState<ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends ConsumerState<ImageField> {
  late final _url = TextEditingController(text: widget.value ?? '');
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    // Raster images only — the Storage rules refuse SVG (scriptable) and others.
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'], withData: true);
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;
    if (file!.size > 10 * 1024 * 1024) {
      setState(() => _error = 'Images must be under 10 MB.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final object = ref.read(storageProvider).ref(widget.storagePath());
      final ext = (file.extension ?? 'jpg').toLowerCase();
      await object.putData(file.bytes!, SettableMetadata(contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}'));
      final url = await object.getDownloadURL();
      _url.text = url;
      widget.onChanged(url);
    } catch (e) {
      setState(() => _error = 'Upload failed — paste an image URL instead. ($e)');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _url.text.trim();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          width: widget.previewSize,
          height: widget.previewSize,
          child: url.isEmpty
              ? ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.image_outlined),
                )
              : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _url,
            decoration: InputDecoration(labelText: '${widget.label} URL'),
            onChanged: (v) {
              setState(() {});
              widget.onChanged(v.trim().isEmpty ? null : v.trim());
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _uploading ? null : _upload,
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_outlined),
              label: const Text('Upload'),
            ),
            if (url.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: () {
                  _url.clear();
                  setState(() {});
                  widget.onChanged(null);
                },
                child: const Text('Remove'),
              ),
            ],
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
    ]);
  }
}

/// Yes/no confirmation; [destructive] colours the confirm button red.
Future<bool> confirmAction(BuildContext context,
    {required String title, required String message, String confirmLabel = 'Confirm', bool destructive = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));
