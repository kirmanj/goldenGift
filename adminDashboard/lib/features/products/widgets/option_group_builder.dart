import 'package:flutter/material.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import '../../../core/widgets/form_widgets.dart';
import '../domain/product_draft.dart';
import 'product_form_fields.dart';

IconData optionTypeIcon(OptionType type) => switch (type) {
      OptionType.imageVariant => Icons.photo_library_outlined,
      OptionType.textVariant => Icons.label_outline,
      OptionType.colorSwatch => Icons.palette_outlined,
      OptionType.text => Icons.short_text,
      OptionType.longText => Icons.notes,
      OptionType.date => Icons.event_outlined,
      OptionType.photoUpload => Icons.add_a_photo_outlined,
      OptionType.quantity => Icons.exposure_plus_1,
    };

void _move<T>(List<T> list, int index, int delta) {
  final item = list.removeAt(index);
  list.insert(index + delta, item);
}

/// The option-group builder (SRS §5.9, §9 "Products"): every [OptionType],
/// trilingual labels, required flag, order (= `sortOrder`), type settings and
/// values with images, swatches, price deltas, stock and preparation-day
/// overrides. Edits [groups] in place and calls [onChanged] after each change.
class OptionGroupBuilder extends StatelessWidget {
  const OptionGroupBuilder({
    super.key,
    required this.groups,
    required this.onChanged,
    required this.storageFolder,
  });

  final List<OptionGroupDraft> groups;
  final VoidCallback onChanged;

  /// `products/{productId}` — value images go to `{folder}/options/{groupId}-{valueId}.jpg`.
  final String Function() storageFolder;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return SectionCard(
      title: 'Option groups',
      trailing: AddOptionGroupButton(onSelected: (type) {
        groups.add(OptionGroupDraft.newOf(type));
        onChanged();
      }),
      children: [
        Text('Shown in this order on Product Details. Required groups must be filled in before Add to Cart.',
            style: muted),
        const SizedBox(height: AppSpacing.md),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('No option groups — the product is sold as is.', textAlign: TextAlign.center, style: muted),
          ),
        for (var i = 0; i < groups.length; i++)
          Padding(
            key: ObjectKey(groups[i]),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: OptionGroupCard(
              group: groups[i],
              index: i,
              count: groups.length,
              onMove: (delta) {
                _move(groups, i, delta);
                onChanged();
              },
              onDelete: () {
                groups.removeAt(i);
                onChanged();
              },
              onChanged: onChanged,
              storageFolder: storageFolder,
            ),
          ),
      ],
    );
  }
}

/// "Add group" menu listing all 8 option types.
class AddOptionGroupButton extends StatelessWidget {
  const AddOptionGroupButton({super.key, required this.onSelected});
  final ValueChanged<OptionType> onSelected;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        builder: (context, controller, _) => OutlinedButton.icon(
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.add),
          label: const Text('Add group'),
        ),
        menuChildren: [
          for (final type in OptionType.values)
            MenuItemButton(
              leadingIcon: Icon(optionTypeIcon(type)),
              onPressed: () => onSelected(type),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(optionTypeLabel(type)),
                  Text(optionTypeHint(type), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
        ],
      );
}

class OptionGroupCard extends StatelessWidget {
  const OptionGroupCard({
    super.key,
    required this.group,
    required this.index,
    required this.count,
    required this.onMove,
    required this.onDelete,
    required this.onChanged,
    required this.storageFolder,
  });

  final OptionGroupDraft group;
  final int index;
  final int count;
  final ValueChanged<int> onMove;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final String Function() storageFolder;

  Future<void> _confirmDelete(BuildContext context) async {
    final name = group.label.en.trim().isEmpty ? optionTypeLabel(group.type) : group.label.en.trim();
    final ok = await confirmAction(
      context,
      title: 'Delete option group?',
      message: group.hasValues && group.values.isNotEmpty
          ? 'Remove “$name” and its ${group.values.length} value(s)? This takes effect when you save.'
          : 'Remove “$name”? This takes effect when you save.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final g = group;
    final title = g.label.en.trim().isEmpty ? 'Untitled ${optionTypeLabel(g.type).toLowerCase()}' : g.label.en.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(optionTypeIcon(g.type), color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${index + 1}. $title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text('${optionTypeLabel(g.type)} · id: ${g.id}${g.idLocked ? ' (saved)' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              ]),
            ),
            if (g.type != OptionType.quantity) ...[
              Text('Required', style: theme.textTheme.bodyMedium),
              Switch(
                value: g.required,
                onChanged: (v) {
                  g.required = v;
                  onChanged();
                },
              ),
            ],
            IconButton(
              tooltip: 'Move group up',
              icon: const Icon(Icons.arrow_upward),
              onPressed: index > 0 ? () => onMove(-1) : null,
            ),
            IconButton(
              tooltip: 'Move group down',
              icon: const Icon(Icons.arrow_downward),
              onPressed: index < count - 1 ? () => onMove(1) : null,
            ),
            IconButton(
              tooltip: 'Delete group',
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: () => _confirmDelete(context),
            ),
            IconButton(
              tooltip: g.expanded ? 'Collapse group' : 'Expand group',
              icon: Icon(g.expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () {
                g.expanded = !g.expanded;
                onChanged();
              },
            ),
          ]),
          if (g.expanded) ...[
            const SizedBox(height: AppSpacing.md),
            TrilingualField(
              label: 'Group label',
              value: g.label,
              onChanged: (t) {
                g.label = t;
                onChanged();
              },
            ),
            ..._settings(context, muted),
            if (g.hasValues) ..._values(context, muted),
          ],
        ]),
      ),
    );
  }

  List<Widget> _settings(BuildContext context, TextStyle? muted) {
    final g = group;
    switch (g.type) {
      case OptionType.text || OptionType.longText:
        return [
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: 220,
              child: IntField(
                label: 'Max length',
                value: g.maxLength,
                helperText: 'Characters; empty = no limit',
                validator: (v) => v != null && v < 1 ? 'At least 1' : null,
                onChanged: (v) {
                  g.maxLength = v;
                  onChanged();
                },
              ),
            ),
          ),
        ];
      case OptionType.photoUpload:
        return [
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, children: [
            SizedBox(
              width: 160,
              child: IntField(
                label: 'Min photos *',
                value: g.minPhotos,
                helperText: '1 – $maxPhotoSlots',
                validator: (v) {
                  if (v == null) return 'Required';
                  if (v < 1) return 'At least 1';
                  if (g.maxPhotos != null && v > g.maxPhotos!) return 'Above max';
                  return null;
                },
                onChanged: (v) {
                  g.minPhotos = v;
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 160,
              child: IntField(
                label: 'Max photos *',
                value: g.maxPhotos,
                helperText: '1 – $maxPhotoSlots',
                validator: (v) {
                  if (v == null) return 'Required';
                  if (v > maxPhotoSlots) return 'At most $maxPhotoSlots';
                  if (g.minPhotos != null && v < g.minPhotos!) return 'Below min';
                  return null;
                },
                onChanged: (v) {
                  g.maxPhotos = v;
                  onChanged();
                },
              ),
            ),
          ]),
        ];
      case OptionType.date:
        return [const SizedBox(height: AppSpacing.sm), Text('Customers pick a date — nothing else to set.', style: muted)];
      case OptionType.quantity:
        return [
          const SizedBox(height: AppSpacing.sm),
          Text('Shown as the quantity stepper in the bottom bar.', style: muted),
        ];
      case OptionType.imageVariant || OptionType.textVariant || OptionType.colorSwatch:
        return const [];
    }
  }

  List<Widget> _values(BuildContext context, TextStyle? muted) {
    final g = group;
    final theme = Theme.of(context);
    return [
      const SizedBox(height: AppSpacing.md),
      Row(children: [
        Expanded(
          child: Text('Values (${g.values.length})',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        ),
        TextButton.icon(
          onPressed: () {
            g.values.add(OptionValueDraft());
            onChanged();
          },
          icon: const Icon(Icons.add),
          label: const Text('Add value'),
        ),
      ]),
      if (g.values.isEmpty)
        Text('Add at least one value.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      for (final (j, v) in g.values.indexed)
        Padding(
          key: ObjectKey(v),
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: OptionValueTile(
            type: g.type,
            value: v,
            index: j,
            count: g.values.length,
            onMove: (delta) {
              _move(g.values, j, delta);
              onChanged();
            },
            onDelete: () {
              g.values.remove(v);
              onChanged();
            },
            onChanged: onChanged,
            imagePath: () => '${storageFolder()}/options/${g.id}-${v.id}.jpg',
          ),
        ),
    ];
  }
}

class OptionValueTile extends StatelessWidget {
  const OptionValueTile({
    super.key,
    required this.type,
    required this.value,
    required this.index,
    required this.count,
    required this.onMove,
    required this.onDelete,
    required this.onChanged,
    required this.imagePath,
  });

  final OptionType type;
  final OptionValueDraft value;
  final int index;
  final int count;
  final ValueChanged<int> onMove;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final String Function() imagePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(
                'Value ${index + 1} · id: ${v.id}${v.idLocked ? ' (saved)' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: 'Move value up',
              icon: const Icon(Icons.arrow_upward, size: 20),
              onPressed: index > 0 ? () => onMove(-1) : null,
            ),
            IconButton(
              tooltip: 'Move value down',
              icon: const Icon(Icons.arrow_downward, size: 20),
              onPressed: index < count - 1 ? () => onMove(1) : null,
            ),
            IconButton(
              tooltip: 'Delete value',
              icon: Icon(Icons.close, size: 20, color: scheme.error),
              onPressed: onDelete,
            ),
          ]),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TrilingualField(
                label: 'Value label',
                value: v.label,
                onChanged: (t) {
                  v.label = t;
                  onChanged();
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.start, children: [
                SizedBox(
                  width: 170,
                  child: IntField(
                    label: 'Price delta (IQD)',
                    value: v.priceDelta == 0 ? null : v.priceDelta,
                    hintText: '0',
                    helperText: 'May be negative',
                    signed: true,
                    onChanged: (n) {
                      v.priceDelta = n ?? 0;
                      onChanged();
                    },
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: IntField(
                    label: 'Stock',
                    value: v.stock,
                    helperText: 'Empty = unlimited',
                    onChanged: (n) {
                      v.stock = n;
                      onChanged();
                    },
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: IntField(
                    label: 'Preparation days',
                    value: v.preparationDaysOverride,
                    helperText: 'Optional override',
                    onChanged: (n) {
                      v.preparationDaysOverride = n;
                      onChanged();
                    },
                  ),
                ),
                if (type == OptionType.colorSwatch)
                  HexColorField(
                    value: v.hex,
                    onChanged: (h) {
                      v.hex = h;
                      onChanged();
                    },
                  ),
              ]),
              if (type == OptionType.imageVariant) ...[
                const SizedBox(height: AppSpacing.sm),
                ImageField(
                  label: 'Value image',
                  value: v.imageUrl,
                  previewSize: 64,
                  storagePath: imagePath,
                  onChanged: (url) {
                    v.imageUrl = url;
                    onChanged();
                  },
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
