import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/app_settings_model.dart';

import '../../core/widgets/form_widgets.dart';
import 'settings_data.dart';
import 'settings_doc_editor.dart';

/// `app_settings/referral` (SRS §5.19). Amounts are provisional (SRS §12 item 3).
class ReferralSettingsTab extends StatelessWidget {
  const ReferralSettingsTab({super.key, this.onDirtyChanged});
  final ValueChanged<bool>? onDirtyChanged;

  @override
  Widget build(BuildContext context) => SettingsDocEditor<ReferralSettings>(
        docId: SettingsDocs.referral,
        fromMap: ReferralSettings.fromMap,
        toMap: (r) => r.toMap(),
        validate: validateReferralSettings,
        onDirtyChanged: onDirtyChanged,
        builder: (context, d) {
          final r = d.value;
          return SectionCard(title: 'Invite & earn', children: [
            const SettingsNote(
              'Provisional — owner to confirm amounts (SRS §12 item 3). The friend gets the join bonus on '
              'sign-up with a code; the referrer gets the order bonus once that friend\'s first order is delivered and paid.',
              icon: Icons.pending_outlined,
              color: AppColors.warning,
            ),
            const SizedBox(height: AppSpacing.md),
            FieldGrid(children: [
              MoneyField(
                label: 'Join bonus — friend (provisional)',
                value: r.joinBonus,
                onChanged: (v) => d.update((s) => s.copyWith(joinBonus: v ?? 0)),
              ),
              MoneyField(
                label: 'Order bonus — referrer (provisional)',
                value: r.orderBonus,
                onChanged: (v) => d.update((s) => s.copyWith(orderBonus: v ?? 0)),
              ),
              CountField(
                label: 'Max referrals per month (provisional)',
                helper: 'Per referrer. 0 = no limit.',
                value: r.maxReferralsPerMonth,
                onChanged: (v) => d.update((s) => s.copyWith(maxReferralsPerMonth: v)),
              ),
              CountField(
                label: 'Credits expire after, days (provisional)',
                helper: '0 = credits never expire.',
                value: r.creditsExpiryDays,
                onChanged: (v) => d.update((s) => s.copyWith(creditsExpiryDays: v)),
              ),
            ]),
          ]);
        },
      );
}

/// Whole non-negative number.
class CountField extends StatelessWidget {
  const CountField({super.key, required this.label, required this.value, required this.onChanged, this.helper});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: '$value',
        decoration: InputDecoration(labelText: '$label *', helperText: helper),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        validator: validateCount,
        onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
      );
}
