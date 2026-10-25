import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../l10n/l10n.dart';
import '../widgets/blocking_notice.dart';

/// The installed version is below `minAppVersion` (SRS §8 Versioning).
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(generalSettingsProvider).valueOrNull;
    final storeUrl = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => settings?.storeUrlIos ?? '',
      TargetPlatform.android => settings?.storeUrlAndroid ?? '',
      _ => '',
    };
    return BlockingNotice(
      icon: Icons.system_update_rounded,
      title: l10n.updateRequiredTitle,
      body: l10n.updateRequiredBody,
      actionLabel: storeUrl.isEmpty ? null : l10n.updateNow,
      onAction: storeUrl.isEmpty
          ? null
          : () => launchUrl(Uri.parse(storeUrl), mode: LaunchMode.externalApplication),
    );
  }
}
