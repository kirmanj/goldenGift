import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/store_model.dart';

import '../../../core/session/admin_session.dart';
import '../../../core/widgets/form_widgets.dart';
import '../data/phone_input.dart';
import '../data/stores_admin_repository.dart';

/// Store profile editor (SRS §9 Stores "edit profile, commission %"; Seller
/// view "Store profile"). Admins edit the commission; sellers see it read-only.
class StoreProfileForm extends ConsumerStatefulWidget {
  const StoreProfileForm({super.key, required this.store, required this.commissionEditable, this.readOnly = false});

  final StoreModel store;
  final bool commissionEditable;

  /// Roles that may look but not edit.
  final bool readOnly;

  @override
  ConsumerState<StoreProfileForm> createState() => _StoreProfileFormState();
}

class _StoreProfileFormState extends ConsumerState<StoreProfileForm> {
  final _form = GlobalKey<FormState>();
  late LocalizedText _name = widget.store.name;
  late LocalizedText _description = widget.store.description;
  late String? _logo = widget.store.logoUrl;
  late String? _cover = widget.store.coverUrl;
  late String? _city = widget.store.city;
  late final _phone = TextEditingController(text: widget.store.phone ?? '');
  late final _commission = TextEditingController(text: _formatPct(widget.store.commissionPercent));
  bool _saving = false;
  String? _error;

  static String _formatPct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _phone.dispose();
    _commission.dispose();
    super.dispose();
  }

  StoreProfileUpdate _build() => StoreProfileUpdate(
        name: _name,
        description: _description,
        logoUrl: _logo,
        coverUrl: _cover,
        phone: _phone.text,
        city: _city,
        commissionPercent: widget.commissionEditable ? double.tryParse(_commission.text.trim()) : null,
      );

  Future<void> _save() async {
    final session = ref.read(adminSessionProvider);
    if (session == null) return;
    final formOk = _form.currentState!.validate();
    final update = _build();
    final errors = update.validate();
    if (!formOk || errors.isNotEmpty) {
      setState(() => _error = errors.isEmpty ? 'Fix the highlighted fields.' : errors.join('\n'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(storesAdminRepositoryProvider).updateProfile(widget.store, update, actorUid: session.uid);
      if (mounted) showMessage(context, 'Store profile saved');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: ${e is ArgumentError ? e.message : e}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final id = widget.store.id;
    final theme = Theme.of(context);
    final editable = !widget.readOnly;
    return Form(
      key: _form,
      child: SectionCard(
        title: 'Store profile',
        trailing: editable
            ? FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Save profile'),
              )
            : null,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          AbsorbPointer(
            absorbing: !editable,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TrilingualField(
                label: 'Store name',
                value: _name,
                maxLength: StoreProfileUpdate.nameMax,
                onChanged: (v) => _name = v,
              ),
              const SizedBox(height: AppSpacing.sm),
              TrilingualField(
                label: 'Description',
                value: _description,
                required: false,
                maxLines: 4,
                maxLength: StoreProfileUpdate.descriptionMax,
                onChanged: (v) => _description = v,
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(builder: (context, c) {
                final logo = ImageField(
                  label: 'Logo',
                  value: _logo,
                  storagePath: () => '${FirestorePaths.storeDoc(id)}/logo.jpg',
                  onChanged: (v) => _logo = v,
                );
                final cover = ImageField(
                  label: 'Cover',
                  value: _cover,
                  storagePath: () => '${FirestorePaths.storeDoc(id)}/cover.jpg',
                  onChanged: (v) => _cover = v,
                );
                if (c.maxWidth < 760) return Column(children: [logo, const SizedBox(height: AppSpacing.md), cover]);
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: logo),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cover),
                ]);
              }),
              const SizedBox(height: AppSpacing.md),
              Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    key: const ValueKey('storePhone'),
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Phone', helperText: 'e.g. 0750 123 4567'),
                    validator: (v) => validateStaffPhone(v),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('storeCity:${cities.length}'),
                    initialValue: _city,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'City'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('—')),
                      for (final c in cities)
                        DropdownMenuItem<String?>(value: c.id, child: Text(c.name.en, overflow: TextOverflow.ellipsis)),
                      if (_city != null && !cities.any((c) => c.id == _city))
                        DropdownMenuItem<String?>(value: _city, child: Text(_city!)),
                    ],
                    onChanged: (v) => setState(() => _city = v),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: widget.commissionEditable
                      ? TextFormField(
                          key: const ValueKey('storeCommission'),
                          controller: _commission,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: const InputDecoration(labelText: 'Commission % *', helperText: '0–50'),
                          validator: (v) => validateCommission(double.tryParse(v?.trim() ?? '')),
                        )
                      : InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Commission',
                            helperText: 'Set by Golden Gift',
                          ),
                          child: Text(commissionLabel(widget.store.commissionPercent)),
                        ),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}
