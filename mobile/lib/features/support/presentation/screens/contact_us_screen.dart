import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../orders/presentation/widgets/order_card.dart' show popOrGo;
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_platform_providers.dart';
import '../widgets/contact_card.dart';
import '../widgets/support_message_form.dart';

/// Contact Us (SRS §5.24): WhatsApp, phone, email and Instagram from
/// `app_settings/general`; empty channels are hidden. Below them, the in-app
/// message form (`special_requests` with `type = support`).
class ContactUsScreen extends ConsumerWidget {
  const ContactUsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context)!.somethingWentWrong;
    var opened = false;
    try {
      opened = await ref.read(externalLinkOpenerProvider)(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    final settings = ref.watch(generalSettingsProvider);

    final channels = [
      (ContactChannel.whatsapp, Icons.chat_rounded, l10n.contactWhatsapp),
      (ContactChannel.phone, Icons.call_outlined, l10n.contactCall),
      (ContactChannel.email, Icons.mail_outline_rounded, l10n.contactEmail),
      (ContactChannel.instagram, Icons.camera_alt_outlined, l10n.contactInstagram),
    ];

    Widget body;
    if (settings.hasError && !settings.hasValue) {
      body = CenteredScroll(child: ErrorState(onRetry: () => ref.invalidate(generalSettingsProvider)));
    } else if (!settings.hasValue) {
      body = const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
        child: SkeletonLoader.list(count: 4),
      );
    } else {
      final s = settings.requireValue;
      body = ListView(
        key: const ValueKey('contact-list'),
        padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
        children: [
          Text(l10n.contactUsBody, style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context))),
          const SizedBox(height: AppSpacing.lg),
          for (final (channel, icon, title) in channels)
            if (contactUri(channel, s) case final uri?)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm + AppSpacing.xs),
                child: ContactCard(
                  key: ValueKey('contact-${channel.name}'),
                  icon: icon,
                  title: title,
                  value: contactDisplayValue(channel, s),
                  onTap: () => _open(context, ref, uri),
                ),
              ),
          const SizedBox(height: AppSpacing.md),
          const SupportMessageForm(),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        title: l10n.contactUs,
        showBack: true,
        onBack: () => popOrGo(context, AppRoutes.mainTab(2)),
      ),
      body: body,
    );
  }
}
