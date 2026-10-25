import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/notification_model.dart';

/// Groups notifications by local calendar day, newest first (SRS §5.5).
/// A missing `createdAt` (server timestamp still pending) counts as [now].
List<(DateTime day, List<NotificationModel> items)> groupNotificationsByDay(
  List<NotificationModel> list,
  DateTime now,
) {
  final groups = <DateTime, List<NotificationModel>>{};
  for (final n in list) {
    final at = n.createdAt?.toLocal() ?? now;
    groups.putIfAbsent(DateTime(at.year, at.month, at.day), () => []).add(n);
  }
  final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final d in days) (d, groups[d]!)];
}

/// "Today" / "Yesterday" / "02/11/2026".
String notificationDayLabel(AppLocalizations l10n, DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return l10n.today;
  if (day == DateTime(today.year, today.month, today.day - 1)) return l10n.yesterday;
  return AppDates.display(day);
}

IconData _iconFor(String type) => switch (type) {
      'orderStatus' => Icons.local_shipping_outlined,
      'specialRequestReply' => Icons.chat_bubble_outline_rounded,
      'referralCredited' || 'referralNotApplied' => Icons.group_add_outlined,
      'giftCardReceived' || 'giftCardSent' => Icons.card_giftcard_rounded,
      'partnerStatus' => Icons.storefront_outlined,
      'secretSantaDraw' => Icons.redeem_rounded,
      _ => Icons.campaign_outlined,
    };

/// One row: unread rows sit on soft gold with a gold dot (SRS §5.5).
class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.notification, required this.onTap});

  final NotificationModel notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.isRead;
    final muted = AppColors.textMuted(context);
    final body = n.body.of(context);
    final at = n.createdAt?.toLocal();
    return Semantics(
      button: true,
      child: Material(
        color: unread ? AppColors.soft(context) : AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: unread ? AppColors.gold(context).withValues(alpha: 0.5) : AppColors.line(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: unread ? AppColors.card(context) : AppColors.soft(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_iconFor(n.type), size: 20, color: AppColors.gold(context)),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title.of(context),
                        style: AppTextStyles.label.copyWith(
                          fontSize: 15,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                          color: AppColors.text(context),
                        ),
                      ),
                      if (body.isNotEmpty)
                        Text(
                          body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(color: muted),
                        ),
                      if (at != null)
                        Text(
                          AppDates.displayWithTime(at).split(' ').last,
                          textDirection: TextDirection.ltr,
                          style: AppTextStyles.bodySmall.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
                if (unread)
                  Container(
                    key: ValueKey('unread-dot-${n.id}'),
                    width: 10,
                    height: 10,
                    margin: const EdgeInsetsDirectional.only(start: AppSpacing.sm, top: AppSpacing.xs),
                    decoration: BoxDecoration(color: AppColors.gold(context), shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
