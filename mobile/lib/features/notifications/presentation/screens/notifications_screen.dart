import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/notification_model.dart';
import '../../../orders/presentation/widgets/order_card.dart' show popOrGo;
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/notifications_repository.dart';
import '../widgets/notification_tile.dart';

/// Notifications (SRS §4.5, §5.5): grouped by day, unread rows on soft gold,
/// tap → mark read + open its route, swipe to delete, "Mark all as read".
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Swiped away; hidden at once (a Dismissible must leave the tree) while
  /// the repository catches up.
  final _removed = <String>{};

  void _ignoreErrors(Future<void> future) => unawaited(future.catchError((Object _) {}));

  /// Broadcast read / hidden state lives on the device, so no Firestore
  /// snapshot follows — re-read the list (and the Home bell count).
  Future<void> _afterLocalChange(Future<void> change, {required bool touchedBroadcast}) async {
    await change;
    if (touchedBroadcast && mounted) {
      ref
        ..invalidate(notificationsProvider)
        ..invalidate(latestNotificationsProvider);
    }
  }

  void _open(NotificationModel n) {
    _ignoreErrors(_afterLocalChange(
      ref.read(notificationsRepositoryProvider).markRead(n),
      touchedBroadcast: n.isBroadcast && !n.isRead,
    ));
    final route = n.route;
    if (route != null && route.startsWith('/')) unawaited(context.push(route));
  }

  Future<void> _remove(NotificationModel n) async {
    setState(() => _removed.add(n.id));
    try {
      await _afterLocalChange(ref.read(notificationsRepositoryProvider).remove(n), touchedBroadcast: n.isBroadcast);
    } catch (_) {
      if (!mounted) return;
      setState(() => _removed.remove(n.id));
      showOrderSnack(context, AppLocalizations.of(context)!.somethingWentWrong);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final async = ref.watch(notificationsProvider);
    final visible = (async.valueOrNull ?? const <NotificationModel>[]).where((n) => !_removed.contains(n.id)).toList();
    final hasUnread = visible.any((n) => !n.isRead);

    Widget body;
    if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.notifications_rounded);
    } else if (async.hasError && !async.hasValue) {
      body = CenteredScroll(child: ErrorState(onRetry: () => ref.invalidate(notificationsProvider)));
    } else if (!async.hasValue) {
      body = const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
        child: SkeletonLoader.list(count: 5),
      );
    } else if (visible.isEmpty) {
      body = CenteredScroll(
        child: EmptyState(
          title: l10n.noNotificationsTitle,
          subtitle: l10n.noNotificationsBody,
          icon: Icons.notifications_none_rounded,
        ),
      );
    } else {
      body = _list(context, l10n, visible);
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        title: l10n.notifications,
        showBack: true,
        onBack: () => popOrGo(context, AppRoutes.mainTab(0)),
        actions: [
          if (signedIn && hasUnread)
            GGCircleButton(
              key: const ValueKey('mark-all-read'),
              icon: Icons.done_all_rounded,
              iconColor: AppColors.gold(context),
              tooltip: l10n.markAllRead,
              onPressed: () => _ignoreErrors(_afterLocalChange(
                ref.read(notificationsRepositoryProvider).markAllRead(visible),
                touchedBroadcast: visible.any((n) => n.isBroadcast && !n.isRead),
              )),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _list(BuildContext context, AppLocalizations l10n, List<NotificationModel> list) {
    final now = DateTime.now();
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    final children = <Widget>[];
    for (final (day, items) in groupNotificationsByDay(list, now)) {
      children.add(Padding(
        padding: EdgeInsetsDirectional.only(
          top: children.isEmpty ? 0 : AppSpacing.md,
          bottom: AppSpacing.sm,
          start: AppSpacing.xs,
        ),
        child: Semantics(
          header: true,
          child: Text(
            notificationDayLabel(l10n, day, now),
            key: ValueKey('day-${day.toIso8601String()}'),
            style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textMuted(context)),
          ),
        ),
      ));
      for (final n in items) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Dismissible(
            key: ValueKey('notification-${n.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: AlignmentDirectional.centerEnd,
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(Icons.delete_outline_rounded, color: AppColors.white, semanticLabel: l10n.delete),
            ),
            onDismissed: (_) => _remove(n),
            child: NotificationTile(notification: n, onTap: () => _open(n)),
          ),
        ));
      }
    }
    return ListView(
      key: const ValueKey('notifications-list'),
      padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
      children: children,
    );
  }
}
