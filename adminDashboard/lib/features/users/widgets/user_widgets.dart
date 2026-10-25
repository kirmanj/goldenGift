import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/session/admin_session.dart';
import '../../categories/categories_screen.dart' show InfoTag;
import '../../../core/widgets/form_widgets.dart' show showMessage;

final adminDateTime = DateFormat('d MMM yyyy, HH:mm', 'en_US');
final adminDate = DateFormat('d MMM yyyy', 'en_US');

String formatAdminDate(DateTime? d, {bool time = true}) =>
    d == null ? '—' : (time ? adminDateTime : adminDate).format(d.toLocal());

String userDisplayName(UserModel? u, {String? fallback}) {
  final name = u?.name.trim() ?? '';
  if (name.isNotEmpty) return name;
  return fallback ?? (u == null ? 'Unknown user' : '(no name)');
}

/// `+964 7501234567`, or an em dash when the account has no phone yet.
String userPhone(UserModel u) => u.phone.isEmpty ? '—' : '${u.countryCode} ${u.phone}';

String adminRoleLabel(AdminRole r) => switch (r) {
      AdminRole.superAdmin => 'super admin',
      AdminRole.ops => 'ops',
      AdminRole.content => 'content',
      AdminRole.finance => 'finance',
      AdminRole.seller => 'seller',
    };

String walletTxnTypeLabel(WalletTxnType t) => switch (t) {
      WalletTxnType.topUp => 'Top-up',
      WalletTxnType.orderPayment => 'Order payment',
      WalletTxnType.refund => 'Refund',
      WalletTxnType.referralCredit => 'Referral credit',
      WalletTxnType.giftCardRedeem => 'Gift card',
      WalletTxnType.adminAdjustment => 'Admin adjustment',
      WalletTxnType.creditExpiry => 'Credits expired',
    };

/// Phone numbers stay left-to-right whatever surrounds them.
class LtrText extends StatelessWidget {
  const LtrText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) =>
      Text(text, textDirection: TextDirection.ltr, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
}

/// Blocked / Deleted pills for a user.
class UserStateChips extends StatelessWidget {
  const UserStateChips({super.key, required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
        if (user.isBlocked) const InfoTag('Blocked', color: AppColors.error),
        if (user.isDeleted) InfoTag('Deleted', color: AppColors.textMuted(context)),
      ]);
}

/// Label + selectable value, with an optional copy button or custom value widget.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.copy, this.child, this.ltr = false});
  final String label;
  final String value;
  final String? copy;
  final Widget? child;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: 150, child: Text(label, style: TextStyle(color: AppColors.textMuted(context)))),
          Expanded(
            child: child ??
                SelectableText(value, textDirection: ltr ? TextDirection.ltr : null, maxLines: 2),
          ),
          if (copy != null && copy!.isNotEmpty)
            IconButton(
              tooltip: 'Copy',
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

/// Body shown instead of a module the admin's role may not open.
class RoleLockedNotice extends StatelessWidget {
  const RoleLockedNotice({super.key, required this.module, required this.role, required this.who});
  final String module;
  final AdminRole role;

  /// e.g. "super admins, ops and finance".
  final String who;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 40, color: AppColors.textMuted(context)),
            const SizedBox(height: AppSpacing.md),
            Text('Your role (${adminRoleLabel(role)}) cannot open $module.',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text('$module is available to $who.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted(context))),
          ]),
        ),
      );
}

/// A DataTable that scrolls sideways on narrow windows and fills the width on
/// wide ones, with an optional footer (e.g. "Load more") below it.
class ScrollableTable extends StatelessWidget {
  const ScrollableTable({super.key, required this.table, this.footer, this.header});
  final DataTable table;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (header != null) header!,
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: (c.maxWidth - AppSpacing.md * 2).clamp(0, double.infinity)),
                child: table,
              ),
            ),
            if (footer != null) footer!,
          ]),
        ),
      );
}

/// "Load more" under a list whose page is full.
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({super.key, required this.visible, required this.onPressed});
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => visible
      ? Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Center(child: OutlinedButton(onPressed: onPressed, child: const Text('Load more'))),
        )
      : const SizedBox(height: AppSpacing.md);
}

/// Signed IQD amount in the success / error colour.
class SignedAmount extends StatelessWidget {
  const SignedAmount(this.amount, {super.key, required this.format});
  final int amount;
  final String Function(num) format;

  @override
  Widget build(BuildContext context) => Text(
        amount < 0 ? '−${format(-amount)}' : '+${format(amount)}',
        textDirection: TextDirection.ltr,
        style: TextStyle(color: amount < 0 ? AppColors.error : AppColors.success, fontWeight: FontWeight.w700),
      );
}
