import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../models/app_settings_model.dart';

enum ContactChannel { whatsapp, phone, email, instagram }

/// Links for the support channels in `app_settings/general` (SRS §5.24);
/// null when the value is empty or unusable.
Uri? contactUri(ContactChannel channel, GeneralSettings settings) {
  switch (channel) {
    case ContactChannel.whatsapp:
      final digits = settings.whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.isEmpty ? null : Uri.parse('https://wa.me/$digits');
    case ContactChannel.phone:
      final phone = settings.supportPhone.replaceAll(RegExp(r'[^0-9+]'), '');
      return phone.isEmpty ? null : Uri(scheme: 'tel', path: phone);
    case ContactChannel.email:
      final email = settings.email.trim();
      return email.isEmpty ? null : Uri(scheme: 'mailto', path: email);
    case ContactChannel.instagram:
      final value = settings.instagram.trim();
      if (value.isEmpty) return null;
      if (value.startsWith('http://') || value.startsWith('https://')) return Uri.tryParse(value);
      final handle = value.replaceFirst('@', '').replaceAll(RegExp(r'[/\s]'), '');
      return handle.isEmpty ? null : Uri.parse('https://instagram.com/$handle');
  }
}

/// What the card shows under its title.
String contactDisplayValue(ContactChannel channel, GeneralSettings settings) => switch (channel) {
      ContactChannel.whatsapp => settings.whatsapp.trim(),
      ContactChannel.phone => settings.supportPhone.trim(),
      ContactChannel.email => settings.email.trim(),
      ContactChannel.instagram => () {
          final v = settings.instagram.trim();
          return v.startsWith('http') || v.startsWith('@') ? v : '@$v';
        }(),
    };

class ContactCard extends StatelessWidget {
  const ContactCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
                  child: Icon(icon, color: AppColors.gold(context)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
                      Text(
                        value,
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textMuted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
