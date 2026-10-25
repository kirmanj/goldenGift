import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/app_settings_model.dart';

import '../../core/widgets/form_widgets.dart';
import 'settings_data.dart';
import 'settings_doc_editor.dart';

/// `app_settings/general`: contact info, cut-off, minimum order, maintenance,
/// forced-update versions and store links (SRS §6.14).
class GeneralSettingsTab extends StatelessWidget {
  const GeneralSettingsTab({super.key, this.onDirtyChanged});
  final ValueChanged<bool>? onDirtyChanged;

  @override
  Widget build(BuildContext context) => SettingsDocEditor<GeneralSettings>(
        docId: SettingsDocs.general,
        fromMap: GeneralSettings.fromMap,
        toMap: (s) => s.toMap(),
        validate: validateGeneralSettings,
        onDirtyChanged: onDirtyChanged,
        builder: (context, d) => _GeneralForm(draft: d),
      );
}

class _GeneralForm extends StatelessWidget {
  const _GeneralForm({required this.draft});
  final SettingsDraft<GeneralSettings> draft;

  GeneralSettings get s => draft.value;

  Future<void> _toggleMaintenance(BuildContext context, bool on) async {
    if (on) {
      final ok = await confirmAction(
        context,
        title: 'Turn on maintenance mode?',
        message: 'Once saved, EVERY customer is blocked by the maintenance screen until you turn it off '
            'and save again. Use it only for planned downtime or an emergency.',
        confirmLabel: 'Turn on',
        destructive: true,
      );
      if (!ok) return;
    }
    draft.update((s) => s.copyWith(maintenanceMode: on));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(title: 'Contact & support', children: [
        FieldGrid(children: [
          TextFormField(
            initialValue: s.supportPhone,
            decoration: const InputDecoration(labelText: 'Support phone', hintText: '+964 750 000 0000'),
            keyboardType: TextInputType.phone,
            validator: validateContactPhone,
            onChanged: (v) => draft.update((s) => s.copyWith(supportPhone: v.trim())),
          ),
          TextFormField(
            initialValue: s.whatsapp,
            decoration: const InputDecoration(labelText: 'WhatsApp number', hintText: '+964 750 000 0000'),
            keyboardType: TextInputType.phone,
            validator: validateContactPhone,
            onChanged: (v) => draft.update((s) => s.copyWith(whatsapp: v.trim())),
          ),
          TextFormField(
            initialValue: s.email,
            decoration: const InputDecoration(labelText: 'Support email'),
            keyboardType: TextInputType.emailAddress,
            validator: validateContactEmail,
            onChanged: (v) => draft.update((s) => s.copyWith(email: v.trim())),
          ),
          TextFormField(
            initialValue: s.instagram,
            decoration: const InputDecoration(labelText: 'Instagram', hintText: '@goldengift or a link'),
            onChanged: (v) => draft.update((s) => s.copyWith(instagram: v.trim())),
          ),
        ]),
      ]),
      const SizedBox(height: AppSpacing.md),
      SectionCard(title: 'Orders', children: [
        FieldGrid(children: [
          CutoffTimeField(
            value: s.sameDayCutoff,
            onChanged: (v) => draft.update((s) => s.copyWith(sameDayCutoff: v)),
          ),
          MoneyField(
            label: 'Minimum order',
            value: s.minOrder,
            onChanged: (v) => draft.update((s) => s.copyWith(minOrder: v ?? 0)),
          ),
        ]),
      ]),
      const SizedBox(height: AppSpacing.md),
      SectionCard(title: 'App availability', children: [
        Container(
          decoration: BoxDecoration(
            color: s.maintenanceMode ? AppColors.error.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: SwitchListTile(
            key: const ValueKey('maintenance-switch'),
            title: const Text('Maintenance mode'),
            subtitle: Text(s.maintenanceMode
                ? 'ON — customers see the maintenance screen and cannot use the app.'
                : 'Off — the app works normally.'),
            value: s.maintenanceMode,
            activeThumbColor: AppColors.error,
            onChanged: (v) => _toggleMaintenance(context, v),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Force update', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.xs),
        const SettingsNote('Installs older than the minimum version must update before they can continue. '
            'The update button opens the store link (left empty until the listing exists).'),
        const SizedBox(height: AppSpacing.md),
        FieldGrid(children: [
          TextFormField(
            key: const ValueKey('min-version-ios'),
            initialValue: s.minAppVersionIos,
            decoration: const InputDecoration(labelText: 'Minimum iOS version *', hintText: '1.0.0'),
            validator: validateAppVersion,
            onChanged: (v) => draft.update((s) => s.copyWith(minAppVersionIos: v.trim())),
          ),
          TextFormField(
            key: const ValueKey('min-version-android'),
            initialValue: s.minAppVersionAndroid,
            decoration: const InputDecoration(labelText: 'Minimum Android version *', hintText: '1.0.0'),
            validator: validateAppVersion,
            onChanged: (v) => draft.update((s) => s.copyWith(minAppVersionAndroid: v.trim())),
          ),
          TextFormField(
            initialValue: s.storeUrlIos,
            decoration: const InputDecoration(labelText: 'App Store link', hintText: 'https://apps.apple.com/…'),
            keyboardType: TextInputType.url,
            validator: validateStoreUrl,
            onChanged: (v) => draft.update((s) => s.copyWith(storeUrlIos: v.trim())),
          ),
          TextFormField(
            initialValue: s.storeUrlAndroid,
            decoration: const InputDecoration(labelText: 'Google Play link', hintText: 'https://play.google.com/…'),
            keyboardType: TextInputType.url,
            validator: validateStoreUrl,
            onChanged: (v) => draft.update((s) => s.copyWith(storeUrlAndroid: v.trim())),
          ),
        ]),
      ]),
    ]);
  }
}

/// "HH:mm" with a 24-hour picker; typing works too.
class CutoffTimeField extends StatefulWidget {
  const CutoffTimeField({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<CutoffTimeField> createState() => _CutoffTimeFieldState();
}

class _CutoffTimeFieldState extends State<CutoffTimeField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final parts = _controller.text.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first)?.clamp(0, 23) ?? 14,
      minute: parts.length > 1 ? (int.tryParse(parts[1])?.clamp(0, 59) ?? 0) : 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Same-day cut-off',
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return;
    final text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    _controller.text = text;
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        key: const ValueKey('cutoff-field'),
        controller: _controller,
        decoration: InputDecoration(
          labelText: 'Same-day cut-off *',
          helperText: 'Orders after this local time cannot be delivered today.',
          suffixIcon: IconButton(tooltip: 'Pick a time', onPressed: _pick, icon: const Icon(Icons.schedule)),
        ),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')), LengthLimitingTextInputFormatter(5)],
        validator: validateCutoff,
        onChanged: (v) => widget.onChanged(v.trim()),
      );
}
