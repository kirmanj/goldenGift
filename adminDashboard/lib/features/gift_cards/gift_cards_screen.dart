import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/gift_card_model.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../stores/widgets/detail_widgets.dart';
import '../stores/widgets/store_sales_card.dart' show showOrderDialog;
import 'data/gift_cards_admin_repository.dart';
import 'gift_card_detail_panel.dart';
import 'gift_card_ui.dart';
import 'issue_gift_card_dialog.dart';
import 'template_editor_dialog.dart';

/// SRS §9 Gift cards: templates CRUD (+ order), issued cards with status
/// filter and code search, detail drawer, disable, manual issue.
class GiftCardsScreen extends ConsumerWidget {
  const GiftCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const AdminScaffold(
        title: 'Gift cards',
        selectedRoute: AdminRoutes.giftCards,
        body: DefaultTabController(
          length: 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [Tab(text: 'Templates'), Tab(text: 'Issued cards')],
            ),
            Divider(height: 1),
            Expanded(child: TabBarView(children: [TemplatesTab(), IssuedCardsTab()])),
          ]),
        ),
      );
}

// ── Templates ─────────────────────────────────────────────────────────────

class TemplatesTab extends ConsumerStatefulWidget {
  const TemplatesTab({super.key});

  @override
  ConsumerState<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends ConsumerState<TemplatesTab> {
  bool _busy = false;

  String get _uid => ref.read(adminSessionProvider)?.uid ?? '';

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(List<GiftCardTemplateModel> list, int index, int delta) => _guard(() async {
        final ordered = [...list];
        final item = ordered.removeAt(index);
        ordered.insert(index + delta, item);
        await ref.read(giftCardsAdminRepositoryProvider).reorder(ordered, adminUid: _uid);
      });

  Future<void> _delete(GiftCardTemplateModel t) async {
    final repo = ref.read(giftCardsAdminRepositoryProvider);
    final ok = await confirmAction(context,
        title: 'Delete “${t.name.en}”?',
        message: 'The template is removed from the shop. Templates already used by issued cards cannot be deleted.',
        confirmLabel: 'Delete',
        destructive: true);
    if (!ok || !mounted) return;
    await _guard(() async {
      try {
        await repo.deleteTemplate(t, adminUid: _uid);
        if (mounted) showMessage(context, 'Template deleted');
      } on TemplateInUseException {
        if (!mounted) return;
        final deactivate = await confirmAction(context,
            title: 'This template is in use',
            message: 'Cards were issued with “${t.name.en}”, so it can’t be deleted. Deactivate it instead? '
                'It disappears from the shop and issued cards keep working.',
            confirmLabel: 'Deactivate');
        if (deactivate) {
          await repo.setTemplateActive(t, false, adminUid: _uid);
          if (mounted) showMessage(context, 'Template deactivated');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final canEdit = session != null && GiftCardsAccess.canEditTemplates(session.role);
    final templates = ref.watch(adminGiftCardTemplatesProvider);
    return templates.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => CenteredNote(icon: Icons.error_outline, text: 'Could not load templates: $e'),
      data: (list) {
        final nextSort = list.isEmpty ? 0 : list.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
        return ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
          Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Shown in the app (Home ▸ Gift cards, shop) in this order.',
                style: TextStyle(color: AppColors.textMuted(context))),
            if (canEdit)
              FilledButton.icon(
                onPressed: _busy ? null : () => showTemplateEditor(context, nextSortOrder: nextSort),
                icon: const Icon(Icons.add),
                label: const Text('New template'),
              ),
          ]),
          const SizedBox(height: AppSpacing.md),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: Text('No templates yet.')),
            )
          else
            Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
              for (final (i, t) in list.indexed)
                _TemplateTile(
                  key: ValueKey(t.id),
                  template: t,
                  canEdit: canEdit && !_busy,
                  onEdit: () => showTemplateEditor(context, template: t, nextSortOrder: nextSort),
                  onEarlier: i > 0 ? () => _move(list, i, -1) : null,
                  onLater: i < list.length - 1 ? () => _move(list, i, 1) : null,
                  onDelete: () => _delete(t),
                  onToggleActive: (v) => _guard(
                      () => ref.read(giftCardsAdminRepositoryProvider).setTemplateActive(t, v, adminUid: _uid)),
                ),
            ]),
        ]);
      },
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    super.key,
    required this.template,
    required this.canEdit,
    required this.onEdit,
    required this.onEarlier,
    required this.onLater,
    required this.onDelete,
    required this.onToggleActive,
  });

  final GiftCardTemplateModel template;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback? onEarlier;
  final VoidCallback? onLater;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleActive;

  @override
  Widget build(BuildContext context) {
    final t = template;
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 12);
    return SizedBox(
      width: 300,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Opacity(
              opacity: t.isActive ? 1 : 0.5,
              child: GiftCardPreview(
                name: t.name.en,
                amount: t.presetAmounts.isNotEmpty ? t.presetAmounts.first : null,
                gradientStart: t.gradientStart,
                gradientEnd: t.gradientEnd,
                artworkUrl: t.artworkUrl,
                width: 276,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(
                child: Text(t.name.en.isEmpty ? t.id : t.name.en,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text('#${t.sortOrder}', style: muted),
            ]),
            Text(templateAmountsLabel(t), maxLines: 2, overflow: TextOverflow.ellipsis, style: muted),
            Row(children: [
              Switch(
                key: ValueKey('tplActive-${t.id}'),
                value: t.isActive,
                onChanged: canEdit ? onToggleActive : null,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(t.isActive ? 'Active' : 'Inactive', style: muted)),
            ]),
            if (canEdit)
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(tooltip: 'Move earlier', onPressed: onEarlier, icon: const Icon(Icons.arrow_back, size: 18)),
                IconButton(tooltip: 'Move later', onPressed: onLater, icon: const Icon(Icons.arrow_forward, size: 18)),
                IconButton(tooltip: 'Edit template', onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18)),
                IconButton(
                  tooltip: 'Delete template',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}

// ── Issued cards ──────────────────────────────────────────────────────────

class IssuedCardsTab extends ConsumerStatefulWidget {
  const IssuedCardsTab({super.key});

  @override
  ConsumerState<IssuedCardsTab> createState() => _IssuedCardsTabState();
}

class _IssuedCardsTabState extends ConsumerState<IssuedCardsTab> {
  GiftCardStatus? _status;
  int _limit = GiftCardsAdminRepository.pageSize;
  final _code = TextEditingController();
  String? _searchCode;
  String? _selected;

  static const _panelBreakpoint = 1280.0;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _search() {
    final code = normalizeGiftCardCode(_code.text);
    setState(() => _searchCode = code.isEmpty ? null : code);
  }

  Future<void> _open(String id, bool sidePanel) async {
    if (sidePanel) {
      setState(() => _selected = id);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: GiftCardDetailPanel(cardId: id, onClose: () => Navigator.pop(context)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final canIssue = session != null && GiftCardsAccess.canIssue(session.role);
    final width = MediaQuery.sizeOf(context).width;
    final sidePanel = width >= _panelBreakpoint;
    final cards = _searchCode != null
        ? ref.watch(giftCardCodeSearchProvider(_searchCode!))
        : ref.watch(adminGiftCardsProvider((_status, _limit)));
    final templates = ref.watch(adminGiftCardTemplatesProvider).valueOrNull ?? const [];
    final templateNames = {for (final t in templates) t.id: t.name.en};

    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<GiftCardStatus?>(
              key: ValueKey('cardStatus-$_status'),
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Status', isDense: true),
              items: [
                const DropdownMenuItem<GiftCardStatus?>(value: null, child: Text('All statuses')),
                for (final s in GiftCardStatus.values)
                  DropdownMenuItem<GiftCardStatus?>(value: s, child: Text(giftCardStatusLabel(s))),
              ],
              onChanged: (v) => setState(() {
                _status = v;
                _limit = GiftCardsAdminRepository.pageSize;
              }),
            ),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              key: const ValueKey('cardCodeSearch'),
              controller: _code,
              decoration: InputDecoration(
                hintText: 'Find by code (ABCD-EFGH-JKLM)',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _searchCode == null
                    ? null
                    : IconButton(
                        tooltip: 'Clear code search',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _code.clear();
                          _searchCode = null;
                        }),
                      ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          OutlinedButton(onPressed: _search, child: const Text('Find')),
          if (canIssue)
            FilledButton.icon(
              onPressed: () => showIssueGiftCardDialog(context),
              icon: const Icon(Icons.add_card),
              label: const Text('Issue gift card'),
            ),
        ]),
      ),
      if (_searchCode != null && _searchCode!.length != 12)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: Text('Codes have 12 characters — this search only finds exact matches.',
              style: TextStyle(color: AppColors.textMuted(context))),
        ),
      const Divider(height: 1),
      Expanded(
        child: cards.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => CenteredNote(
            icon: Icons.error_outline,
            text: 'Could not load gift cards: $e\n\nThe status filter needs the gift_cards (status, createdAt) index.',
          ),
          data: (rows) => rows.isEmpty
              ? CenteredNote(
                  icon: Icons.card_giftcard_outlined,
                  text: _searchCode != null ? 'No card has the code $_searchCode.' : 'No gift cards match.',
                )
              : LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 1000;
                  return ListView.separated(
                    itemCount: rows.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      if (i == rows.length) {
                        return _searchCode == null && rows.length >= _limit
                            ? Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Center(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() => _limit += GiftCardsAdminRepository.pageSize),
                                    child: const Text('Load more'),
                                  ),
                                ),
                              )
                            : const SizedBox(height: AppSpacing.lg);
                      }
                      final card = rows[i];
                      return GiftCardRow(
                        key: ValueKey(card.id),
                        card: card,
                        wide: wide,
                        templateName: card.card.templateName.en.isNotEmpty
                            ? card.card.templateName.en
                            : (templateNames[card.card.templateId] ?? card.card.templateId),
                        selected: card.id == _selected,
                        onTap: () => _open(card.id, sidePanel),
                      );
                    },
                  );
                }),
        ),
      ),
    ]);

    if (!(sidePanel && _selected != null)) return list;
    return Row(children: [
      Expanded(child: list),
      const VerticalDivider(width: 1),
      SizedBox(
        width: 480,
        child: GiftCardDetailPanel(
            key: ValueKey(_selected), cardId: _selected!, onClose: () => setState(() => _selected = null)),
      ),
    ]);
  }
}

/// One issued card: code + template, amount + balance, recipient, purchaser
/// and order links, status, sent / expires / redeemed.
class GiftCardRow extends StatelessWidget {
  const GiftCardRow({
    super.key,
    required this.card,
    required this.wide,
    required this.templateName,
    required this.onTap,
    this.selected = false,
  });

  final AdminGiftCard card;
  final bool wide;
  final String templateName;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = card.card;
    final fmt = DateFormat('MMM d, yyyy', 'en_US');
    String date(DateTime? d) => d == null ? '—' : fmt.format(d.toLocal());
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 12);
    final contact = [c.recipientPhone, c.recipientEmail].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final codeCell = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(c.formattedCode, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
      Text(templateName, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
    ]);
    if (!wide) {
      return ListTile(
        selected: selected,
        selectedTileColor: AppColors.primary.withValues(alpha: 0.10),
        onTap: onTap,
        title: Row(children: [Expanded(child: codeCell), GiftCardStatusChip(c.status)]),
        subtitle: Text(
          [c.recipientName, if (contact.isNotEmpty) contact, 'expires ${date(c.expiresAt)}'].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(CurrencyFormatter.format(c.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
    Widget link(String label, VoidCallback onTap) => TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.goldText(context),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onTap,
          child: Text(label),
        );
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(children: [
            Expanded(flex: 3, child: codeCell),
            SizedBox(
              width: 130,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(CurrencyFormatter.format(c.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Balance ${CurrencyFormatter.formatCompact(c.balance)}', style: muted),
              ]),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.recipientName, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(contact.isEmpty ? '—' : contact, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              ]),
            ),
            SizedBox(
              width: 120,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (c.purchaserUid.isNotEmpty)
                  link('Purchaser', () => context.go(AdminRoutes.user(c.purchaserUid)))
                else
                  Text('Admin issue', style: muted),
                if (c.orderId != null) link('Order', () => showOrderDialog(context, c.orderId!)),
              ]),
            ),
            SizedBox(width: 110, child: Align(alignment: AlignmentDirectional.centerStart, child: GiftCardStatusChip(c.status))),
            SizedBox(
              width: 150,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sent ${date(c.sentAt)}', style: muted),
                Text('Expires ${date(c.expiresAt)}', style: muted),
                if (c.redeemedAt != null) Text('Redeemed ${date(c.redeemedAt)}', style: muted),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
