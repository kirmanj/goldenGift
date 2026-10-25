import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../l10n/l10n.dart';
import '../../data/wallet_repository.dart';

/// "Use my credits (X available)" switch bound to [useCreditsProvider]
/// (SRS §5.10). Callers show it only for signed-in customers with credits > 0.
class UseCreditsToggle extends ConsumerWidget {
  const UseCreditsToggle({super.key, required this.available});

  final int available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final value = ref.watch(useCreditsProvider);
    final gold = AppColors.gold(context);
    void set(bool v) => ref.read(useCreditsProvider.notifier).state = v;

    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => set(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(Icons.stars_rounded, size: 22, color: gold),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.useMyCredits(CurrencyFormatter.format(available)),
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.text(context),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Switch(
                key: const ValueKey('use-credits-switch'),
                value: value,
                onChanged: set,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? AppColors.white : null,
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? gold : null,
                ),
                trackOutlineColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? gold : AppColors.line(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
