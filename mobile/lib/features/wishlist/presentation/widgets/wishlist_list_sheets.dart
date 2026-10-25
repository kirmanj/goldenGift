import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../orders/presentation/widgets/order_section.dart' show errorText;
import '../../data/wishlist_repository.dart';
import '../providers/wishlist_providers.dart';

const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
);

/// Bottom sheet listing the customer's wishlists (default first) plus
/// "New list" (SRS §5.15). Resolves to the chosen — or newly created — list,
/// null when dismissed. [selectedId] gets a check mark.
Future<WishlistList?> showWishlistListPicker(BuildContext context, {required String title, String? selectedId}) =>
    showModalBottomSheet<WishlistList>(
      context: context,
      backgroundColor: AppColors.card(context),
      showDragHandle: true,
      isScrollControlled: true,
      shape: _sheetShape,
      builder: (_) => _WishlistListPicker(title: title, selectedId: selectedId),
    );

class _WishlistListPicker extends ConsumerStatefulWidget {
  const _WishlistListPicker({required this.title, this.selectedId});
  final String title;
  final String? selectedId;

  @override
  ConsumerState<_WishlistListPicker> createState() => _WishlistListPickerState();
}

class _WishlistListPickerState extends ConsumerState<_WishlistListPicker> {
  bool _creating = false;

  Future<void> _newList() async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final name = await showWishlistListNameDialog(context, title: l10n.wishlistNewList, confirmLabel: l10n.wishlistCreateList);
    if (name == null || !mounted) return;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    setState(() => _creating = true);
    try {
      final id = await ref.read(wishlistRepositoryProvider).createList(uid, name);
      navigator.pop(WishlistList(id: id, name: name.trim(), createdAt: DateTime.now()));
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lists = ref.watch(wishlistListsOrDefaultProvider);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                children: [
                  for (final list in lists)
                    WishlistSheetOption(
                      key: ValueKey('wishlist-pick-${list.id}'),
                      icon: list.isDefault ? Icons.favorite_rounded : Icons.bookmark_border_rounded,
                      label: wishlistListName(l10n, list),
                      selected: list.id == widget.selectedId,
                      onTap: () => Navigator.of(context).pop(list),
                    ),
                  if (lists.length - 1 < WishlistRepository.maxLists)
                    WishlistSheetOption(
                      key: const ValueKey('wishlist-pick-new'),
                      icon: Icons.add_rounded,
                      label: l10n.wishlistNewList,
                      busy: _creating,
                      onTap: _creating ? null : _newList,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of a wishlist sheet: gold icon, label, check when [selected].
class WishlistSheetOption extends StatelessWidget {
  const WishlistSheetOption({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
    this.busy = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? errorText(context) : AppColors.gold(context);
    return Semantics(
      selected: selected,
      child: ListTile(
        minTileHeight: 56,
        enabled: onTap != null || busy,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
        leading: busy
            ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Icon(icon, color: color),
        title: Text(
          label,
          style: AppTextStyles.label.copyWith(
            color: destructive ? errorText(context) : AppColors.text(context),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        trailing: selected ? Icon(Icons.check_rounded, color: AppColors.gold(context)) : null,
        onTap: onTap,
      ),
    );
  }
}

/// Name field for a new or renamed list; resolves to the trimmed name, null
/// when cancelled.
Future<String?> showWishlistListNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ListNameDialog(title: title, confirmLabel: confirmLabel, initial: initial),
    );

class _ListNameDialog extends StatefulWidget {
  const _ListNameDialog({required this.title, required this.confirmLabel, required this.initial});
  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends State<_ListNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = AppLocalizations.of(context)!.errorRequired);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.card(context),
      title: Text(widget.title, style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
      content: SingleChildScrollView(
        child: GGInput(
          key: const ValueKey('wishlist-list-name'),
          label: l10n.wishlistListName,
          hint: l10n.wishlistListNameHint,
          controller: _name,
          autofocus: true,
          errorText: _error,
          maxLength: WishlistRepository.maxListName,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel, style: TextStyle(color: AppColors.textMuted(context))),
        ),
        TextButton(
          key: const ValueKey('wishlist-list-name-save'),
          onPressed: _submit,
          child: Text(
            widget.confirmLabel,
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.goldText(context)),
          ),
        ),
      ],
    );
  }
}

/// "Delete “Mum's birthday”? Its gifts move to Favourites."
Future<bool> confirmDeleteWishlistList(BuildContext context, String name) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.card(dialogContext),
      title: Text(
        l10n.wishlistDeleteList,
        style: AppTextStyles.heading3.copyWith(color: AppColors.text(dialogContext)),
      ),
      content: Text(
        l10n.wishlistDeleteListConfirm(name, l10n.wishlistDefaultList),
        style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(dialogContext)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel, style: TextStyle(color: AppColors.textMuted(dialogContext))),
        ),
        TextButton(
          key: const ValueKey('wishlist-delete-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.delete, style: TextStyle(fontWeight: FontWeight.w700, color: errorText(dialogContext))),
        ),
      ],
    ),
  );
  return ok ?? false;
}
