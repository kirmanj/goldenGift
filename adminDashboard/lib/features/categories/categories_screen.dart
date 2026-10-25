import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:intl/intl.dart';

import '../../core/router/admin_routes.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import 'categories_data.dart';
import 'category_editor_dialog.dart';

/// SRS §9 Categories: CRUD, icon upload, drag ordering, seasonal windows,
/// occasion vs product type, status Available / Coming soon / Hidden (§5.7a).
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  CategoryFilter _filter = CategoryFilter.all;
  String _query = '';

  /// The order shown while a reorder is being saved.
  List<CategoryModel>? _pendingOrder;

  Future<void> _edit(CategoryModel? category, List<CategoryModel> all) async {
    final saved = await showCategoryEditor(context, category: category, all: all);
    if (saved && mounted) showMessage(context, category == null ? 'Category created' : 'Category saved');
  }

  Future<void> _delete(CategoryModel c, List<CategoryModel> all) async {
    final children = all.where((x) => x.parentId == c.id).map((x) => x.title.en).toList();
    if (children.isNotEmpty) {
      showMessage(context, 'Move or delete its subcategories first: ${children.join(', ')}');
      return;
    }
    final warning = c.productCount > 0
        ? '\n\n${c.productCount} product${c.productCount == 1 ? '' : 's'} still list this category. '
            'They keep the id "${c.id}" until they are edited, but the app will no longer show them under it.'
        : '';
    final ok = await confirmAction(
      context,
      title: 'Delete "${c.title.en}"?',
      message: 'The category disappears from the app immediately.$warning',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(categoryAdminRepositoryProvider).delete(c, existing: all);
      if (mounted) showMessage(context, 'Category deleted');
    } catch (e) {
      if (mounted) showMessage(context, 'Could not delete: $e');
    }
  }

  Future<void> _setStatus(CategoryModel c, CategoryStatus status) async {
    if (c.status == status) return;
    try {
      await ref.read(categoryAdminRepositoryProvider).setStatus(c, status);
      if (!mounted) return;
      showMessage(
        context,
        status == CategoryStatus.comingSoon
            ? '"${c.title.en}" is now Coming soon — add an optional note with Edit.'
            : '"${c.title.en}" is now ${status.label}.',
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Could not change the status: $e');
    }
  }

  Future<void> _reorder(List<CategoryModel> all, int oldIndex, int newIndex) async {
    final moved = moveItem(all, oldIndex, newIndex);
    setState(() => _pendingOrder = moved);
    try {
      await ref.read(categoryAdminRepositoryProvider).reorder(moved);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save the new order: $e');
    } finally {
      if (mounted) setState(() => _pendingOrder = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(adminCategoriesProvider);
    final loaded = categories.valueOrNull;
    return AdminScaffold(
      title: 'Categories',
      selectedRoute: AdminRoutes.categories,
      floatingActionButton: loaded == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(null, loaded),
              icon: const Icon(Icons.add),
              label: const Text('New category'),
            ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load categories: $e')),
        data: (list) => _body(context, _pendingOrder ?? list),
      ),
    );
  }

  Widget _body(BuildContext context, List<CategoryModel> all) {
    final visible = filterAdminCategories(all, _filter, _query);
    final canReorder = _filter == CategoryFilter.all && _query.trim().isEmpty && all.length > 1;
    final titles = {for (final c in all) c.id: c.title.en};
    final byId = {for (final c in all) c.id: c};
    final muted = AppColors.textMuted(context);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by title'),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                for (final f in CategoryFilter.values)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                Text('${visible.length} of ${all.length}', style: TextStyle(color: muted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: Text(
              '${canReorder ? 'Drag the handle to reorder. The app shows categories in this order (Home shows the first 7).' : 'Clear the search and choose "All" to reorder.'}\n'
              "Status: Available · Coming soon — customers see a 'coming soon' page instead of products "
              '(no products yet, or a problem) · Hidden — not shown in the app.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(child: Text(all.isEmpty ? 'No categories yet — add the first one.' : 'No categories match.'))
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 88),
                    itemCount: visible.length,
                    onReorder: (o, n) {
                      if (canReorder) _reorder(all, o, n);
                    },
                    itemBuilder: (context, i) {
                      final c = visible[i];
                      return _CategoryRow(
                        key: ValueKey(c.id),
                        category: c,
                        index: i,
                        canReorder: canReorder,
                        parentTitle: c.parentId == null ? null : (titles[c.parentId] ?? c.parentId),
                        inheritsComingSoon: c.status == CategoryStatus.available && c.isComingSoonWithin(byId),
                        onStatus: (s) => _setStatus(c, s),
                        onEdit: () => _edit(c, all),
                        onDelete: () => _delete(c, all),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.index,
    required this.canReorder,
    required this.parentTitle,
    required this.inheritsComingSoon,
    required this.onStatus,
    required this.onEdit,
    required this.onDelete,
  });

  final CategoryModel category;
  final int index;
  final bool canReorder;
  final String? parentTitle;

  /// Available itself, but under a coming-soon parent: the app treats it as coming soon.
  final bool inheritsComingSoon;
  final ValueChanged<CategoryStatus> onStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static final _date = DateFormat('d MMM yyyy', 'en_US');

  @override
  Widget build(BuildContext context) {
    final c = category;
    final theme = Theme.of(context);
    final translations = [c.title.ar, c.title.ku].whereType<String>().join(' · ');
    final seasonLive = c.isVisibleAt(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          child: Row(children: [
            if (canReorder)
              ReorderableDragStartListener(
                index: index,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(padding: EdgeInsets.all(AppSpacing.sm), child: Icon(Icons.drag_indicator)),
                ),
              )
            else
              const SizedBox(width: AppSpacing.sm),
            CategoryIcon(url: c.iconUrl, size: 44),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title.en, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (translations.isNotEmpty)
                  Text(translations,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context))),
                const SizedBox(height: AppSpacing.xs),
                Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
                  InfoTag(c.id),
                  InfoTag(c.type == CategoryType.occasion ? 'Occasion' : 'Product type', gold: true),
                  if (inheritsComingSoon) const InfoTag('Coming soon via its parent', gold: true),
                  if (c.status == CategoryStatus.comingSoon && !c.comingSoonNote.isEmpty)
                    InfoTag('Note: ${c.comingSoonNote.en.isEmpty ? (c.comingSoonNote.ar ?? c.comingSoonNote.ku ?? '') : c.comingSoonNote.en}'),
                  if (c.isSeasonal)
                    InfoTag(
                      'Seasonal · ${c.activeFrom == null ? '…' : _date.format(c.activeFrom!)} – '
                      '${c.activeTo == null ? '…' : _date.format(c.activeTo!)}'
                      '${c.isActive ? (seasonLive ? ' · showing now' : ' · hidden now') : ''}',
                      color: AppColors.info,
                    ),
                  if (parentTitle != null) InfoTag('In: $parentTitle'),
                  InfoTag('${c.productCount} product${c.productCount == 1 ? '' : 's'}'),
                ]),
              ]),
            ),
            const SizedBox(width: AppSpacing.sm),
            CategoryStatusMenu(status: c.status, onSelected: onStatus),
            IconButton(tooltip: 'Edit', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
            IconButton(tooltip: 'Delete', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
          ]),
        ),
      ),
    );
  }
}

/// Status pill of a row (SRS §5.7a); opens a menu to switch it in one click.
class CategoryStatusMenu extends StatelessWidget {
  const CategoryStatusMenu({super.key, required this.status, required this.onSelected});
  final CategoryStatus status;
  final ValueChanged<CategoryStatus> onSelected;

  static IconData iconOf(CategoryStatus s) => switch (s) {
        CategoryStatus.available => Icons.check_circle_outline,
        CategoryStatus.comingSoon => Icons.hourglass_top_rounded,
        CategoryStatus.hidden => Icons.visibility_off_outlined,
      };

  static Color colorOf(BuildContext context, CategoryStatus s) => switch (s) {
        CategoryStatus.available => AppColors.success,
        CategoryStatus.comingSoon => AppColors.goldText(context),
        CategoryStatus.hidden => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(context, status);
    final bg = status == CategoryStatus.comingSoon ? AppColors.soft(context) : color.withValues(alpha: 0.14);
    return PopupMenuButton<CategoryStatus>(
      key: const ValueKey('category-status-menu'),
      tooltip: 'Change status',
      initialValue: status,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final s in CategoryStatus.values)
          PopupMenuItem<CategoryStatus>(
            value: s,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(iconOf(s), color: colorOf(context, s)),
                title: Text(s.label),
                subtitle: Text(s.description),
                trailing: s == status ? const Icon(Icons.check) : null,
              ),
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget - AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(iconOf(status), size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(status.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
          Icon(Icons.arrow_drop_down, size: 18, color: color),
        ]),
      ),
    );
  }
}

/// Square category icon with a placeholder (also used by the banner editor).
class CategoryIcon extends StatelessWidget {
  const CategoryIcon({super.key, required this.url, this.size = 40});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: AppColors.field(context),
      child: Icon(Icons.category_outlined, size: size * 0.5, color: AppColors.textMuted(context)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: SizedBox.square(
        dimension: size,
        child: url == null || url!.isEmpty
            ? placeholder
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
      ),
    );
  }
}

/// Small pill label. [gold] uses the brand tint; [color] tints a status.
class InfoTag extends StatelessWidget {
  const InfoTag(this.text, {super.key, this.color, this.gold = false});
  final String text;
  final Color? color;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? (gold ? AppColors.goldText(context) : AppColors.textMuted(context));
    final bg = color?.withValues(alpha: 0.14) ?? (gold ? AppColors.soft(context) : AppColors.field(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
