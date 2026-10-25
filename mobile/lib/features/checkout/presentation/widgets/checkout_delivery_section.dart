import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/app_settings_model.dart';
import '../../../orders/presentation/widgets/order_labels.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../providers/checkout_providers.dart';

/// "Today" / "Tomorrow" / "02/11" for the date chips.
String deliveryDateChipLabel(AppLocalizations l10n, DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (isSameDay(date, today)) return l10n.today;
  if (isSameDay(date, DateTime(today.year, today.month, today.day + 1))) return l10n.tomorrow;
  return AppDates.display(date).substring(0, 5); // dd/MM
}

/// Step 2 — delivery date & time slot (SRS §5.11).
class CheckoutDeliverySection extends StatelessWidget {
  const CheckoutDeliverySection({
    super.key,
    required this.choice,
    required this.now,
    required this.onDate,
    required this.onSlot,
  });

  final DeliveryChoice choice;
  final DateTime now;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<DeliverySlot> onSlot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OrderSection(
      title: l10n.deliveryDateAndTime,
      icon: Icons.event_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: CategoryChip.height,
            child: ListView.separated(
              key: const ValueKey('checkout-dates'),
              scrollDirection: Axis.horizontal,
              itemCount: choice.dates.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) {
                final date = choice.dates[i];
                final open = choice.hasSlots(date);
                final chip = CategoryChip(
                  key: ValueKey('date-${AppDates.isoDate(date)}'),
                  label: deliveryDateChipLabel(l10n, date, now),
                  selected: choice.date != null && isSameDay(date, choice.date!),
                  onTap: open ? () => onDate(date) : null,
                );
                return open ? chip : Opacity(opacity: 0.45, child: chip);
              },
            ),
          ),
          if (choice.todayHasNoSlots) ...[
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            InfoBanner(
              key: const ValueKey('no-slots-today'),
              message: l10n.noSlotsToday,
              type: InfoBannerType.warning,
              icon: Icons.schedule_rounded,
            ),
          ],
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final slot in choice.slots)
                _SlotChip(
                  key: ValueKey('slot-${slot.id}'),
                  slot: slot,
                  selected: choice.slot?.id == slot.id,
                  onTap: () => onSlot(slot),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two-line pill: slot name over its time window.
class _SlotChip extends StatelessWidget {
  const _SlotChip({super.key, required this.slot, required this.selected, required this.onTap});

  final DeliverySlot slot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    final name = slot.label.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.soft(context) : AppColors.card(context),
        shape: StadiumBorder(
          side: BorderSide(color: selected ? gold : AppColors.line(context), width: selected ? 1.4 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + AppSpacing.xxs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      style: AppTextStyles.label.copyWith(fontSize: 14, color: AppColors.text(context)),
                    ),
                  Text(
                    '${slot.from}–${slot.to}',
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.goldText(context) : AppColors.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
