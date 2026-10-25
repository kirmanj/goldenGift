import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

import '../../core/router/admin_routes.dart';
import '../../core/widgets/admin_scaffold.dart';
import 'cities_settings_tab.dart';
import 'general_settings_tab.dart';
import 'payments_settings_tab.dart';
import 'referral_settings_tab.dart';
import 'search_settings_tab.dart';
import 'settings_data.dart';

/// SRS §9 Settings: `app_settings/*` editors. Each tab loads and saves its own
/// document; switching tabs keeps unsaved edits (a dot marks them).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _tabs = [
    (SettingsDocs.general, 'General', Icons.tune),
    (SettingsDocs.cities, 'Cities & fees', Icons.location_city_outlined),
    (SettingsDocs.payments, 'Payments', Icons.payments_outlined),
    (SettingsDocs.referral, 'Referral', Icons.group_add_outlined),
    (SettingsDocs.search, 'Search', Icons.manage_search),
  ];

  final Set<String> _dirty = {};

  void _setDirty(String doc, bool dirty) => setState(() => dirty ? _dirty.add(doc) : _dirty.remove(doc));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AdminScaffold(
      title: 'Settings',
      selectedRoute: AdminRoutes.settings,
      body: DefaultTabController(
        length: _tabs.length,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Material(
            color: scheme.surface,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: AppColors.line(context),
              tabs: [
                for (final (doc, label, icon) in _tabs)
                  Tab(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Text(label),
                      if (_dirty.contains(doc)) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Tooltip(
                          message: 'Unsaved changes',
                          child: Container(
                            key: ValueKey('dirty-$doc'),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ]),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              GeneralSettingsTab(onDirtyChanged: (d) => _setDirty(SettingsDocs.general, d)),
              CitiesSettingsTab(onDirtyChanged: (d) => _setDirty(SettingsDocs.cities, d)),
              PaymentsSettingsTab(onDirtyChanged: (d) => _setDirty(SettingsDocs.payments, d)),
              ReferralSettingsTab(onDirtyChanged: (d) => _setDirty(SettingsDocs.referral, d)),
              SearchSettingsTab(onDirtyChanged: (d) => _setDirty(SettingsDocs.search, d)),
            ]),
          ),
        ]),
      ),
    );
  }
}
