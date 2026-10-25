import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/store_model.dart';

import '../../core/session/admin_session.dart';

/// What a partner sees instead of the dashboard while their store is not
/// `active` (SRS §5.25: pending approval, suspended, or no longer exists —
/// a rejected application deletes the store doc).
class SellerStoreGate extends ConsumerWidget {
  const SellerStoreGate({super.key, required this.session, this.store});
  final AdminSession session;
  final StoreModel? store;

  static (IconData, String, String) copyFor(StoreModel? store) => switch (store?.status) {
        StoreStatus.pendingApproval => (
            Icons.hourglass_top_rounded,
            'Your store is pending approval',
            'We are reviewing the application for “${store!.name.en}”. You will be notified as soon as it '
                'is approved — this page opens the dashboard automatically.',
          ),
        StoreStatus.suspended => (
            Icons.pause_circle_outline,
            'Your store is suspended',
            '“${store!.name.en}” is hidden from customers and its dashboard is closed for now. '
                'Contact Golden Gift support to reactivate it.',
          ),
        StoreStatus.active || null => (
            Icons.storefront_outlined,
            'Your store could not be found',
            'This partner account is not linked to an active store. If your application was declined, '
                'you can contact Golden Gift support.',
          ),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, title, message) = copyFor(store);
    final general = ref.watch(generalSettingsProvider).valueOrNull;
    final contacts = [
      if ((general?.supportPhone ?? '').isNotEmpty) general!.supportPhone,
      if ((general?.email ?? '').isNotEmpty) general!.email,
    ];
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 48, color: AppColors.gold(context)),
                  const SizedBox(height: AppSpacing.md),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted(context))),
                  if (contacts.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    SelectableText('Support: ${contacts.join(' · ')}', textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(session.email, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context))),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: () => ref.read(firebaseAuthProvider).signOut(),
                    child: const Text('Sign out'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Body for an admin-only module opened by a partner account.
class SellerModuleUnavailable extends StatelessWidget {
  const SellerModuleUnavailable({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 40, color: AppColors.textMuted(context)),
            const SizedBox(height: AppSpacing.md),
            const Text('This module is not available to partner accounts.', textAlign: TextAlign.center),
          ]),
        ),
      );
}
