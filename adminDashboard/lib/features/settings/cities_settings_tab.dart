import 'package:flutter/material.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/localized_text.dart';

import '../../core/widgets/form_widgets.dart';
import '../categories/slug.dart';
import 'settings_data.dart';
import 'settings_doc_editor.dart';

/// `app_settings/cities` = `{items: [{id, name*, deliveryFee, isActive}]}` (SRS §4.3).
class CitiesSettingsTab extends StatelessWidget {
  const CitiesSettingsTab({super.key, this.onDirtyChanged});
  final ValueChanged<bool>? onDirtyChanged;

  @override
  Widget build(BuildContext context) => SettingsDocEditor<List<CityModel>>(
        docId: SettingsDocs.cities,
        fromMap: CityModel.listFromDoc,
        toMap: citiesDoc,
        validate: validateCities,
        onDirtyChanged: onDirtyChanged,
        builder: (context, d) => _CitiesForm(draft: d),
      );
}

Map<String, dynamic> citiesDoc(List<CityModel> cities) => {
      'items': [for (final c in cities) c.toMap()],
    };

class _CitiesForm extends StatefulWidget {
  const _CitiesForm({required this.draft});
  final SettingsDraft<List<CityModel>> draft;

  @override
  State<_CitiesForm> createState() => _CitiesFormState();
}

class _CitiesFormState extends State<_CitiesForm> {
  /// Stable widget keys per row (cities can be reordered and renamed).
  late final List<int> _keys = List.generate(widget.draft.value.length, (i) => i);
  late int _nextKey = _keys.length;

  /// Rows whose id is already saved: the id is read-only (addresses refer to it).
  late final Set<int> _locked = {
    for (var i = 0; i < widget.draft.value.length; i++)
      if (widget.draft.saved.any((c) => c.id == widget.draft.value[i].id)) _keys[i],
  };

  List<CityModel> get _cities => widget.draft.value;

  void _replace(int index, CityModel city) => widget.draft.update((list) => [...list]..[index] = city);

  void _add([List<CityModel>? cities]) {
    final added = cities ?? [const CityModel(id: '', name: LocalizedText.empty)];
    setState(() {
      for (var i = 0; i < added.length; i++) {
        _keys.add(_nextKey++);
      }
    });
    widget.draft.update((list) => [...list, ...added]);
  }

  Future<void> _remove(int index) async {
    final city = _cities[index];
    final name = city.name.en.isEmpty ? 'this city' : '"${city.name.en}"';
    final ok = await confirmAction(
      context,
      title: 'Remove $name?',
      message: 'After you save, customers can no longer choose it. Addresses already saved with it stay as they are. '
          'To pause deliveries for a while, switch it to inactive instead.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _locked.remove(_keys.removeAt(index)));
    widget.draft.update((list) => [...list]..removeAt(index));
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _cities.length) return;
    setState(() {
      final key = _keys.removeAt(index);
      _keys.insert(target, key);
    });
    widget.draft.update((list) {
      final next = [...list];
      final city = next.removeAt(index);
      next.insert(target, city);
      return next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cities = _cities;
    final active = cities.where((c) => c.isActive).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsNote('Customers can deliver only to active cities; each order pays the city\'s delivery fee once. '
          '${cities.length} cities, $active active. The order here is the order of the city picker.'),
      const SizedBox(height: AppSpacing.md),
      if (cities.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(children: [
              const Text('No cities yet — nobody can check out until at least one is active.'),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => _add(defaultCities(AppConstants.defaultCities)),
                icon: const Icon(Icons.playlist_add),
                label: Text('Add the ${AppConstants.defaultCities.length} default cities'),
              ),
            ]),
          ),
        ),
      for (var i = 0; i < cities.length; i++)
        Padding(
          key: ValueKey(_keys[i]),
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _CityRow(
            city: cities[i],
            locked: _locked.contains(_keys[i]),
            takenIds: [for (var j = 0; j < cities.length; j++) if (j != i) cities[j].id],
            canMoveUp: i > 0,
            canMoveDown: i < cities.length - 1,
            onChanged: (c) => _replace(i, c),
            onRemove: () => _remove(i),
            onMoveUp: () => _move(i, -1),
            onMoveDown: () => _move(i, 1),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.tonalIcon(
          onPressed: () => _add(),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add city'),
        ),
      ),
    ]);
  }
}

class _CityRow extends StatefulWidget {
  const _CityRow({
    required this.city,
    required this.locked,
    required this.takenIds,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final CityModel city;
  final bool locked;
  final List<String> takenIds;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<CityModel> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  State<_CityRow> createState() => _CityRowState();
}

class _CityRowState extends State<_CityRow> {
  late final _id = TextEditingController(text: widget.city.id);
  late bool _idEdited = widget.city.id.isNotEmpty;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  void _rename(LocalizedText name) {
    var city = widget.city.copyWith(name: name);
    if (!widget.locked && !_idEdited) {
      final id = slugify(name.en);
      _id.text = id;
      city = city.copyWith(id: id);
    }
    widget.onChanged(city);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.city;
    final muted = AppColors.textMuted(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextFormField(
                  controller: _id,
                  enabled: !widget.locked,
                  decoration: InputDecoration(
                    labelText: 'Id *',
                    helperText: widget.locked ? 'Saved — cannot change' : 'From the English name',
                  ),
                  validator: widget.locked ? null : (v) => validateSlugId(v, takenIds: widget.takenIds),
                  onChanged: (v) {
                    _idEdited = true;
                    widget.onChanged(c.copyWith(id: v.trim()));
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: MoneyField(
                  label: 'Delivery fee',
                  value: c.deliveryFee,
                  onChanged: (v) => widget.onChanged(c.copyWith(deliveryFee: v ?? 0)),
                ),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Switch(value: c.isActive, onChanged: (v) => widget.onChanged(c.copyWith(isActive: v))),
                const SizedBox(width: AppSpacing.xs),
                Text(c.isActive ? 'Active' : 'Inactive', style: TextStyle(color: c.isActive ? null : muted)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: 'Move up', onPressed: widget.canMoveUp ? widget.onMoveUp : null, icon: const Icon(Icons.arrow_upward)),
                IconButton(
                    tooltip: 'Move down',
                    onPressed: widget.canMoveDown ? widget.onMoveDown : null,
                    icon: const Icon(Icons.arrow_downward)),
                IconButton(tooltip: 'Remove city', onPressed: widget.onRemove, icon: const Icon(Icons.delete_outline)),
              ]),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TrilingualField(label: 'Name', value: c.name, onChanged: _rename),
          if (c.deliveryFee > 0)
            Text('Customers pay ${CurrencyFormatter.format(c.deliveryFee)} per order.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
        ]),
      ),
    );
  }
}
