import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../../domain/product_configuration.dart';
import '../providers/product_details_controller.dart';
import 'option_formatting.dart';
import 'photo_upload_grid.dart';
import 'text_and_date_options.dart';
import 'variant_options.dart';

/// One option group on Product Details (SRS §5.9 table): header
/// ("Frame Color", "Date (Optional)"), the input for its [OptionType] and —
/// after the first Add to Cart attempt — the error-red hint.
///
/// Watches only this group's issue; the input below watches only this
/// group's selection, so other groups never rebuild.
class OptionGroupSection extends ConsumerWidget {
  const OptionGroupSection({super.key, required this.productId, required this.group});

  final String productId;
  final OptionGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final issue = ref.watch(productDetailsControllerProvider(productId).select((s) => s.issueFor(group.id)));
    final hint = issue == null ? null : optionIssueMessage(l10n, group, issue);
    final isText = group.type == OptionType.text || group.type == OptionType.longText;

    final Widget input = switch (group.type) {
      OptionType.imageVariant => ImageVariantOptions(productId: productId, group: group),
      OptionType.textVariant => TextVariantOptions(productId: productId, group: group),
      OptionType.colorSwatch => ColorSwatchOptions(productId: productId, group: group),
      OptionType.text || OptionType.longText => TextOptionField(productId: productId, group: group, errorText: hint),
      OptionType.date => DateOptionField(productId: productId, group: group, hasError: hint != null),
      OptionType.photoUpload => PhotoUploadGrid(productId: productId, group: group, hasError: hint != null),
      OptionType.quantity => const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupHeader(group: group),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        input,
        // Text inputs show the hint inside GGInput (red border + message).
        if (hint != null && !isText) ...[
          const SizedBox(height: AppSpacing.sm),
          OptionHint(message: hint),
        ],
      ],
    );
  }
}

/// Localized hint for a validation problem (SRS §5.9: messages are localized).
String optionIssueMessage(AppLocalizations l10n, OptionGroup group, OptionIssueKind kind) {
  final minPhotos = group.minPhotos ?? 1;
  return switch (kind) {
    OptionIssueKind.missing => switch (group.type) {
        OptionType.text || OptionType.longText => l10n.textRequiredError,
        OptionType.date => l10n.dateRequiredError,
        OptionType.photoUpload => l10n.photosRequiredError(minPhotos),
        _ => l10n.optionRequiredError,
      },
    OptionIssueKind.tooLong => l10n.textTooLongError(group.maxLength ?? 0),
    OptionIssueKind.notEnoughPhotos => l10n.photosRequiredError(minPhotos),
    OptionIssueKind.unavailable => l10n.optionUnavailableError,
  };
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});
  final OptionGroup group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      header: true,
      child: Text.rich(
        TextSpan(
          text: group.label.of(context),
          children: [
            if (!group.required)
              TextSpan(
                text: ' ${l10n.optionalLabel}',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 15,
                  color: AppColors.textMuted(context),
                ),
              ),
          ],
        ),
        style: AppTextStyles.label.copyWith(fontSize: 17, color: AppColors.text(context)),
      ),
    );
  }
}

/// Error-red hint line under a group (announced when it appears).
class OptionHint extends StatelessWidget {
  const OptionHint({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = errorTextColor(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Icon(Icons.error_outline_rounded, size: 16, color: color),
          ),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
