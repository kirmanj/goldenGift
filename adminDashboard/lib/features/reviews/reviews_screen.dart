import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/store_model.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../orders/data/admin_orders_repository.dart' show orderStoreFilterProvider;
import '../stores/widgets/detail_widgets.dart';
import 'data/reviews_admin_repository.dart';
import 'review_detail_panel.dart';
import 'review_ui.dart';

/// SRS §9 Reviews: the moderation queue (collection-group query on
/// `reviews`, newest first) with approval / rating / store / product
/// filters, a detail drawer, Approve / Hide and bulk approve.
class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key});

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  ReviewFilters _filters = const ReviewFilters();
  int _limit = ReviewsAdminRepository.pageSize;

  /// Paths of the reviews ticked for bulk approve.
  final _selected = <String>{};

  /// Path of the review open in the side panel (wide windows).
  String? _open;
  bool _bulkBusy = false;
  final _busyRows = <String>{};

  /// path → approval just written here, applied to the rows until the
  /// listener delivers it (and dropped when the filters change).
  final _moderated = <String, bool>{};

  static const _panelBreakpoint = 1280.0;

  void _setFilters(ReviewFilters f) => setState(() {
        _filters = f;
        _limit = ReviewsAdminRepository.pageSize;
        _selected.clear();
        _moderated.clear();
      });

  /// The listener's rows with this screen's own writes applied, still
  /// filtered (an approved review leaves the Pending queue at once).
  List<AdminReview> _withLocalChanges(List<AdminReview> list) => [
        for (final r in list)
          if (_moderated[r.path] case final approved? when approved != r.review.isApproved) r.withApproved(approved) else r,
      ].where(_filters.matches).toList();

  Future<void> _openReview(AdminReview r, bool sidePanel) async {
    if (sidePanel) {
      setState(() => _open = r.path);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ReviewDetailPanel(path: r.path, onClose: () => Navigator.pop(context)),
        ),
      ),
    );
  }

  Future<void> _moderate(AdminReview r, bool approved) async {
    final session = ref.read(adminSessionProvider);
    if (session == null) return;
    setState(() => _busyRows.add(r.path));
    try {
      await ref.read(reviewsAdminRepositoryProvider).setApproved(r, approved, adminUid: session.uid);
      if (mounted) {
        setState(() {
          _selected.remove(r.path);
          _moderated[r.path] = approved;
        });
        showMessage(context, approved ? 'Review approved' : 'Review hidden');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not update the review: $e');
    } finally {
      if (mounted) setState(() => _busyRows.remove(r.path));
    }
  }

  Future<void> _bulkApprove(List<AdminReview> visible) async {
    final session = ref.read(adminSessionProvider);
    if (session == null) return;
    final chosen = visible.where((r) => _selected.contains(r.path)).toList();
    if (chosen.isEmpty) return;
    final ok = await confirmAction(
      context,
      title: 'Approve ${chosen.length} review${chosen.length == 1 ? '' : 's'}?',
      message: 'They become visible on the product pages. Product and store ratings update automatically.',
      confirmLabel: 'Approve',
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      final result = await ref.read(reviewsAdminRepositoryProvider).bulkApprove(chosen, adminUid: session.uid);
      if (!mounted) return;
      setState(() {
        for (final r in chosen) {
          _moderated[r.path] = true;
        }
        _selected.clear();
      });
      showMessage(
        context,
        'Approved ${result.approved} review${result.approved == 1 ? '' : 's'}'
        '${result.skipped == 0 ? '' : ' (${result.skipped} already approved)'}.',
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Bulk approve failed: $e');
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final canModerate = session != null && ReviewsAccess.canModerate(session.role);
    final reviews = ref.watch(adminReviewsProvider((_filters, _limit))).whenData(_withLocalChanges);
    final stores = ref.watch(orderStoreFilterProvider).valueOrNull ?? const <StoreModel>[];
    final storeNames = {for (final s in stores) s.id: s.name.en.isEmpty ? s.id : s.name.en};
    final sidePanel = MediaQuery.sizeOf(context).width >= _panelBreakpoint;
    final visible = reviews.valueOrNull ?? const <AdminReview>[];
    final selectable = visible.where((r) => !r.review.isApproved).toList();
    final selectedCount = selectable.where((r) => _selected.contains(r.path)).length;

    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _FilterBar(filters: _filters, stores: stores, onChanged: _setFilters),
      if (canModerate && selectable.isNotEmpty)
        _BulkBar(
          selected: selectedCount,
          selectable: selectable.length,
          busy: _bulkBusy,
          onSelectAll: (all) => setState(() {
            if (all) {
              _selected.addAll(selectable.map((r) => r.path));
            } else {
              _selected.clear();
            }
          }),
          onApprove: () => _bulkApprove(visible),
        ),
      const Divider(height: 1),
      Expanded(
        child: reviews.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => CenteredNote(
            icon: Icons.error_outline,
            text: 'Could not load reviews: $e\n\nA filter combination may need a Firestore index '
                '(collection group "reviews": isApproved / rating / storeId + createdAt desc).',
          ),
          data: (list) => list.isEmpty
              ? CenteredNote(
                  icon: Icons.rate_review_outlined,
                  text: _filters == const ReviewFilters()
                      ? 'No reviews are waiting for moderation.'
                      : 'No reviews match these filters.',
                )
              : ListView.separated(
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == list.length) {
                      return list.length < _limit
                          ? const SizedBox(height: AppSpacing.lg)
                          : Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Center(
                                child: OutlinedButton(
                                  onPressed: () => setState(() => _limit += ReviewsAdminRepository.pageSize),
                                  child: const Text('Load more'),
                                ),
                              ),
                            );
                    }
                    final r = list[i];
                    return ReviewRow(
                      key: ValueKey(r.path),
                      review: r,
                      storeName: storeNames[r.review.storeId] ?? r.review.storeId,
                      open: r.path == _open,
                      canModerate: canModerate,
                      busy: _busyRows.contains(r.path) || _bulkBusy,
                      selected: _selected.contains(r.path),
                      onSelect: r.review.isApproved
                          ? null
                          : (v) => setState(() => v ? _selected.add(r.path) : _selected.remove(r.path)),
                      onTap: () => _openReview(r, sidePanel),
                      onModerate: (approved) => _moderate(r, approved),
                      onOnlyProduct: () => _setFilters(_filters.copyWith(productId: r.review.productId)),
                    );
                  },
                ),
        ),
      ),
    ]);

    return AdminScaffold(
      title: 'Reviews',
      selectedRoute: AdminRoutes.reviews,
      body: sidePanel && _open != null
          ? Row(children: [
              Expanded(child: list),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 480,
                child:
                    ReviewDetailPanel(key: ValueKey(_open), path: _open!, onClose: () => setState(() => _open = null)),
              ),
            ])
          : list,
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.selected,
    required this.selectable,
    required this.busy,
    required this.onSelectAll,
    required this.onApprove,
  });
  final int selected;
  final int selectable;
  final bool busy;
  final ValueChanged<bool> onSelectAll;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.md, AppSpacing.sm),
        child: Row(children: [
          Checkbox(
            key: const ValueKey('selectAllReviews'),
            tristate: true,
            value: selected == 0 ? false : (selected == selectable ? true : null),
            onChanged: busy ? null : (_) => onSelectAll(selected != selectable),
          ),
          Expanded(
            child: Text(
              selected == 0 ? 'Select pending reviews to approve them together' : '$selected selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted(context)),
            ),
          ),
          FilledButton.icon(
            onPressed: selected == 0 || busy ? null : onApprove,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.done_all),
            label: Text(selected == 0 ? 'Approve selected' : 'Approve $selected'),
          ),
        ]),
      );
}

class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar({required this.filters, required this.stores, required this.onChanged});
  final ReviewFilters filters;
  final List<StoreModel> stores;
  final ValueChanged<ReviewFilters> onChanged;

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  late final _product = TextEditingController(text: widget.filters.productId ?? '');

  @override
  void didUpdateWidget(covariant _FilterBar old) {
    super.didUpdateWidget(old);
    final id = widget.filters.productId ?? '';
    if (id != old.filters.productId && _product.text.trim() != id) _product.text = id;
  }

  @override
  void dispose() {
    _product.dispose();
    super.dispose();
  }

  void _applyProduct() {
    final id = _product.text.trim();
    widget.onChanged(id.isEmpty
        ? widget.filters.copyWith(clearProduct: true)
        : widget.filters.copyWith(productId: id, clearStore: true));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filters;
    final productTitle = f.productId == null ? null : ref.watch(reviewProductTitleProvider(f.productId!));
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<ReviewApproval>(
              showSelectedIcon: false,
              segments: [
                for (final a in ReviewApproval.values) ButtonSegment(value: a, label: Text(reviewApprovalLabel(a))),
              ],
              selected: {f.approval},
              onSelectionChanged: (s) => widget.onChanged(f.copyWith(approval: s.first)),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<int?>(
                key: ValueKey('rating-${f.rating}'),
                initialValue: f.rating,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Rating', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Any rating')),
                  for (var n = 5; n >= 1; n--)
                    DropdownMenuItem<int?>(value: n, child: Text('$n star${n == 1 ? '' : 's'}')),
                ],
                onChanged: (v) => widget.onChanged(f.copyWith(rating: v, clearRating: v == null)),
              ),
            ),
            if (f.productId == null)
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('store-${f.storeId}'),
                  initialValue: widget.stores.any((s) => s.id == f.storeId) ? f.storeId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Store', isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All stores')),
                    for (final s in widget.stores)
                      DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text(s.name.en.isEmpty ? s.id : s.name.en, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => widget.onChanged(f.copyWith(storeId: v, clearStore: v == null)),
                ),
              ),
            SizedBox(
              width: 240,
              child: TextField(
                key: const ValueKey('reviewProductFilter'),
                controller: _product,
                decoration: InputDecoration(
                  labelText: 'Product id',
                  isDense: true,
                  helperText: productTitle?.when(
                    data: (t) => t ?? 'No product with this id',
                    loading: () => '…',
                    error: (_, __) => null,
                  ),
                  suffixIcon: f.productId == null
                      ? IconButton(
                          tooltip: 'Filter by product', icon: const Icon(Icons.search), onPressed: _applyProduct)
                      : IconButton(
                          tooltip: 'Clear product',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _product.clear();
                            widget.onChanged(f.copyWith(clearProduct: true));
                          },
                        ),
                ),
                onSubmitted: (_) => _applyProduct(),
              ),
            ),
            if (f != const ReviewFilters())
              TextButton(
                onPressed: () {
                  _product.clear();
                  widget.onChanged(const ReviewFilters());
                },
                child: const Text('Reset filters'),
              ),
          ]),
    );
  }
}

/// One row of the queue: stars, first name, product (link to the editor),
/// store, text excerpt, photo count, date, order link and quick actions.
class ReviewRow extends ConsumerWidget {
  const ReviewRow({
    super.key,
    required this.review,
    required this.storeName,
    required this.onTap,
    required this.onModerate,
    required this.onOnlyProduct,
    this.onSelect,
    this.selected = false,
    this.open = false,
    this.canModerate = false,
    this.busy = false,
  });

  final AdminReview review;
  final String storeName;
  final VoidCallback onTap;
  final ValueChanged<bool> onModerate;
  final VoidCallback onOnlyProduct;

  /// Null for approved reviews (only pending ones are bulk-approved).
  final ValueChanged<bool>? onSelect;
  final bool selected;
  final bool open;
  final bool canModerate;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = review.review;
    final title = ref.watch(reviewProductTitleProvider(r.productId)).valueOrNull ?? r.productId;
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 12);
    final fmt = DateFormat('MMM d, HH:mm', 'en_US');
    return Material(
      color: open ? AppColors.soft(context) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (canModerate)
              Checkbox(
                value: onSelect == null ? false : selected,
                onChanged: onSelect == null || busy ? null : (v) => onSelect!(v ?? false),
              )
            else
              const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ReviewStars(r.rating),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(r.userName.isEmpty ? 'Customer' : r.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ReviewApprovalPill(approved: r.isApproved),
                  const Spacer(),
                  if (r.createdAt != null) Text(fmt.format(r.createdAt!.toLocal()), style: muted),
                ]),
                const SizedBox(height: AppSpacing.xs),
                Row(children: [
                  Flexible(
                    child: LinkText(title.isEmpty ? '(product)' : title,
                        onTap: () => context.go(AdminRoutes.product(r.productId))),
                  ),
                  IconButton(
                    tooltip: 'Only this product',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: onOnlyProduct,
                    icon: const Icon(Icons.filter_alt_outlined),
                  ),
                  Flexible(child: Text(storeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted)),
                ]),
                Text(
                  r.text.isEmpty ? '(rating only)' : reviewExcerpt(r.text),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(children: [
                  Icon(Icons.image_outlined, size: 14, color: AppColors.textMuted(context)),
                  Text(' ${r.images.length} photo${r.images.length == 1 ? '' : 's'}', style: muted),
                  const SizedBox(width: AppSpacing.md),
                  if (r.orderId.isNotEmpty) ...[
                    Icon(Icons.receipt_long_outlined, size: 14, color: AppColors.textMuted(context)),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(child: LinkText('Order', onTap: () => showOrderDialog(context, r.orderId))),
                  ],
                ]),
              ]),
            ),
            if (canModerate) ...[
              const SizedBox(width: AppSpacing.sm),
              r.isApproved
                  ? IconButton(
                      tooltip: 'Hide',
                      onPressed: busy ? null : () => onModerate(false),
                      icon: Icon(Icons.visibility_off_outlined, color: Theme.of(context).colorScheme.error),
                    )
                  : IconButton(
                      tooltip: 'Approve',
                      onPressed: busy ? null : () => onModerate(true),
                      icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
                    ),
            ],
          ]),
        ),
      ),
    );
  }
}
