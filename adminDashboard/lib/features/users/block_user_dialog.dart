import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import 'data/function_errors.dart';
import 'data/users_admin_repository.dart';

/// Confirms blocking (reason required) or unblocking (reason optional) and
/// calls `setUserBlocked`. Resolves to the new blocked state, or null when cancelled.
Future<bool?> showBlockUserDialog(BuildContext context,
        {required String uid, required String userName, required bool currentlyBlocked}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlockUserDialog(uid: uid, userName: userName, block: !currentlyBlocked),
    );

class BlockUserDialog extends ConsumerStatefulWidget {
  const BlockUserDialog({super.key, required this.uid, required this.userName, required this.block});
  final String uid;
  final String userName;

  /// True to block, false to unblock.
  final bool block;

  static const reasonMax = 300;

  @override
  ConsumerState<BlockUserDialog> createState() => _BlockUserDialogState();
}

class _BlockUserDialogState extends ConsumerState<BlockUserDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final blocked = await ref
          .read(usersAdminRepositoryProvider)
          .setBlocked(uid: widget.uid, blocked: widget.block, reason: _reason.text);
      if (mounted) Navigator.of(context).pop(blocked);
    } catch (e) {
      if (mounted) {
        setState(() => _error = functionErrorMessage('setUserBlocked', e,
            action: widget.block ? 'block the user' : 'unblock the user'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final block = widget.block;
    return AlertDialog(
      title: Text(block ? 'Block ${widget.userName}?' : 'Unblock ${widget.userName}?'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(block
                ? 'They are signed out on every device and cannot sign in or order until unblocked. '
                    'Their orders, wallet and referrals are kept.'
                : 'They can sign in and order again.'),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('block-reason'),
              controller: _reason,
              autofocus: true,
              maxLength: BlockUserDialog.reasonMax,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: block ? 'Reason (for the audit log) *' : 'Reason (optional)'),
              validator: (v) => block && (v?.trim().length ?? 0) < 3 ? 'A reason of at least 3 characters is required' : null,
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: block ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: AppColors.white) : null,
          onPressed: _saving ? null : _confirm,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(block ? 'Block user' : 'Unblock user'),
        ),
      ],
    );
  }
}
