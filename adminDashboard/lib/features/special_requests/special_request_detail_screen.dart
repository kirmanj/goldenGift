import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/special_request_model.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import '../orders/data/admin_orders_repository.dart';
import '../stores/widgets/detail_widgets.dart';
import '../stores/widgets/store_sales_card.dart' show showOrderDialog;
import 'data/special_requests_admin_repository.dart';
import 'special_request_ui.dart';

/// `/special-requests/:id` (SRS §5.17, §9): the request and its photos, the
/// customer, the message thread with a reply box, status actions, Send quote
/// and Assign to me. Accepting a quote happens in the app (`acceptQuote`),
/// which links the new order here.
class SpecialRequestDetailScreen extends ConsumerWidget {
  const SpecialRequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(adminSpecialRequestProvider(requestId));
    return AdminScaffold(
      title: 'Special request',
      selectedRoute: AdminRoutes.specialRequests,
      body: request.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => CenteredNote(icon: Icons.error_outline, text: 'Could not load the request: $e'),
        data: (r) => r == null
            ? CenteredNote(
                icon: Icons.search_off,
                text: 'Request “$requestId” doesn’t exist.',
                action: OutlinedButton(
                    onPressed: () => context.go(AdminRoutes.specialRequests), child: const Text('All requests')),
              )
            : _Body(request: r),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.request});
  final SpecialRequestModel request;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  SpecialRequestModel get _r => widget.request;

  Future<void> _run(Future<void> Function(String uid) action, String done) async {
    final uid = ref.read(adminSessionProvider)?.uid;
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      await action(uid);
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, e is SpecialRequestException ? e.message : 'Could not update the request: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  SpecialRequestsAdminRepository get _repo => ref.read(specialRequestsAdminRepositoryProvider);

  Future<void> _move(SpecialRequestStatus next) async {
    if (next == SpecialRequestStatus.rejected) {
      final reason = await showReasonDialog(
        context,
        title: 'Reject this request?',
        message: 'The reason is posted in the thread for the customer.',
        label: 'Reason (shown to the customer) *',
        confirmLabel: 'Reject',
        destructive: true,
      );
      if (reason == null || !mounted) return;
      return _run((uid) => _repo.setStatus(_r, next, reason: reason, adminUid: uid), 'Request rejected');
    }
    final withdrawing = _r.status == SpecialRequestStatus.quoted && next == SpecialRequestStatus.inReview;
    if (withdrawing) {
      final ok = await confirmAction(context,
          title: 'Withdraw the quote?',
          message: 'The customer can no longer accept ${CurrencyFormatter.format(_r.quoteAmount ?? 0)}; they are told '
              'an updated quote will follow.',
          confirmLabel: 'Withdraw');
      if (!ok || !mounted) return;
    }
    await _run((uid) => _repo.setStatus(_r, next, adminUid: uid), 'Status: ${specialRequestStatusLabel(next)}');
  }

  Future<void> _quote() async {
    final result = await showDialog<(int, String)>(context: context, builder: (_) => QuoteDialog(request: _r));
    if (result == null || !mounted) return;
    await _run((uid) => _repo.sendQuote(_r, amount: result.$1, note: result.$2, adminUid: uid), 'Quote sent');
  }

  String _actionLabel(SpecialRequestStatus next) => switch (next) {
        SpecialRequestStatus.inReview =>
          _r.status == SpecialRequestStatus.quoted ? 'Withdraw quote' : 'Mark in review',
        SpecialRequestStatus.rejected => 'Reject',
        SpecialRequestStatus.completed => _r.type == SpecialRequestType.support ? 'Mark resolved' : 'Mark completed',
        _ => specialRequestStatusLabel(next),
      };

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final canAct = session != null && SpecialRequestsAccess.canAct(session.role);
    final r = _r;
    final moves = requestTransitions(r).where((s) => s != SpecialRequestStatus.quoted).toList();
    final actions = Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
      if (canSendQuote(r))
        FilledButton.icon(
          onPressed: _busy ? null : _quote,
          icon: const Icon(Icons.request_quote_outlined),
          label: const Text('Send quote'),
        ),
      for (final s in moves)
        s == SpecialRequestStatus.rejected
            ? OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: _busy ? null : () => _move(s),
                child: Text(_actionLabel(s)),
              )
            : OutlinedButton(onPressed: _busy ? null : () => _move(s), child: Text(_actionLabel(s))),
      if (session != null && r.assignedAdminUid != session.uid)
        TextButton.icon(
          onPressed: _busy ? null : () => _run((uid) => _repo.assignTo(r, adminUid: uid), 'Assigned to you'),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Assign to me'),
        ),
    ]);

    final details = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(request: r),
      const SizedBox(height: AppSpacing.md),
      if (canAct) actions else Text('Your role can read requests but not answer them.', style: TextStyle(color: AppColors.textMuted(context))),
      const SizedBox(height: AppSpacing.md),
      _RequestCard(request: r),
      const SizedBox(height: AppSpacing.md),
      _CustomerCard(request: r),
      if (r.quoteAmount != null || r.orderId != null) ...[
        const SizedBox(height: AppSpacing.md),
        _QuoteCard(request: r),
      ],
    ]);
    final thread = _Thread(request: r, canReply: canAct);

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 1100) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 5,
            child: ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [_back(context), details]),
          ),
          const VerticalDivider(width: 1),
          Expanded(flex: 6, child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: thread)),
        ]);
      }
      return ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
        _back(context),
        details,
        const SizedBox(height: AppSpacing.md),
        SizedBox(height: 560, child: thread),
      ]);
    });
  }

  Widget _back(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => context.go(AdminRoutes.specialRequests),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Inbox'),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.request});
  final SpecialRequestModel request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final fmt = DateFormat('yyyy-MM-dd HH:mm', 'en_US');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(r.customerName ?? 'Customer',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        SpecialRequestTypeChip(r.type),
        SpecialRequestStatusChip(r.status),
      ]),
      const SizedBox(height: AppSpacing.xs),
      Text(
        [
          if (r.createdAt != null) 'Sent ${fmt.format(r.createdAt!.toLocal())}',
          if (r.lastMessageAt != null) 'last activity ${fmt.format(r.lastMessageAt!.toLocal())}',
          if (r.lastMessageBy == 'customer') 'awaiting our reply',
        ].join(' · '),
        style: TextStyle(color: AppColors.textMuted(context)),
      ),
    ]);
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});
  final SpecialRequestModel request;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: request.type == SpecialRequestType.gift ? 'The idea' : 'Message',
        children: [
          SelectableText(request.text.isEmpty ? '—' : request.text),
          if (request.images.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(spacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Photos (${request.images.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('click one to open it full size', style: TextStyle(color: AppColors.textMuted(context), fontSize: 12)),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
              for (final url in request.images) ImageThumb(url: url, size: 96),
            ]),
          ],
        ],
      );
}

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.request});
  final SpecialRequestModel request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final session = ref.watch(adminSessionProvider);
    final assigned = r.assignedAdminUid;
    final assignedName = assigned == null ? null : ref.watch(adminNameProvider(assigned)).valueOrNull;
    return SectionCard(title: 'Customer', children: [
      KeyValueRow('Name', r.customerName ?? ''),
      KeyValueRow('Phone', r.customerPhone ?? '', copy: r.customerPhone),
      KeyValueRow(
        'Account',
        r.userId,
        child: r.userId.isEmpty
            ? const Text('—')
            : Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.goldText(context), padding: EdgeInsets.zero),
                  onPressed: () => context.go(AdminRoutes.user(r.userId)),
                  child: Text(r.userId, overflow: TextOverflow.ellipsis),
                ),
              ),
      ),
      KeyValueRow(
        'Assigned to',
        assigned == null
            ? 'Nobody yet'
            : assigned == session?.uid
                ? 'You'
                : (assignedName ?? assigned),
      ),
    ]);
  }
}

class _QuoteCard extends ConsumerWidget {
  const _QuoteCard({required this.request});
  final SpecialRequestModel request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final orderId = r.orderId;
    final order = orderId == null ? null : ref.watch(adminOrderProvider(orderId));
    return SectionCard(title: 'Quote & order', children: [
      if (r.quoteAmount != null) KeyValueRow('Quoted', CurrencyFormatter.format(r.quoteAmount!)),
      if ((r.quoteNote ?? '').isNotEmpty) KeyValueRow('Note', r.quoteNote!),
      if (orderId == null)
        KeyValueRow('Order', '',
            child: Text(
              r.status == SpecialRequestStatus.quoted ? 'Waiting for the customer to accept in the app.' : '—',
              style: TextStyle(color: AppColors.textMuted(context)),
            ))
      else
        KeyValueRow(
          'Order',
          orderId,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.goldText(context), padding: EdgeInsets.zero),
              onPressed: () => showOrderDialog(context, orderId),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(
                order?.valueOrNull?.orderNumber.isNotEmpty ?? false ? order!.valueOrNull!.orderNumber : orderId,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Message thread (admin bubbles gold, customer neutral) with a reply box.
class _Thread extends ConsumerStatefulWidget {
  const _Thread({required this.request, required this.canReply});
  final SpecialRequestModel request;
  final bool canReply;

  @override
  ConsumerState<_Thread> createState() => _ThreadState();
}

class _ThreadState extends ConsumerState<_Thread> {
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  int _lastCount = 0;

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final uid = ref.read(adminSessionProvider)?.uid;
    final text = _reply.text.trim();
    if (uid == null || text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(specialRequestsAdminRepositoryProvider).reply(widget.request, text, adminUid: uid);
      _reply.clear();
    } catch (e) {
      if (mounted) showMessage(context, e is SpecialRequestException ? e.message : 'Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd(int count) {
    if (count == _lastCount) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(adminSpecialRequestMessagesProvider(widget.request.id));
    final theme = Theme.of(context);
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: Text('Conversation', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load messages: $e')),
            data: (list) {
              _scrollToEnd(list.length);
              if (list.isEmpty) {
                return Center(
                  child: Text('No messages yet — reply to start the conversation.',
                      style: TextStyle(color: AppColors.textMuted(context))),
                );
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: list.length,
                itemBuilder: (_, i) => MessageBubble(message: list[i]),
              );
            },
          ),
        ),
        if (widget.canReply) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('replyField'),
                  controller: _reply,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: SpecialRequestRules.maxMessage,
                  decoration: const InputDecoration(hintText: 'Write a reply to the customer', counterText: ''),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _sending || _reply.text.trim().isEmpty ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: const Text('Send'),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});
  final SpecialRequestMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final admin = m.isFromAdmin;
    final bg = admin ? AppColors.gold(context) : AppColors.field(context);
    final fg = admin ? AppColors.textOnPrimary : AppColors.text(context);
    final at = m.at == null ? '' : DateFormat('MMM d, HH:mm', 'en_US').format(m.at!.toLocal());
    return Align(
      alignment: admin ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(m.text, style: TextStyle(color: fg)),
            if (m.images.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
                for (final url in m.images) ImageThumb(url: url, size: 64),
              ]),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text('${admin ? 'Golden Gift' : 'Customer'}${at.isEmpty ? '' : ' · $at'}',
                style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

/// Send quote: amount ≥ 1,000 IQD, note ≤ 500. Resolves to (amount, note).
class QuoteDialog extends StatefulWidget {
  const QuoteDialog({super.key, required this.request});
  final SpecialRequestModel request;

  @override
  State<QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<QuoteDialog> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.request.quoteAmount?.toString() ?? '');
  late final _note = TextEditingController(text: widget.request.quoteNote ?? '');
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final amount = int.tryParse(_amount.text.trim());
    final error = validateQuote(amount, _note.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (amount!, _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final amount = int.tryParse(_amount.text.trim());
    return AlertDialog(
      title: const Text('Send a quote'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('The customer sees the amount in the app and can accept it, which creates the order.'),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('quoteAmount'),
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Amount (IQD) *', helperText: 'At least 1,000 IQD'),
              validator: (v) => validateQuote(int.tryParse(v?.trim() ?? ''), ''),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const ValueKey('quoteNote'),
              controller: _note,
              maxLength: SpecialRequestRules.maxQuoteNote,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(labelText: 'Note for the customer (optional)'),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (amount != null && amount > 0)
              Text('Posted as: “${quoteMessage(amount, _note.text)}”', style: TextStyle(color: AppColors.textMuted(context))),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Send quote')),
      ],
    );
  }
}
