import 'package:flutter/material.dart';

import '../../../../core/constants/country_codes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/utils/validators.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/address_model.dart';
import '../../../../models/app_settings_model.dart';
import '../../../auth/presentation/providers/auth_flow.dart' show splitE164;
import '../../../profile/presentation/widgets/profile_formatters.dart';

/// Recipient phones are stored in E.164 (`+9647501234567`) so a non-Iraqi
/// number keeps its country code. Older / seeded addresses may hold only the
/// Iraqi national number (`7501234567`).
(CountryCode, String) splitAddressPhone(String phone) {
  final value = phone.trim();
  if (value.isEmpty) return (CountryCodes.iraq, '');
  if (!value.startsWith('+')) return (CountryCodes.iraq, Validators.normalizePhone(value));
  final (dial, national) = splitE164(value);
  final country = CountryCodes.all.where((c) => c.dialCode == dial).firstOrNull;
  return country == null ? (CountryCodes.iraq, value) : (country, national);
}

String addressPhoneValue(String input, CountryCode country) => Validators.e164(input, country);

/// "+964 750 123 4567" — render with `TextDirection.ltr`.
String addressPhoneDisplay(String phone) {
  final (country, national) = splitAddressPhone(phone);
  if (national.startsWith('+')) return national;
  return national.isEmpty ? '' : formatPhoneForDisplay(country.dialCode, national);
}

/// The localized city name; the raw id when the city is no longer listed.
String cityDisplayName(BuildContext context, List<CityModel> cities, String cityId) {
  final city = cities.where((c) => c.id == cityId).firstOrNull;
  final name = city?.name.of(context) ?? '';
  return name.isEmpty ? cityId : name;
}

/// One saved address (SRS §5.20): label + Default chip, recipient and phone
/// (always LTR), localized city, street line. Used by Saved Addresses and
/// the Checkout address section.
class AddressCard extends StatelessWidget {
  const AddressCard({
    super.key,
    required this.address,
    required this.cityName,
    this.trailing,
    this.onTap,
    this.showDefaultChip = true,
    this.outlined = true,
  });

  final AddressModel address;
  final String cityName;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDefaultChip;

  /// false inside another card (Checkout section).
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final phone = addressPhoneDisplay(address.phone);
    final line = address.oneLine;
    final content = Padding(
      padding: outlined
          ? const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.md, AppSpacing.xs, AppSpacing.md)
          : EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Icon(Icons.location_on_outlined, color: AppColors.gold(context)),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      address.label,
                      style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                    ),
                    if (showDefaultChip && address.isDefault)
                      Container(
                        key: ValueKey('default-chip-${address.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                        decoration: BoxDecoration(
                          color: AppColors.soft(context),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: AppColors.gold(context)),
                        ),
                        child: Text(
                          l10n.defaultAddress,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.goldText(context),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    Text(address.name, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text(context))),
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        textDirection: TextDirection.ltr,
                        style: AppTextStyles.bodyMedium.copyWith(color: muted),
                      ),
                  ],
                ),
                Text(cityName, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text(context))),
                if (line.isNotEmpty) Text(line, style: AppTextStyles.bodyMedium.copyWith(color: muted)),
                if (address.notes.trim().isNotEmpty)
                  Text(
                    address.notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (!outlined) return content;
    return Material(
      color: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: address.isDefault ? AppColors.gold(context) : AppColors.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
