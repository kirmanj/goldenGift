import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../l10n/l10n.dart';
import '../widgets/blocking_notice.dart';

/// Shown while `app_settings/general.maintenanceMode` is on (SRS §6.14).
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlockingNotice(
      icon: Icons.construction_rounded,
      title: l10n.maintenanceTitle,
      body: l10n.maintenanceBody,
      actionLabel: l10n.retry,
      onAction: () => context.go(AppRoutes.splash),
    );
  }
}
