import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/address_model.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/address_repository.dart';
import '../widgets/address_card.dart';

enum _AddressAction { edit, setDefault, delete }

/// Saved Addresses (SRS §5.20). In [selectMode] (opened from Checkout) a tap
/// returns the address with `context.pop(address)`; a newly added address
/// is returned straight away.
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key, this.selectMode = false});

  /// Opened from checkout: tapping an address returns it (context.pop(address)).
  final bool selectMode;

  Future<void> _add(BuildContext context) async {
    final saved = await context.push<AddressModel>(AppRoutes.addressForm);
    if (saved != null && selectMode && context.mounted) context.pop(saved);
  }

  Future<void> _edit(BuildContext context, AddressModel address) =>
      context.push<AddressModel>('${AppRoutes.addressForm}?id=${Uri.encodeQueryComponent(address.id)}');

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context)!.somethingWentWrong;
    try {
      await action();
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, AddressModel address, _AddressAction action) async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    final repo = ref.read(addressRepositoryProvider);
    switch (action) {
      case _AddressAction.edit:
        await _edit(context, address);
      case _AddressAction.setDefault:
        await _run(context, () => repo.setDefault(uid, address.id));
      case _AddressAction.delete:
        final l10n = AppLocalizations.of(context)!;
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.card(dialogContext),
            title: Text(l10n.deleteAddressConfirm,
                style: AppTextStyles.heading3.copyWith(color: AppColors.text(dialogContext))),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.cancel, style: TextStyle(color: AppColors.textMuted(dialogContext))),
              ),
              TextButton(
                key: const ValueKey('confirm-delete-address'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.delete, style: TextStyle(color: errorText(dialogContext))),
              ),
            ],
          ),
        );
        if (ok == true && context.mounted) await _run(context, () => repo.delete(uid, address.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final bottom = math.max(96.0, MediaQuery.paddingOf(context).bottom + 88);

    Widget body;
    if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.location_on_rounded);
    } else {
      body = ref.watch(addressesProvider).when(
            loading: () => const SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
              child: SkeletonLoader.list(count: 3),
            ),
            error: (_, __) => CenteredScroll(child: ErrorState(onRetry: () => ref.invalidate(addressesProvider))),
            data: (list) => list.isEmpty
                ? CenteredScroll(
                    child: EmptyState(
                      title: l10n.noAddressesTitle,
                      subtitle: l10n.noAddressesBody,
                      icon: Icons.location_on_outlined,
                      ctaLabel: l10n.addAddress,
                      ctaIcon: Icons.add_rounded,
                      onCta: () => _add(context),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                        AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                    itemBuilder: (context, i) {
                      final address = list[i];
                      return AddressCard(
                        key: ValueKey('address-${address.id}'),
                        address: address,
                        cityName: cityDisplayName(context, cities, address.city),
                        onTap: selectMode ? () => context.pop(address) : () => _edit(context, address),
                        trailing: PopupMenuButton<_AddressAction>(
                          key: ValueKey('address-menu-${address.id}'),
                          icon: Icon(Icons.more_vert_rounded, color: AppColors.textMuted(context)),
                          color: AppColors.card(context),
                          onSelected: (action) => _onAction(context, ref, address, action),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: _AddressAction.edit, child: Text(l10n.edit)),
                            if (!address.isDefault)
                              PopupMenuItem(value: _AddressAction.setDefault, child: Text(l10n.setAsDefault)),
                            PopupMenuItem(
                              value: _AddressAction.delete,
                              child: Text(l10n.delete, style: TextStyle(color: errorText(context))),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          );
    }

    final showFab = signedIn && (ref.watch(addressesProvider).valueOrNull?.isNotEmpty ?? false);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.savedAddresses),
      body: body,
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              key: const ValueKey('add-address-fab'),
              backgroundColor: AppColors.gold(context),
              foregroundColor: AppColors.textOnPrimary,
              shape: const StadiumBorder(),
              onPressed: () => _add(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addAddress, style: AppTextStyles.label.copyWith(color: AppColors.textOnPrimary)),
            )
          : null,
    );
  }
}
