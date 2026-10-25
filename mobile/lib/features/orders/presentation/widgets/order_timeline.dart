import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/order_model.dart';
import 'order_labels.dart';
import 'order_section.dart';

enum TimelineMark { done, current, upcoming, stopped }

class TimelineStep {
  const TimelineStep(this.status, this.mark, {this.entry, this.note});
  final OrderStatus status;
  final TimelineMark mark;

  /// The latest `status_history` entry for this status, if any.
  final StatusHistoryEntry? entry;
  final String? note;
}

/// The order's progress for the timeline (SRS §5.12): the main flow
/// (pending → delivered) with done / current / upcoming steps, or — once the
/// order left it (cancelled, returned, refunded) — the steps it reached
/// followed by those states.
List<TimelineStep> orderTimeline(OrderModel order, List<StatusHistoryEntry> history) {
  const flow = OrderStatusX.flow;
  StatusHistoryEntry? latest(OrderStatus s) => history.where((h) => h.status == s).lastOrNull;
  String? noteOf(OrderStatus s) {
    final note = latest(s)?.note;
    return note == null || note.trim().isEmpty ? null : note.trim();
  }

  final index = flow.indexOf(order.status);
  if (index >= 0) {
    return [
      for (var i = 0; i < flow.length; i++)
        TimelineStep(
          flow[i],
          i < index || (i == index && order.status == OrderStatus.delivered)
              ? TimelineMark.done
              : (i == index ? TimelineMark.current : TimelineMark.upcoming),
          entry: latest(flow[i]),
          note: noteOf(flow[i]),
        ),
    ];
  }

  var reached = 0;
  for (final h in history) {
    final i = flow.indexOf(h.status);
    if (i > reached) reached = i;
  }
  final off = <OrderStatus>{
    for (final h in history)
      if (!flow.contains(h.status) && h.status != order.status) h.status,
    order.status,
  };
  final cancelReason = order.cancelReason?.trim();
  return [
    for (var i = 0; i <= reached; i++)
      TimelineStep(flow[i], TimelineMark.done, entry: latest(flow[i]), note: noteOf(flow[i])),
    for (final s in off)
      TimelineStep(
        s,
        TimelineMark.stopped,
        entry: latest(s),
        note: noteOf(s) ??
            ((s == OrderStatus.cancelledByBuyer || s == OrderStatus.cancelledBySeller) &&
                    cancelReason != null &&
                    cancelReason.isNotEmpty
                ? cancelReason
                : null),
      ),
  ];
}

class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.steps});
  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            key: ValueKey('timeline-${steps[i].status.name}-${steps[i].mark.name}'),
            step: steps[i],
            isLast: i == steps.length - 1,
            nextReached: i + 1 < steps.length && steps[i + 1].mark != TimelineMark.upcoming,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({super.key, required this.step, required this.isLast, required this.nextReached});

  final TimelineStep step;
  final bool isLast;
  final bool nextReached;

  /// Who made the change, when it wasn't Golden Gift's team: the store
  /// (`byRole: seller`, Phase 8) or the customer. "Cancelled by the store"
  /// already says it.
  static String? _actor(AppLocalizations l10n, TimelineStep step) {
    if (step.status == OrderStatus.cancelledBySeller) return null;
    return switch (step.entry?.byRole) {
      'seller' => l10n.orderChangedByStore,
      'customer' => l10n.orderChangedByYou,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final upcoming = step.mark == TimelineMark.upcoming;
    final at = step.entry?.at;
    final actor = upcoming ? null : _actor(l10n, step);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _Marker(mark: step.mark),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                      color: nextReached ? AppColors.gold(context) : AppColors.line(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md, top: AppSpacing.xxs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    orderStatusLabel(l10n, step.status),
                    style: AppTextStyles.label.copyWith(
                      fontSize: 15,
                      fontWeight: step.mark == TimelineMark.current ? FontWeight.w700 : FontWeight.w600,
                      color: switch (step.mark) {
                        TimelineMark.upcoming => muted,
                        TimelineMark.stopped => errorText(context),
                        _ => AppColors.text(context),
                      },
                    ),
                  ),
                  if (at != null && !upcoming)
                    Text(
                      AppDates.displayWithTime(at),
                      textDirection: TextDirection.ltr,
                      style: AppTextStyles.bodySmall.copyWith(color: muted),
                    ),
                  if (actor != null)
                    Text(
                      actor,
                      key: ValueKey('timeline-by-${step.status.name}'),
                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: muted),
                    ),
                  if (step.note != null)
                    Text(
                      orderNoteText(l10n, step.note!),
                      key: ValueKey('timeline-note-${step.status.name}'),
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.text(context)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.mark});
  final TimelineMark mark;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    const size = 24.0;
    return switch (mark) {
      TimelineMark.done => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: gold, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 16, color: AppColors.textOnPrimary),
        ),
      TimelineMark.current => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.soft(context),
            shape: BoxShape.circle,
            border: Border.all(color: gold, width: 2),
          ),
          child: Container(width: 10, height: 10, decoration: BoxDecoration(color: gold, shape: BoxShape.circle)),
        ),
      TimelineMark.upcoming => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.card(context),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line(context), width: 2),
          ),
        ),
      TimelineMark.stopped => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 16, color: AppColors.white),
        ),
    };
  }
}
