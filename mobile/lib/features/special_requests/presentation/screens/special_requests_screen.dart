import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/special_request_model.dart';
import '../../../../models/user_model.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../../orders/presentation/widgets/order_section.dart' show showOrderSnack;
import '../../../product_details/domain/product_configuration.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/special_requests_repository.dart';
import '../widgets/picked_photos_field.dart';
import '../widgets/special_request_widgets.dart';

/// Name + E.164 phone snapshot for the admin inbox (users are private).
(String?, String?) customerSnapshot(UserModel? profile) {
  if (profile == null) return (null, null);
  final name = profile.name.trim();
  final phone = profile.phone.trim();
  return (name.isEmpty ? null : name, phone.isEmpty ? null : '${profile.countryCode}$phone');
}

/// The signed-in customer's snapshot; waits briefly for the profile stream
/// when nothing has loaded it yet (never blocks a submit on it).
Future<(String?, String?)> readCustomerSnapshot(WidgetRef ref) async {
  UserModel? profile = ref.read(currentUserProfileProvider).valueOrNull;
  if (profile == null) {
    try {
      profile = await ref.read(currentUserProfileProvider.future).timeout(const Duration(seconds: 3));
    } catch (_) {
      profile = null;
    }
  }
  return customerSnapshot(profile);
}

/// Special Requests (SRS §5.17, IMG_4492): illustration, title, subtitle,
/// dashed photo tile (≤ 5), "Write your idea here" (≤ 1000) and the gold
/// **Submit your request**; below it, my requests (incl. Contact Us support
/// messages) with their status and a dot when Golden Gift replied.
class SpecialRequestsScreen extends ConsumerStatefulWidget {
  const SpecialRequestsScreen({super.key});

  @override
  ConsumerState<SpecialRequestsScreen> createState() => _SpecialRequestsScreenState();
}

class _SpecialRequestsScreenState extends ConsumerState<SpecialRequestsScreen> {
  final _text = TextEditingController();
  List<PickedPhoto> _photos = const [];
  String? _textError;
  bool _submitting = false;
  double? _progress;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context)!;
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _textError = l10n.srTextRequired);
      return;
    }
    if (!await requireSignIn(context, ref)) return;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null || !mounted) return;
    FocusScope.of(context).unfocus();
    final photos = _photos;
    setState(() {
      _submitting = true;
      _progress = photos.isEmpty ? null : 0;
    });
    try {
      final (name, phone) = await readCustomerSnapshot(ref);
      await ref.read(specialRequestsRepositoryProvider).create(
            uid: uid,
            text: text,
            type: SpecialRequestType.gift,
            photos: photos,
            customerName: name,
            customerPhone: phone,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.specialRequestSubmit, {
        'type': SpecialRequestType.gift.name,
        'images': photos.length,
      }));
      if (!mounted) return;
      _text.clear();
      setState(() {
        _photos = const [];
        _textError = null;
      });
      showOrderSnack(context, l10n.srSubmitted);
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
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
    final requests = signedIn ? ref.watch(mySpecialRequestsProvider) : null;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.specialRequests),
      body: ListView(
        key: const ValueKey('special-requests-list'),
        padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
        children: [
          const Align(alignment: AlignmentDirectional.centerStart, child: IdeaIllustration()),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(l10n.specialRequests, style: AppTextStyles.heading1.copyWith(color: AppColors.text(context))),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.srSubtitle, style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context))),
          const SizedBox(height: AppSpacing.lg),
          PickedPhotosField(
            keyPrefix: 'sr-photos',
            photos: _photos,
            max: SpecialRequestModel.maxImages,
            tileSize: 96,
            enabled: !_submitting,
            onAdd: (p) => setState(() => _photos = [..._photos, p].take(SpecialRequestModel.maxImages).toList()),
            onRemove: (i) => setState(() => _photos = [..._photos]..removeAt(i)),
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Text(
            l10n.srPhotosHint(SpecialRequestModel.maxImages),
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          GGInput(
            key: const ValueKey('sr-text'),
            hint: l10n.writeYourIdeaHere,
            controller: _text,
            multiline: true,
            minLines: 5,
            maxLines: 10,
            maxLength: SpecialRequestModel.maxText,
            showCounter: true,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.sentences,
            errorText: _textError,
            onChanged: (_) {
              if (_textError != null) setState(() => _textError = null);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_progress != null) ...[
            UploadProgressLine(progress: _progress!),
            const SizedBox(height: AppSpacing.sm),
          ],
          PrimaryButton(
            key: const ValueKey('sr-submit'),
            label: l10n.submitYourRequest,
            isLoading: _submitting,
            onPressed: _submit,
          ),
          if (requests != null) ..._myRequests(context, l10n, requests),
        ],
      ),
    );
  }

  List<Widget> _myRequests(BuildContext context, AppLocalizations l10n, AsyncValue<List<SpecialRequestModel>> async) {
    final header = [
      const SizedBox(height: AppSpacing.xl),
      SectionHeader(key: const ValueKey('sr-my-requests'), title: l10n.srMyRequests),
      const SizedBox(height: AppSpacing.sm),
    ];
    if (async.hasError && !async.hasValue) {
      return [...header, ErrorState(onRetry: () => ref.invalidate(mySpecialRequestsProvider))];
    }
    if (!async.hasValue) return [...header, const SkeletonLoader.list(count: 2)];
    final list = async.requireValue;
    if (list.isEmpty) return const [];
    return [
      ...header,
      for (final r in list)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm + AppSpacing.xs),
          child: SpecialRequestTile(key: ValueKey('sr-${r.id}'), request: r),
        ),
    ];
  }
}
