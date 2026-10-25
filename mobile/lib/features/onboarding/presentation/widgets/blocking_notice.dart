import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';

/// Full-screen notice the user can't navigate away from (maintenance, forced update).
class BlockingNotice extends StatelessWidget {
  const BlockingNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GGLogo(size: 64, showWordmark: false),
                  const SizedBox(height: AppSpacing.xl),
                  Icon(icon, size: 48, color: AppColors.gold(context)),
                  const SizedBox(height: AppSpacing.md),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.heading2.copyWith(color: AppColors.text(context))),
                  const SizedBox(height: AppSpacing.sm),
                  Text(body,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context))),
                  if (actionLabel != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(label: actionLabel!, onPressed: onAction),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
