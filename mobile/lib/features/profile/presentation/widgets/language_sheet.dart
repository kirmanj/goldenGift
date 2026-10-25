import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/locale_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';
import '../../data/datasources/user_repository.dart';
import '../providers/profile_providers.dart';

/// Name of a supported language in its own script ("English", "العربية", "کوردی").
String languageName(AppLocalizations l10n, String code) => switch (code) {
      'ar' => l10n.languageArabic,
      'ckb' => l10n.languageKurdish,
      _ => l10n.languageEnglish,
    };

/// Profile ▸ Language (SRS §4.2): pick English / العربية / کوردی. Applies
/// immediately, is kept on the device, and — when signed in — is also saved
/// to `users/{uid}.locale` for notifications (failures are ignored).
Future<void> showLanguageSheet(BuildContext context, WidgetRef ref) async {
  final current = ref.read(localeProvider).languageCode;
  final code = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.card(context),
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => LanguageSheet(current: current),
  );
  if (code == null || code == current) return;

  // Read everything before the switch: the whole tree rebuilds in the new locale.
  final notifier = ref.read(localeProvider.notifier);
  final repository = ref.read(userRepositoryProvider);
  final uid = ref.read(isSignedInProvider) ? ref.read(currentUserProfileProvider).valueOrNull?.uid : null;
  await notifier.setLocale(code);
  if (uid != null) {
    unawaited(repository.updateFields(uid, {'locale': code}).then((_) {}, onError: (_) {}));
  }
}

class LanguageSheet extends StatelessWidget {
  const LanguageSheet({super.key, required this.current});

  final String current;

  static const codes = ['en', 'ar', 'ckb'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal, 0, AppSpacing.screenHorizontal, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.chooseLanguage,
                textAlign: TextAlign.center,
                style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final code in codes) ...[
              _LanguageOption(
                code: code,
                label: languageName(l10n, code),
                selected: code == current,
                onTap: () => Navigator.of(context).pop(code),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    // Each name is shown in its own script and font.
    final font = AppTextStyles.fontFamily(Locale(code));
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? AppColors.soft(context) : AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: selected ? gold : AppColors.line(context), width: selected ? 1.4 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('language-$code'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTextStyles.label.copyWith(
                        fontSize: 16,
                        fontFamily: font,
                        color: AppColors.text(context),
                      ),
                    ),
                  ),
                  if (selected) Icon(Icons.check_circle_rounded, color: gold, size: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
