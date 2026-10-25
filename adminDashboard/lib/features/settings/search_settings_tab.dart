import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/app_settings_model.dart';

import '../../core/widgets/form_widgets.dart';
import 'settings_data.dart';
import 'settings_doc_editor.dart';

/// `app_settings/search`: Algolia text search (SRS §6.14, §12 item 7).
class SearchSettingsTab extends StatelessWidget {
  const SearchSettingsTab({super.key, this.onDirtyChanged});
  final ValueChanged<bool>? onDirtyChanged;

  @override
  Widget build(BuildContext context) => SettingsDocEditor<SearchSettings>(
        docId: SettingsDocs.search,
        fromMap: SearchSettings.fromMap,
        toMap: (s) => s.toMap(),
        validate: validateSearchSettings,
        onDirtyChanged: onDirtyChanged,
        builder: (context, d) => _SearchForm(draft: d),
      );
}

class _SearchForm extends StatefulWidget {
  const _SearchForm({required this.draft});
  final SettingsDraft<SearchSettings> draft;

  @override
  State<_SearchForm> createState() => _SearchFormState();
}

class _SearchFormState extends State<_SearchForm> {
  bool _showKey = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final s = d.value;
    final configured = s.isConfigured;
    return SectionCard(
      title: 'Algolia',
      trailing: Chip(
        avatar: Icon(configured ? Icons.bolt : Icons.search, size: 16),
        label: Text(configured ? 'App uses Algolia' : 'App uses keyword fallback'),
      ),
      children: [
        const SettingsNote('The app switches to Algolia only once both the Application ID and the search key are set '
            '(and saved). Until then text search uses the Firestore keyword fallback.'),
        const SizedBox(height: AppSpacing.md),
        FieldGrid(children: [
          TextFormField(
            initialValue: s.algoliaAppId,
            decoration: const InputDecoration(labelText: 'Application ID', hintText: 'e.g. ABCD1234EF'),
            onChanged: (v) => d.update((s) => s.copyWith(algoliaAppId: v.trim())),
          ),
          TextFormField(
            initialValue: s.indexName,
            decoration: const InputDecoration(labelText: 'Index name *', helperText: 'Default: products'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            onChanged: (v) => d.update((s) => s.copyWith(indexName: v.trim())),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: s.algoliaSearchKey,
          obscureText: !_showKey,
          decoration: InputDecoration(
            labelText: 'Search-only API key',
            suffixIcon: IconButton(
              tooltip: _showKey ? 'Hide' : 'Show',
              onPressed: () => setState(() => _showKey = !_showKey),
              icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            ),
          ),
          onChanged: (v) => d.update((s) => s.copyWith(algoliaSearchKey: v.trim())),
        ),
        const SizedBox(height: AppSpacing.sm),
        const SettingsNote(
          'Use the SEARCH-ONLY key. This document is public — every app user can read it. Never paste the Admin '
          'API key here: it can change or delete the index. The admin key lives only in Secret Manager '
          '(ALGOLIA_ADMIN_KEY) for the sync function.',
          icon: Icons.gpp_maybe_outlined,
          color: AppColors.error,
        ),
      ],
    );
  }
}
