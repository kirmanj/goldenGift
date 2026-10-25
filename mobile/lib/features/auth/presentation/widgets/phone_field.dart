import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/country_codes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';

/// "Mobile Number" pill input with the country-code picker inside the field
/// (flag + dial code, default +964 — SRS AUTH-1, IMG_4475). Phone numbers
/// are always laid out left-to-right, also in Arabic and Kurdish.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    required this.country,
    required this.onCountryChanged,
    this.label,
    this.errorText,
    this.enabled = true,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final CountryCode country;
  final ValueChanged<CountryCode> onCountryChanged;
  final String? label;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GGInput(
      label: label ?? l10n.mobileNumber,
      hint: l10n.enterYourNumber,
      controller: controller,
      errorText: errorText,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹ ]')),
        LengthLimitingTextInputFormatter(15),
      ],
      onSubmitted: onSubmitted,
      prefix: _CountryButton(
        country: country,
        enabled: enabled,
        onTap: () async {
          final picked = await showModalBottomSheet<CountryCode>(
            context: context,
            showDragHandle: true,
            backgroundColor: AppColors.card(context),
            builder: (_) => _CountryPicker(selected: country),
          );
          if (picked != null) onCountryChanged(picked);
        },
      ),
    );
  }
}

class _CountryButton extends StatelessWidget {
  const _CountryButton({required this.country, required this.onTap, required this.enabled});
  final CountryCode country;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${AppLocalizations.of(context)!.selectCountry}: ${country.name} ${country.dialCode}',
      // The label says it all; the flag / code / arrow would be read again.
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: const EdgeInsetsDirectional.only(start: AppSpacing.md, end: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.ltr,
            children: [
              Text(country.flag, style: AppTextStyles.sectionTitle),
              const SizedBox(width: AppSpacing.xs),
              Text(country.dialCode,
                  textDirection: TextDirection.ltr,
                  style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
              Icon(Icons.arrow_drop_down_rounded, color: AppColors.gold(context)),
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
                color: AppColors.line(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryPicker extends StatelessWidget {
  const _CountryPicker({required this.selected});
  final CountryCode selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(l10n.selectCountry, style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in CountryCodes.all)
                  ListTile(
                    leading: Text(c.flag, style: AppTextStyles.heading2),
                    title: Text(c.name, style: TextStyle(color: AppColors.text(context))),
                    trailing: Text(c.dialCode,
                        textDirection: TextDirection.ltr,
                        style: AppTextStyles.label.copyWith(
                            color: c.dialCode == selected.dialCode
                                ? AppColors.goldText(context)
                                : AppColors.textMuted(context))),
                    selected: c.dialCode == selected.dialCode,
                    onTap: () => Navigator.of(context).pop(c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
