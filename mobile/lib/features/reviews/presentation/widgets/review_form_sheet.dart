import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/review_model.dart';
import '../../../product_details/data/photo_service.dart';
import '../../../product_details/domain/product_configuration.dart' show PickedPhoto;
import '../../../product_details/presentation/widgets/photo_upload_grid.dart' show showPhotoSourceSheet;
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/reviews_repository.dart';
import '../providers/review_providers.dart';
import 'star_rating.dart';

/// Review form for one delivered order line (SRS §5.26): 1–5 stars
/// (required), text ≤ 500 and up to 3 photos. Editing [existing] warns that
/// the review goes back to moderation. Resolves to true when submitted.
Future<bool> showReviewFormSheet(BuildContext context, {required ReviewTarget target, ReviewModel? existing}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.card(context),
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => ReviewFormSheet(target: target, existing: existing),
  );
  return submitted ?? false;
}

class ReviewFormSheet extends ConsumerStatefulWidget {
  const ReviewFormSheet({super.key, required this.target, this.existing});

  final ReviewTarget target;
  final ReviewModel? existing;

  @override
  ConsumerState<ReviewFormSheet> createState() => _ReviewFormSheetState();
}

/// A photo in the form: already uploaded ([url]) or just picked ([photo]).
class _FormPhoto {
  const _FormPhoto.url(String this.url) : photo = null;
  const _FormPhoto.picked(PickedPhoto this.photo) : url = null;
  final String? url;
  final PickedPhoto? photo;
}

class _ReviewFormSheetState extends ConsumerState<ReviewFormSheet> {
  late int _rating = widget.existing?.rating ?? 0;
  late final _text = TextEditingController(text: widget.existing?.text ?? '');
  late final List<_FormPhoto> _photos = [
    for (final url in widget.existing?.images ?? const <String>[]) _FormPhoto.url(url),
  ];
  bool _ratingError = false;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _snack(String message) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addPhoto() async {
    final l10n = AppLocalizations.of(context)!;
    final source = await showPhotoSourceSheet(context);
    if (source == null || !mounted) return;
    try {
      final photo = await ref.read(photoServiceProvider).pick(source);
      if (photo != null && mounted && _photos.length < ReviewModel.maxImages) {
        setState(() => _photos.add(_FormPhoto.picked(photo)));
      }
    } on PhotoTooLargeException {
      _snack(l10n.photoTooLarge);
    } catch (_) {
      _snack(l10n.somethingWentWrong);
    }
  }

  /// The reviewer's name as stored (first name only, by the repository):
  /// the profile name, else the sign-in name.
  Future<String> _reviewerName() async {
    String? profileName;
    try {
      profileName = (await ref.read(currentUserProfileProvider.future).timeout(const Duration(seconds: 3)))?.name;
    } catch (_) {
      profileName = null;
    }
    final name = profileName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return ref.read(authStateProvider).valueOrNull?.displayName?.trim() ?? '';
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (_rating < 1) {
      setState(() => _ratingError = true);
      return;
    }
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    final navigator = Navigator.of(context);
    final target = widget.target;
    setState(() => _saving = true);
    try {
      final kept = [for (final p in _photos) if (p.url != null) p.url!];
      final picked = [for (final p in _photos) if (p.photo != null) p.photo!];
      var uploaded = const <String>[];
      if (picked.isNotEmpty) {
        // A fresh sub-folder on edits so new files never overwrite kept ones.
        final folder = (widget.existing?.images.isNotEmpty ?? false)
            ? '${target.photoFolder(uid)}/${DateTime.now().millisecondsSinceEpoch}'
            : target.photoFolder(uid);
        try {
          uploaded = await ref.read(imageUploadServiceProvider).upload(folder, picked);
        } catch (_) {
          _snack(l10n.photoUploadFailed);
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
      await ref.read(reviewsRepositoryProvider).submit(
            productId: target.productId,
            orderId: target.orderId,
            uid: uid,
            userName: await _reviewerName(),
            storeId: target.storeId,
            rating: _rating,
            text: _text.text,
            images: [...kept, ...uploaded],
          );
      navigator.pop(true);
    } catch (_) {
      _snack(l10n.somethingWentWrong);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Keeps the session loaded for Submit (it reads the uid).
    ref.watch(authStateProvider);
    final target = widget.target;
    final muted = AppColors.textMuted(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const ValueKey('review-form'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          0,
          AppSpacing.screenHorizontal,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.existing == null ? l10n.reviewFormTitle : l10n.reviewEdit,
                style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox.square(dimension: 48, child: GGNetworkImage(url: target.image)),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Text(
                    target.productTitle.of(context),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
                  ),
                ),
              ],
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: AppSpacing.md),
              InfoBanner(
                key: const ValueKey('review-edit-warning'),
                message: l10n.reviewEditWarning,
                type: InfoBannerType.warning,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(l10n.reviewYourRating, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
            const SizedBox(height: AppSpacing.xs),
            StarRatingInput(
              value: _rating,
              hasError: _ratingError,
              onChanged: (v) => setState(() {
                _rating = v;
                _ratingError = false;
              }),
            ),
            if (_ratingError)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm, top: AppSpacing.xs),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.reviewRatingRequired,
                    key: const ValueKey('review-rating-error'),
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            GGInput(
              key: const ValueKey('review-text'),
              label: '${l10n.reviewTextLabel} ${l10n.optionalLabel}',
              hint: l10n.reviewTextHint,
              controller: _text,
              multiline: true,
              minLines: 3,
              maxLines: 6,
              maxLength: ReviewModel.maxText,
              showCounter: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.reviewAddPhotos(ReviewModel.maxImages),
              style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  _PhotoThumb(
                    key: ValueKey('review-form-photo-$i'),
                    photo: _photos[i],
                    removeLabel: l10n.removePhoto,
                    onRemove: _saving ? null : () => setState(() => _photos.removeAt(i)),
                  ),
                if (_photos.length < ReviewModel.maxImages)
                  Semantics(
                    button: true,
                    label: l10n.reviewAddPhoto,
                    excludeSemantics: true,
                    child: InkWell(
                      key: const ValueKey('review-add-photo'),
                      onTap: _saving ? null : () => unawaited(_addPhoto()),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.soft(context),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.gold(context), width: 1.4),
                        ),
                        child: Icon(Icons.add_a_photo_outlined, color: AppColors.gold(context)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              key: const ValueKey('review-submit'),
              label: l10n.reviewSubmit,
              isLoading: _saving,
              onPressed: _submit,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.reviewThanks,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({super.key, required this.photo, required this.removeLabel, this.onRemove});

  final _FormPhoto photo;
  final String removeLabel;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    // The 48 dp remove target sits inside this box (hit testing stops at a
    // Stack's bounds) and overlaps the photo's top-end corner.
    return SizedBox(
      width: 72 + AppSpacing.md,
      height: 72 + AppSpacing.md,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            start: 0,
            bottom: 0,
            width: 72,
            height: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: photo.photo != null
                  // Decoded at thumbnail size, not the photo's (≤ 1600 px).
                  ? Image.memory(photo.photo!.bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: (72 * MediaQuery.devicePixelRatioOf(context)).round())
                  : GGNetworkImage(url: photo.url),
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: GGCircleButton(
              icon: Icons.close_rounded,
              size: 28,
              iconSize: 16,
              tooltip: removeLabel,
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}
