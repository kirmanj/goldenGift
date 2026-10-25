import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'info_banner.dart';
import 'primary_button.dart';

/// Error state with icon, message and Retry (SRS §4.8 — every list screen
/// has an error state with Retry). [message] defaults to the localized
/// "Something went wrong"; Retry shows when [onRetry] is set.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.message,
    this.details,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  final String? message;

  /// Optional secondary line (e.g. "Check your connection").
  final String? details;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: InfoBanner.softColor(context, InfoBannerType.error),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: AppColors.error),
              ),
            ),
            const SizedBox(height: AppSpacing.md + AppSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                message ?? l10n.somethingWentWrong,
                textAlign: TextAlign.center,
                style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
              ),
            ),
            if (details != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                details!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: l10n.retry,
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
