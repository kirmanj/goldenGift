import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../../l10n/l10n.dart';

/// "Coming soon" screen for a route whose feature is switched off (Saved
/// Cards until an online gateway is enabled, SRS §5.21).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.detail, this.showAppBar = true});
  final String title;

  /// Route / query parameters, shown so deep links can be checked by eye.
  final String? detail;

  /// Tabs inside MainShell have no back button.
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showAppBar ? AppBar(title: Text(title)) : null,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: AppSpacing.screenPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppLocalizations.of(context)!.comingSoon,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context))),
                if (detail != null && kDebugMode) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(detail!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context))),
                ],
                if (kDebugMode) ...[
                  const SizedBox(height: AppSpacing.lg),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.goldText(context)),
                    onPressed: () => context.push('/dev/gallery'),
                    icon: const Icon(Icons.widgets_outlined),
                    label: const Text('Widget gallery (debug)'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
