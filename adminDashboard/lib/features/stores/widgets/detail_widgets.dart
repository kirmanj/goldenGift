import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import '../../../core/web/browser.dart';
import '../../../core/widgets/form_widgets.dart';
import '../data/stores_admin_repository.dart' show validateReason;

/// Coloured status chip (same look as the orders' status chip).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.isDark(context) && color == AppColors.primaryDark ? AppColors.accent : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// "Label    value  [copy]" line of a detail panel.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.copy, this.child, this.labelWidth = 130});
  final String label;
  final String value;
  final String? copy;

  /// Replaces the value text (e.g. a link button).
  final Widget? child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: labelWidth, child: Text(label, style: TextStyle(color: AppColors.textMuted(context)))),
          Expanded(child: child ?? SelectableText(value.isEmpty ? '—' : value)),
          if (copy != null && copy!.isNotEmpty)
            IconButton(
              tooltip: 'Copy $label',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copy!));
                showMessage(context, 'Copied');
              },
              icon: const Icon(Icons.copy),
            ),
        ]),
      );
}

/// Square network image that opens full size in a new tab.
class ImageThumb extends StatelessWidget {
  const ImageThumb({super.key, required this.url, this.size = 72, this.openOnTap = true});
  final String? url;
  final double size;
  final bool openOnTap;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: AppColors.field(context),
      child: Icon(Icons.image_outlined, color: AppColors.textMuted(context)),
    );
    final u = url;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: size,
        height: size,
        child: u == null || u.isEmpty
            ? placeholder
            : Image.network(u, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
      ),
    );
    if (!openOnTap || u == null || u.isEmpty) return image;
    return Tooltip(
      message: 'Open full size',
      child: InkWell(borderRadius: BorderRadius.circular(AppRadius.sm), onTap: () => openInNewTab(u), child: image),
    );
  }
}

/// Asks for a required reason; resolves to the trimmed text or null (cancel).
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  String? message,
  String label = 'Reason *',
  String confirmLabel = 'Confirm',
  bool destructive = false,
  int maxLength = 500,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: title,
        message: message,
        label: label,
        confirmLabel: confirmLabel,
        destructive: destructive,
        maxLength: maxLength,
      ),
    );

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.confirmLabel,
    required this.destructive,
    required this.maxLength,
  });

  final String title;
  final String? message;
  final String label;
  final String confirmLabel;
  final bool destructive;
  final int maxLength;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) Navigator.pop(context, _reason.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: AppSpacing.md)],
              TextFormField(
                key: const ValueKey('reasonField'),
                controller: _reason,
                autofocus: true,
                maxLength: widget.maxLength,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(labelText: widget.label),
                validator: (v) => validateReason(v, max: widget.maxLength),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: widget.destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
            onPressed: _submit,
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}

/// Centered icon + text (+ action) for empty / error / not-found states.
class CenteredNote extends StatelessWidget {
  const CenteredNote({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: AppColors.textMuted(context)),
            const SizedBox(height: AppSpacing.md),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
          ]),
        ),
      );
}
