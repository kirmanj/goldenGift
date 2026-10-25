import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/user_model.dart';
import '../../../auth/presentation/widgets/auth_messages.dart';
import '../../data/datasources/user_repository.dart';
import '../providers/profile_platform_providers.dart';
import '../providers/profile_providers.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/profile_formatters.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_pickers.dart';
import '../widgets/profile_value_field.dart';

/// Edit Profile (SRS §5.14): photo, name, email, phone (read-only — changed
/// through the OTP flow), birthday, gender, city. Save writes
/// `UserModel.toProfileMap` (which recomputes `profileCompleted`).
///
/// The photo is saved as soon as it is uploaded (re-uploading replaces
/// `users/{uid}/avatar.jpg`, so the old URL would not survive a discard).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();

  /// The profile as loaded (or last saved); edits are compared against it.
  UserModel? _original;
  DateTime? _birthday;
  String? _gender;
  String? _city;
  String? _photoUrl;

  ValidationError? _nameError;
  ValidationError? _emailError;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    if (profile != null) _load(profile);
    _name.addListener(_onText);
    _email.addListener(_onText);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  void _load(UserModel profile) {
    _original = profile;
    _name.text = profile.name;
    _email.text = profile.email ?? '';
    _birthday = profile.birthday;
    _gender = profile.gender;
    _city = profile.city;
    _photoUrl = profile.photoUrl;
  }

  String? get _emailValue {
    final email = _email.text.trim();
    return email.isEmpty ? null : email;
  }

  bool get _dirty {
    final original = _original;
    if (original == null) return false;
    return _name.text.trim() != original.name.trim() ||
        _emailValue != (original.email ?? '').trim().nullIfEmpty ||
        !sameDay(_birthday, original.birthday) ||
        _gender != original.gender ||
        _city != original.city;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changePhoto() async {
    final uid = _original?.uid;
    if (uid == null || _uploading) return;
    final l10n = AppLocalizations.of(context)!;
    final source = await showAvatarSourceSheet(context);
    if (source == null || !mounted) return;

    final Uint8List? bytes;
    try {
      bytes = await ref.read(avatarPickerProvider).pick(source);
    } catch (_) {
      if (mounted) _snack(l10n.photoUploadFailed);
      return;
    }
    if (bytes == null || !mounted) return;
    if (bytes.isEmpty || bytes.length > maxAvatarBytes) {
      _snack(l10n.photoUploadFailed);
      return;
    }

    setState(() => _uploading = true);
    try {
      final repository = ref.read(userRepositoryProvider);
      final url = await repository.uploadAvatar(uid, bytes);
      await repository.updateFields(uid, {'photoUrl': url});
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _original = _original?.copyWith(photoUrl: Optional(url));
      });
    } catch (_) {
      // Storage may not be set up yet; the profile keeps its old photo.
      if (mounted) _snack(l10n.photoUploadFailed);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = _birthday;
    var initial = current == null
        ? DateTime(today.year - 20, today.month, today.day)
        : DateTime(current.year, current.month, current.day);
    if (initial.isAfter(today)) initial = today;
    if (initial.isBefore(DateTime(1900))) initial = DateTime(1900);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: AppLocalizations.of(context)!.selectBirthday,
    );
    if (picked != null && mounted) setState(() => _birthday = birthdayValue(picked));
  }

  Future<void> _pickCity() async {
    final city = await showCityPickerSheet(context, selectedId: _city);
    if (city != null && mounted) setState(() => _city = city.id);
  }

  Future<void> _save() async {
    final original = _original;
    if (original == null || _saving) return;
    final l10n = AppLocalizations.of(context)!;
    FocusScope.of(context).unfocus();
    final nameError = Validators.name(_name.text);
    final emailError = Validators.email(_email.text);
    setState(() {
      _nameError = nameError;
      _emailError = emailError;
    });
    if (nameError != null || emailError != null) return;

    // Start from the live document so fields changed elsewhere (phone,
    // notifications, locale) are not overwritten with stale values.
    final base = ref.read(currentUserProfileProvider).valueOrNull ?? original;
    final updated = base.copyWith(
      name: _name.text.trim(),
      email: Optional(_emailValue),
      photoUrl: Optional(_photoUrl),
      birthday: Optional(_birthday),
      gender: Optional(_gender),
      city: Optional(_city),
    );

    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).updateProfile(updated);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(l10n.somethingWentWrong);
      }
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = false;
      _original = updated;
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
    popOrGoMain(context);
  }

  Future<void> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context)!;
    final discard = await showConfirmDialog(
      context,
      title: l10n.unsavedChanges,
      confirmLabel: l10n.discard,
      destructive: true,
    );
    if (discard && mounted) popOrGoMain(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The profile may still be loading when the screen opens.
    ref.listen<AsyncValue<UserModel?>>(currentUserProfileProvider, (_, next) {
      final profile = next.valueOrNull;
      if (_original == null && profile != null) setState(() => _load(profile));
    });
    final profileAsync = ref.watch(currentUserProfileProvider);

    final Widget body;
    if (_original != null) {
      body = _form(context, l10n, profileAsync.valueOrNull ?? _original!);
    } else if (profileAsync.hasError) {
      body = ErrorState(onRetry: () => ref.invalidate(currentUserProfileProvider));
    } else if (profileAsync.isLoading) {
      body = const Padding(
        padding: AppSpacing.screenPadding,
        child: SkeletonLoader.list(count: 5),
      );
    } else {
      // Signed out (or no profile document): nothing to edit.
      body = ErrorState(
        message: l10n.signInToContinue,
        icon: Icons.lock_outline_rounded,
        onRetry: () => ref.invalidate(currentUserProfileProvider),
      );
    }

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: GGAppBar(title: l10n.editProfile),
        body: SafeArea(top: false, child: body),
      ),
    );
  }

  Widget _form(BuildContext context, AppLocalizations l10n, UserModel live) {
    final phoneSupported = ref.watch(phoneChangeSupportedProvider);
    final cities = ref.watch(activeCitiesProvider).valueOrNull ?? const [];
    String? cityLabel;
    if (_city != null) {
      final match = cities.where((c) => c.id == _city);
      cityLabel = match.isEmpty ? _city : match.first.name.of(context);
    }
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    final linkStyle = TextButton.styleFrom(
      foregroundColor: AppColors.goldText(context),
      minimumSize: const Size.square(AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      shape: const StadiumBorder(),
      textStyle: AppTextStyles.link.copyWith(fontFamily: font),
    );

    const gap = SizedBox(height: AppSpacing.md + AppSpacing.xs);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, AppSpacing.xl),
      children: [
        Center(
          child: _AvatarEditor(
            name: _name.text.trim().isEmpty ? live.name : _name.text,
            photoUrl: _photoUrl,
            uploading: _uploading,
            onTap: _changePhoto,
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _uploading ? null : _changePhoto,
            style: linkStyle,
            child: Text(l10n.changePhoto),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        GGInput(
          key: const ValueKey('edit-name'),
          label: l10n.yourName,
          hint: l10n.enterYourName,
          controller: _name,
          errorText: l10n.validation(_nameError),
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        gap,
        GGInput(
          key: const ValueKey('edit-email'),
          label: l10n.email,
          hint: l10n.enterYourEmail,
          controller: _email,
          errorText: l10n.validation(_emailError),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
        ),
        gap,
        ProfileValueField(
          key: const ValueKey('edit-phone'),
          label: l10n.mobileNumber,
          value: live.hasPhone ? formatPhoneForDisplay(live.countryCode, live.phone) : null,
          hint: l10n.addPhoneNumber,
          valueDirection: TextDirection.ltr,
          onTap: phoneSupported ? () => context.push(AppRoutes.changePhone) : null,
          trailing: phoneSupported
              ? TextButton(
                  onPressed: () => context.push(AppRoutes.changePhone),
                  style: linkStyle,
                  child: Text(live.hasPhone ? l10n.changePhone : l10n.addPhoneNumber),
                )
              : null,
        ),
        if (!phoneSupported) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBanner(message: l10n.phoneChangeMobileOnly),
        ] else if (!live.hasPhone) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.phoneLaterNote,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
          ),
        ],
        gap,
        ProfileValueField(
          key: const ValueKey('edit-birthday'),
          label: l10n.birthday,
          value: _birthday == null ? null : formatBirthday(_birthday!),
          hint: l10n.selectBirthday,
          valueDirection: TextDirection.ltr,
          onTap: _pickBirthday,
          trailing: Icon(Icons.calendar_month_rounded, color: AppColors.gold(context)),
        ),
        gap,
        Text(l10n.gender, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (value, label) in [
              ('male', l10n.genderMale),
              ('female', l10n.genderFemale),
              (null, l10n.genderPreferNot),
            ])
              CategoryChip(
                key: ValueKey('gender-${value ?? 'none'}'),
                label: label,
                selected: _gender == value,
                onTap: () => setState(() => _gender = value),
              ),
          ],
        ),
        gap,
        ProfileValueField(
          key: const ValueKey('edit-city'),
          label: l10n.city,
          value: cityLabel,
          hint: l10n.selectCity,
          onTap: _pickCity,
          trailing: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.gold(context)),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          key: const ValueKey('edit-save'),
          label: l10n.save,
          isLoading: _saving,
          onPressed: _uploading ? null : _save,
        ),
      ],
    );
  }
}

/// Large avatar with a gold camera badge and an upload spinner.
class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.name,
    required this.photoUrl,
    required this.uploading,
    required this.onTap,
  });

  final String name;
  final String? photoUrl;
  final bool uploading;
  final VoidCallback onTap;

  static const double size = 104;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l10n.changePhoto,
      child: InkResponse(
        onTap: uploading ? null : onTap,
        radius: size / 2,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ProfileAvatar(name: name, photoUrl: photoUrl, size: size),
              if (uploading)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.black.withValues(alpha: 0.45),
                    ),
                    child: const Center(
                      child: SizedBox.square(
                        dimension: 32,
                        child: CircularProgressIndicator(
                          key: ValueKey('avatar-uploading'),
                          strokeWidth: 3,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.gold(context),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bg(context), width: 3),
                  ),
                  child: const Icon(Icons.photo_camera_rounded, size: 16, color: AppColors.textOnPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
