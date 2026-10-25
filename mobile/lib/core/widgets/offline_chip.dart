import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Subtle "Offline — showing saved items" pill (SRS §4.8): catalogue screens
/// keep showing cached data and add this chip while the server is unreachable.
/// Soft surface + 1 px border so it reads in both light and dark mode.
class OfflineChip extends StatelessWidget {
  const OfflineChip({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textMuted(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.sm + AppSpacing.xs,
          AppSpacing.xs + AppSpacing.xxs,
          AppSpacing.md - AppSpacing.xxs,
          AppSpacing.xs + AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: AppColors.field(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.line(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 16, color: muted),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Flexible(
              child: Text(
                AppLocalizations.of(context)!.offlineChip,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
