import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/country_codes.dart';
import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/app_settings_model.dart';
import '../../../../models/store_model.dart';
import '../../../../models/user_model.dart';
import '../../../addresses/presentation/widgets/address_card.dart' show cityDisplayName;
import '../../../auth/presentation/widgets/auth_messages.dart';
import '../../../auth/presentation/widgets/phone_field.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../product_details/domain/product_configuration.dart';
import '../../../profile/presentation/providers/profile_platform_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../profile/presentation/widgets/profile_pickers.dart' show showCityPickerSheet;
import '../../../special_requests/presentation/widgets/picked_photos_field.dart';
import '../../data/partner_repository.dart';

/// Where approved partners manage their store (admin dashboard, seller view).
const partnerDashboardUrl = 'https://goldengift-admin.web.app';

/// `@handle` / `handle` → `handle`; null when it isn't a valid Instagram name.
String? normalizeInstagram(String value) {
  final v = value.trim().replaceFirst(RegExp('^@'), '');
  if (v.isEmpty) return '';
  return RegExp(r'^[A-Za-z0-9._]{1,30}$').hasMatch(v) ? v : null;
}

enum _F { storeName, ownerName, phone, city, category, instagram }

/// Become a Partner — "Sell on Golden Gift" (SRS §5.25): hero, benefits and
/// the application form (store, owner, phone, city, what they sell,
/// Instagram, up to 5 sample photos) → `submitPartnerApplication`. Once the
/// account has a store, its status card replaces the form.
class BecomePartnerScreen extends ConsumerStatefulWidget {
  const BecomePartnerScreen({super.key});

  @override
  ConsumerState<BecomePartnerScreen> createState() => _BecomePartnerScreenState();
}

class _BecomePartnerScreenState extends ConsumerState<BecomePartnerScreen> {
  final _storeName = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _cityText = TextEditingController();
  final _category = TextEditingController();
  final _instagram = TextEditingController();
  CountryCode _country = CountryCodes.iraq;
  String _cityId = '';
  List<PickedPhoto> _photos = const [];
  Map<_F, String?> _errors = const {};
  bool _submitting = false;
  bool _submitted = false;
  double? _progress;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<UserModel?>>(currentUserProfileProvider, (_, next) => _prefill(next.valueOrNull),
        fireImmediately: true);
  }

  void _prefill(UserModel? profile) {
    if (_prefilled || profile == null) return;
    _prefilled = true;
    if (_ownerName.text.isEmpty) _ownerName.text = profile.name;
    if (_phone.text.isEmpty && profile.phone.isNotEmpty) {
      _phone.text = profile.phone;
      _country = CountryCodes.byDialCode(profile.countryCode);
    }
    if (_cityId.isEmpty && (profile.city ?? '').isNotEmpty) _cityId = profile.city!;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_storeName, _ownerName, _phone, _cityText, _category, _instagram]) {
      c.dispose();
    }
    super.dispose();
  }

  void _clear(_F field) {
    if (_errors[field] != null) setState(() => _errors = {..._errors, field: null});
  }

  Future<void> _pickCity() async {
    final city = await showCityPickerSheet(context, selectedId: _cityId.isEmpty ? null : _cityId);
    if (city == null || !mounted) return;
    setState(() {
      _cityId = city.id;
      _errors = {..._errors, _F.city: null};
    });
  }

  Map<_F, String?> _validate(AppLocalizations l10n, List<CityModel> cities) {
    final store = _storeName.text.trim();
    return {
      _F.storeName: store.isEmpty
          ? l10n.errorRequired
          : (store.runes.length < 2 || store.runes.length > 60 ? l10n.partnerStoreNameLength : null),
      _F.ownerName: l10n.validation(Validators.name(_ownerName.text)),
      _F.phone: l10n.validation(Validators.phone(_phone.text, _country)),
      _F.city: cities.any((c) => c.id == _cityId && c.isActive) ? null : l10n.errorRequired,
      _F.category: _category.text.trim().isEmpty ? l10n.errorRequired : null,
      _F.instagram: normalizeInstagram(_instagram.text) == null ? l10n.partnerInstagramInvalid : null,
    };
  }

  Future<void> _submit(List<CityModel> cities) async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context)!;
    final errors = _validate(l10n, cities);
    if (errors.values.any((e) => e != null)) {
      setState(() => _errors = errors);
      showOrderSnack(context, l10n.giftCardFixErrors);
      return;
    }
    if (!await requireSignIn(context, ref)) return;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null || !mounted) return;
    FocusScope.of(context).unfocus();
    final photos = _photos;
    setState(() {
      _errors = const {};
      _submitting = true;
      _progress = photos.isEmpty ? null : 0;
    });
    var uploading = photos.isNotEmpty;
    try {
      final urls = photos.isEmpty
          ? const <String>[]
          : await ref.read(imageUploadServiceProvider).upload(
                'partner_applications/$uid',
                photos.take(PartnerApplication.maxPhotos).toList(),
                onProgress: (p) {
                  if (mounted) setState(() => _progress = p);
                },
              );
      uploading = false;
      if (mounted) setState(() => _progress = null);
      await ref.read(partnerRepositoryProvider).submit(PartnerApplication(
            storeName: _storeName.text,
            ownerName: _ownerName.text,
            phone: Validators.e164(_phone.text, _country),
            city: _cityId,
            category: _category.text,
            instagram: normalizeInstagram(_instagram.text),
            samplePhotos: urls,
          ));
      if (mounted) setState(() => _submitted = true);
    } on PartnerFailure catch (f) {
      if (!mounted) return;
      showOrderSnack(context, switch (f.reason) {
        PartnerFailureReason.alreadyApplied => l10n.partnerAlreadyApplied,
        PartnerFailureReason.invalid => l10n.partnerInvalid,
        PartnerFailureReason.unavailable => l10n.partnerUnavailable,
        PartnerFailureReason.rateLimited => l10n.authErrorTooManyRequests,
        PartnerFailureReason.unknown => l10n.somethingWentWrong,
      });
    } catch (_) {
      if (mounted) showOrderSnack(context, uploading ? l10n.photoUploadFailed : l10n.somethingWentWrong);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    final signedIn = ref.watch(isSignedInProvider);
    final storeAsync = signedIn ? ref.watch(myPartnerStoreProvider) : const AsyncValue<StoreModel?>.data(null);
    final cities = ref.watch(citiesProvider).valueOrNull ?? const <CityModel>[];

    final List<Widget> tail;
    final store = storeAsync.valueOrNull;
    if (!storeAsync.hasValue && !storeAsync.hasError) {
      tail = const [SkeletonLoader.box(height: 220, radius: AppRadius.lg)];
    } else if (store != null) {
      tail = [PartnerStatusCard(store: store)];
    } else if (_submitted) {
      tail = [
        _MessageCard(
          key: const ValueKey('partner-thanks'),
          icon: Icons.check_circle_outline_rounded,
          title: l10n.partnerThanksTitle,
          body: l10n.partnerThanksBody,
        ),
      ];
    } else {
      tail = [_form(context, l10n, cities)];
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.partnerScreenTitle),
      body: ListView(
        key: const ValueKey('partner-list'),
        padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
        children: [
          const _Hero(),
          const SizedBox(height: AppSpacing.lg),
          const _Benefits(),
          const SizedBox(height: AppSpacing.lg),
          ...tail,
        ],
      ),
    );
  }

  Widget _form(BuildContext context, AppLocalizations l10n, List<CityModel> cities) {
    final cityName = _cityId.isEmpty ? '' : cityDisplayName(context, cities, _cityId);
    if (_cityText.text != cityName) _cityText.text = cityName;
    const gap = SizedBox(height: AppSpacing.md);
    return OrderSection(
      key: const ValueKey('partner-form'),
      title: l10n.partnerFormTitle,
      icon: Icons.storefront_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GGInput(
            key: const ValueKey('partner-store-name'),
            label: l10n.partnerStoreName,
            controller: _storeName,
            textCapitalization: TextCapitalization.words,
            enabled: !_submitting,
            errorText: _errors[_F.storeName],
            onChanged: (_) => _clear(_F.storeName),
          ),
          gap,
          GGInput(
            key: const ValueKey('partner-owner-name'),
            label: l10n.partnerOwnerName,
            hint: l10n.enterYourName,
            controller: _ownerName,
            textCapitalization: TextCapitalization.words,
            enabled: !_submitting,
            errorText: _errors[_F.ownerName],
            onChanged: (_) => _clear(_F.ownerName),
          ),
          gap,
          PhoneField(
            key: const ValueKey('partner-phone'),
            controller: _phone,
            country: _country,
            enabled: !_submitting,
            errorText: _errors[_F.phone],
            onCountryChanged: (c) => setState(() {
              _country = c;
              _errors = {..._errors, _F.phone: null};
            }),
          ),
          gap,
          GGInput(
            key: const ValueKey('partner-city'),
            label: l10n.city,
            hint: l10n.selectCity,
            controller: _cityText,
            readOnly: true,
            enabled: !_submitting,
            onTap: _pickCity,
            errorText: _errors[_F.city],
            suffix: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.gold(context)),
          ),
          gap,
          GGInput(
            key: const ValueKey('partner-category'),
            label: l10n.partnerCategory,
            hint: l10n.partnerCategoryHint,
            controller: _category,
            textCapitalization: TextCapitalization.sentences,
            enabled: !_submitting,
            errorText: _errors[_F.category],
            onChanged: (_) => _clear(_F.category),
          ),
          gap,
          GGInput(
            key: const ValueKey('partner-instagram'),
            label: '${l10n.contactInstagram} ${l10n.optionalLabel}',
            hint: '@yourstore',
            controller: _instagram,
            keyboardType: TextInputType.url,
            enabled: !_submitting,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            errorText: _errors[_F.instagram],
            onChanged: (_) => _clear(_F.instagram),
          ),
          gap,
          Text(
            '${l10n.partnerSamplePhotos} ${l10n.optionalLabel}',
            style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
          ),
          const SizedBox(height: AppSpacing.sm),
          PickedPhotosField(
            keyPrefix: 'partner-photos',
            photos: _photos,
            max: PartnerApplication.maxPhotos,
            enabled: !_submitting,
            onAdd: (p) => setState(() => _photos = [..._photos, p].take(PartnerApplication.maxPhotos).toList()),
            onRemove: (i) => setState(() => _photos = [..._photos]..removeAt(i)),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_progress != null) ...[
            UploadProgressLine(progress: _progress!),
            const SizedBox(height: AppSpacing.sm),
          ],
          PrimaryButton(
            key: const ValueKey('partner-submit'),
            label: l10n.partnerSubmit,
            icon: Icons.send_rounded,
            isLoading: _submitting,
            onPressed: () => _submit(cities),
          ),
        ],
      ),
    );
  }
}

/// The account's store: pending review, live (→ dashboard) or suspended.
class PartnerStatusCard extends ConsumerWidget {
  const PartnerStatusCard({super.key, required this.store});
  final StoreModel store;

  Future<void> _openDashboard(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context)!.somethingWentWrong;
    var opened = false;
    try {
      opened = await ref.read(externalLinkOpenerProvider)(Uri.parse(partnerDashboardUrl));
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final name = store.name.of(context);
    return switch (store.status) {
      StoreStatus.pendingApproval => _MessageCard(
          key: const ValueKey('partner-status-pending'),
          icon: Icons.hourglass_top_rounded,
          title: l10n.partnerPendingTitle,
          body: l10n.partnerPendingBody(name.isEmpty ? l10n.partnerYourStore : name),
        ),
      StoreStatus.active => _MessageCard(
          key: const ValueKey('partner-status-active'),
          icon: Icons.storefront_rounded,
          title: l10n.partnerActiveTitle,
          body: l10n.partnerActiveBody,
          extra: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      partnerDashboardUrl,
                      textDirection: TextDirection.ltr,
                      style: AppTextStyles.label.copyWith(color: AppColors.goldText(context)),
                    ),
                  ),
                  GGCircleButton(
                    key: const ValueKey('partner-copy-dashboard'),
                    icon: Icons.copy_rounded,
                    size: 40,
                    iconSize: 18,
                    iconColor: AppColors.gold(context),
                    tooltip: l10n.partnerCopyLink,
                    onPressed: () {
                      unawaited(Clipboard.setData(const ClipboardData(text: partnerDashboardUrl)));
                      showOrderSnack(context, l10n.codeCopied);
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                key: const ValueKey('partner-open-dashboard'),
                label: l10n.partnerOpenDashboard,
                icon: Icons.open_in_new_rounded,
                onPressed: () => _openDashboard(context, ref),
              ),
            ],
          ),
        ),
      StoreStatus.suspended => _MessageCard(
          key: const ValueKey('partner-status-suspended'),
          icon: Icons.block_rounded,
          title: l10n.partnerSuspendedTitle,
          body: l10n.partnerSuspendedBody,
          extra: PrimaryButton(
            key: const ValueKey('partner-contact-support'),
            label: l10n.contactSupport,
            icon: Icons.support_agent_rounded,
            onPressed: () => context.push(AppRoutes.contactUs),
          ),
        ),
    };
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({super.key, required this.icon, required this.title, required this.body, this.extra});

  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return OrderSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
                child: Icon(icon, color: AppColors.gold(context), size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(body, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context))),
                  ],
                ),
              ),
            ],
          ),
          if (extra != null) ...[
            const SizedBox(height: AppSpacing.md),
            extra!,
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.partnerHeroTitle,
                    style: AppTextStyles.heading2.copyWith(color: AppColors.textOnPrimary),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.partnerHeroBody,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textOnPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storefront_rounded, size: 34, color: AppColors.textOnPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      (Icons.groups_rounded, l10n.partnerBenefitReachTitle, l10n.partnerBenefitReachBody),
      (Icons.dashboard_customize_outlined, l10n.partnerBenefitDashboardTitle, l10n.partnerBenefitDashboardBody),
      (Icons.auto_awesome_rounded, l10n.partnerBenefitPersonalTitle, l10n.partnerBenefitPersonalBody),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.partnerWhyTitle, style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        for (final (icon, title, body) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm + AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.soft(context), borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(icon, color: AppColors.gold(context)),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
                      Text(body, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
