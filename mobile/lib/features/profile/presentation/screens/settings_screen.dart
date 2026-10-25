import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/providers/auth_flow.dart';
import '../../data/datasources/user_repository.dart';
import '../providers/profile_platform_providers.dart';
import '../providers/profile_providers.dart';
import '../widgets/language_sheet.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/profile_menu_tile.dart';
import '../widgets/theme_mode_selector.dart';

/// Settings (SRS §5.13, AUTH-7, §8 Privacy): notifications, appearance,
/// language, legal links, version and account deletion.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Optimistic switch value while (and after) the write runs.
  bool? _notifications;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setNotifications(String uid, bool current, bool value) async {
    setState(() => _notifications = value);
    try {
      await ref.read(userRepositoryProvider).updateFields(uid, {'notificationsEnabled': value});
    } catch (_) {
      if (!mounted) return;
      setState(() => _notifications = current);
      _snack(AppLocalizations.of(context)!.somethingWentWrong);
    }
  }

  Future<void> _openLink(Uri uri) async {
    final l10n = AppLocalizations.of(context)!;
    bool opened;
    try {
      opened = await ref.read(externalLinkOpenerProvider)(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) _snack(l10n.somethingWentWrong);
  }

  /// SRS AUTH-7: confirm → `deleteAccount` callable → sign out → Sign Up.
  /// When the call fails nothing else changes (still signed in).
  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.deleteAccountTitle,
      message: l10n.deleteAccountBody,
      confirmLabel: l10n.deleteAccountConfirm,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final authFlow = ref.read(authFlowProvider);
    final closeProgress = showBlockingProgress(context);
    try {
      await ref.read(userRepositoryProvider).deleteAccount();
    } catch (_) {
      closeProgress();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
      return;
    }
    try {
      await authFlow.signOut();
    } catch (_) {
      // The Auth user is already gone server-side; continue to Sign Up.
    }
    closeProgress();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
    router.go(AppRoutes.signUp);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final profile = signedIn ? ref.watch(currentUserProfileProvider).valueOrNull : null;
    final themeMode = ref.watch(themeModeProvider);
    final version = ref.watch(appVersionLabelProvider).valueOrNull;
    final languageCode = Localizations.localeOf(context).languageCode;
    final muted = AppColors.textMuted(context);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.settings),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xl),
          children: [
            if (profile != null) ...[
              _Group(
                children: [
                  _NotificationsTile(
                    value: _notifications ?? profile.notificationsEnabled,
                    onChanged: (v) =>
                        _setNotifications(profile.uid, _notifications ?? profile.notificationsEnabled, v),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _SectionLabel(l10n.appearance),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
              child: ThemeModeSelector(
                value: themeMode,
                onChanged: (mode) => ref.read(themeModeProvider.notifier).setMode(mode),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _Group(
              children: [
                ProfileMenuTile(
                  icon: Icons.translate_rounded,
                  tone: ProfileTileTone.warning,
                  title: l10n.language,
                  subtitle: languageName(l10n, languageCode),
                  subtitleColor: muted,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md),
                  onTap: () => showLanguageSheet(context, ref),
                ),
                ProfileMenuTile(
                  icon: Icons.privacy_tip_outlined,
                  tone: ProfileTileTone.neutral,
                  title: l10n.privacyPolicy,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md),
                  onTap: () => _openLink(ProfileLinks.privacyPolicy),
                ),
                ProfileMenuTile(
                  icon: Icons.description_outlined,
                  tone: ProfileTileTone.neutral,
                  title: l10n.termsOfService,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md),
                  onTap: () => _openLink(ProfileLinks.termsOfService),
                ),
              ],
            ),
            if (signedIn) ...[
              const SizedBox(height: AppSpacing.lg),
              _Group(
                children: [
                  ProfileMenuTile(
                    key: const ValueKey('settings-delete-account'),
                    icon: Icons.delete_forever_rounded,
                    tone: ProfileTileTone.error,
                    title: l10n.deleteAccount,
                    destructive: true,
                    showChevron: false,
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md),
                    onTap: _deleteAccount,
                  ),
                ],
              ),
            ],
            if (version != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.appVersion(version),
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationsTile extends StatelessWidget {
  const _NotificationsTile({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final gold = AppColors.gold(context);
    return ProfileMenuTile(
      key: const ValueKey('settings-notifications'),
      icon: Icons.notifications_rounded,
      title: l10n.notificationsSetting,
      subtitle: l10n.notificationsSettingSubtitle,
      subtitleColor: AppColors.textMuted(context),
      showChevron: false,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md),
      onTap: () => onChanged(!value),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
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
    );
  }
}

/// Rounded card that groups related rows.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
      child: Material(
        color: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: AppColors.line(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, indent: 76, color: AppColors.line(context)),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.screenHorizontal, 0, AppSpacing.screenHorizontal, AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(text, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
      ),
    );
  }
}
