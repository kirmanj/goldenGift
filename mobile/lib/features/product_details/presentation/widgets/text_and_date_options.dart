import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../providers/product_details_controller.dart';
import 'option_formatting.dart';

/// `text` (Text 1 0/50, Name 0/12) and `longText` (Notes 0/500): grey
/// rounded text area with the live `n/max` counter (IMG_4503, IMG_4509).
///
/// The field owns its text; typing only updates the configuration, so
/// nothing else on the page rebuilds per keystroke.
class TextOptionField extends ConsumerWidget {
  const TextOptionField({super.key, required this.productId, required this.group, this.errorText});

  final String productId;
  final OptionGroup group;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final provider = productDetailsControllerProvider(productId);
    final long = group.type == OptionType.longText;
    return GGInput(
      // Restores the text when the field is rebuilt (e.g. a live product update).
      initialValue: ref.read(provider).config?.selectionFor(group.id).text,
      hint: l10n.customizeTextHint,
      multiline: true,
      minLines: long ? 4 : 2,
      maxLines: long ? 8 : 4,
      maxLength: group.maxLength,
      showCounter: group.maxLength != null,
      textCapitalization: TextCapitalization.sentences,
      errorText: errorText,
      onChanged: (text) => ref.read(provider.notifier).setText(group.id, text),
    );
  }
}

/// `date` (Date (Optional), IMG_4507): grey pill "Select a date" → date
/// picker (today … one year ahead). Shown as dd/MM/yyyy in every language.
class DateOptionField extends ConsumerWidget {
  const DateOptionField({super.key, required this.productId, required this.group, this.hasError = false});

  final String productId;
  final OptionGroup group;
  final bool hasError;

  Future<void> _pick(BuildContext context, WidgetRef ref, DateTime? current) async {
    final notifier = ref.read(productDetailsControllerProvider(productId).notifier);
    final today = DateUtils.dateOnly(DateTime.now());
    final last = DateTime(today.year + 1, today.month, today.day);
    var initial = current == null ? today : DateTime(current.year, current.month, current.day);
    if (initial.isBefore(today) || initial.isAfter(last)) initial = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: group.label.of(context),
    );
    if (picked != null && notifier.mounted) notifier.setDate(group.id, optionDateValue(picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final date =
        ref.watch(productDetailsControllerProvider(productId).select((s) => s.config?.selectionFor(group.id).date));
    final hintColor = AppColors.isDark(context) ? AppColors.darkTextHint : AppColors.textHint;
    final label = date == null ? l10n.selectADate : formatOptionDate(date);

    return Semantics(
      button: true,
      label: group.label.of(context),
      value: date == null ? null : label,
      child: Material(
        color: AppColors.field(context),
        shape: StadiumBorder(
          side: BorderSide(color: hasError ? AppColors.error : AppColors.line(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _pick(context, ref, date),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.lg,
                end: AppSpacing.xs,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.gold(context)),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: date == null ? hintColor : AppColors.text(context),
                      ),
                    ),
                  ),
                  if (date != null)
                    IconButton(
                      tooltip: l10n.remove,
                      icon: Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted(context)),
                      onPressed: () =>
                          ref.read(productDetailsControllerProvider(productId).notifier).setDate(group.id, null),
                    )
                  else
                    const SizedBox(height: AppSpacing.minTapTarget),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
