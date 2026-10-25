import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/form_widgets.dart';
import '../orders/data/admin_orders_repository.dart';
import '../orders/order_status_ui.dart';
import '../stores/widgets/detail_widgets.dart';
import '../users/data/users_admin_repository.dart' show adminNameProvider;
import 'data/reviews_admin_repository.dart';
import 'review_ui.dart';

/// One review in full (SRS §9 Reviews): text, photos (open full size in a new
/// tab), customer, product, store and order, plus Approve / Hide.
class ReviewDetailPanel extends ConsumerWidget {
  const ReviewDetailPanel({super.key, required this.path, this.onClose});

  /// `products/{productId}/reviews/{id}`.
  final String path;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(adminReviewProvider(path));
    return review.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => CenteredNote(icon: Icons.error_outline, text: 'Could not load the review: $e'),
      data: (r) => r == null
          ? const CenteredNote(icon: Icons.rate_review_outlined, text: 'This review no longer exists.')
          : _Body(review: r, onClose: onClose),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.review, this.onClose});
  final AdminReview review;
  final VoidCallback? onClose;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  Future<void> _set(bool approved) async {
    final session = ref.read(adminSessionProvider);
    if (session == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(reviewsAdminRepositoryProvider).setApproved(widget.review, approved, adminUid: session.uid);
      if (mounted) showMessage(context, approved ? 'Review approved' : 'Review hidden');
    } catch (e) {
      if (mounted) showMessage(context, 'Could not update the review: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review.review;
    final session = ref.watch(adminSessionProvider);
    final canModerate = session != null && ReviewsAccess.canModerate(session.role);
    final productTitle = ref.watch(reviewProductTitleProvider(r.productId)).valueOrNull;
    final stores = ref.watch(orderStoreFilterProvider).valueOrNull ?? const [];
    final storeName = stores.where((s) => s.id == r.storeId).firstOrNull?.name.en;
    final fmt = DateFormat('yyyy-MM-dd HH:mm', 'en_US');
    final theme = Theme.of(context);
    final moderator = widget.review.moderatedBy;
    final moderatorName = moderator == null ? null : ref.watch(adminNameProvider(moderator)).valueOrNull;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(children: [
          ReviewStars(r.rating, size: 22),
          const SizedBox(width: AppSpacing.sm),
          ReviewApprovalPill(approved: r.isApproved),
          const Spacer(),
          if (widget.onClose != null)
            IconButton(tooltip: 'Close', onPressed: widget.onClose, icon: const Icon(Icons.close)),
        ]),
        Text(
          [
            r.userName.isEmpty ? 'Customer' : r.userName,
            if (r.createdAt != null) fmt.format(r.createdAt!.toLocal()),
          ].join(' · '),
          style: TextStyle(color: AppColors.textMuted(context)),
        ),
        const SizedBox(height: AppSpacing.md),
        if (canModerate)
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            if (!r.isApproved)
              FilledButton.icon(
                onPressed: _busy ? null : () => _set(true),
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
              ),
            if (r.isApproved)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: _busy ? null : () => _set(false),
                icon: const Icon(Icons.visibility_off_outlined),
                label: const Text('Hide'),
              ),
          ])
        else
          Text('Your role can view reviews but not moderate them.',
              style: TextStyle(color: AppColors.textMuted(context))),
        const SizedBox(height: AppSpacing.md),
        SectionCard(title: 'Review', children: [
          SelectableText(r.text.isEmpty ? '(no text — rating only)' : r.text),
          if (r.images.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
              for (final url in r.images) ImageThumb(url: url, size: 96),
            ]),
            const SizedBox(height: AppSpacing.xs),
            Text('Tap a photo to open it full size.',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context))),
          ],
        ]),
        const SizedBox(height: AppSpacing.md),
        SectionCard(title: 'Customer & product', children: [
          KeyValueRow('Customer', r.userName),
          KeyValueRow('Customer id', r.userId,
              copy: r.userId,
              child: r.userId.isEmpty ? null : LinkText(r.userId, onTap: () => context.go(AdminRoutes.user(r.userId)))),
          KeyValueRow('Product', productTitle ?? r.productId,
              child: r.productId.isEmpty
                  ? null
                  : LinkText(productTitle ?? r.productId, onTap: () => context.go(AdminRoutes.product(r.productId)))),
          KeyValueRow('Store', storeName ?? r.storeId),
        ]),
        const SizedBox(height: AppSpacing.md),
        _OrderCard(orderId: r.orderId),
        if (moderator != null) ...[
          const SizedBox(height: AppSpacing.md),
          SectionCard(title: 'Moderation', children: [
            KeyValueRow('By', moderatorName ?? moderator),
            KeyValueRow(
                'At', widget.review.moderatedAt == null ? '' : fmt.format(widget.review.moderatedAt!.toLocal())),
          ]),
        ],
      ],
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (orderId.isEmpty || orderId.contains('/')) {
      return const SectionCard(title: 'Order', children: [Text('No order is linked to this review.')]);
    }
    final order = ref.watch(adminOrderProvider(orderId));
    final fmt = DateFormat('yyyy-MM-dd', 'en_US');
    return SectionCard(
      title: 'Order',
      trailing: TextButton.icon(
        onPressed: () => showOrderDialog(context, orderId),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('Open order'),
      ),
      children: [
        ...order.when(
          loading: () => [const LinearProgressIndicator()],
          error: (e, _) => [KeyValueRow('Order id', orderId, copy: orderId)],
          data: (o) => o == null
              ? [KeyValueRow('Order id', orderId, copy: orderId), const Text('This order no longer exists.')]
              : [
                  KeyValueRow('Order', o.orderNumber.isEmpty ? o.id : o.orderNumber,
                      copy: o.orderNumber.isEmpty ? o.id : o.orderNumber),
                  KeyValueRow('Status', '',
                      child: Align(alignment: Alignment.centerLeft, child: OrderStatusChip(o.status))),
                  KeyValueRow('Placed', o.createdAt == null ? '' : fmt.format(o.createdAt!.toLocal())),
                  KeyValueRow('Total', CurrencyFormatter.format(o.total)),
                ],
        ),
      ],
    );
  }
}
