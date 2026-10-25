import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:uuid/uuid.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import 'data/broadcast_repository.dart';

/// In-app routes a broadcast can open (paths of the app's AppRoutes / ProductQuery).
const broadcastRoutes = <(String, String)>[
  ('', 'Nothing (just open the app)'),
  ('/main?tab=0', 'Home'),
  ('/products?sort=newest', 'New arrivals'),
  ('/products?sale=1', 'Offers'),
  ('/products?featured=1', 'Featured gifts'),
  ('/categories', 'All categories'),
  ('/orders', 'My orders'),
  ('/invite', 'Invite & earn'),
];

/// SRS §9 Notifications: trilingual broadcast composer + history.
class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key});

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  final _form = GlobalKey<FormState>();
  LocalizedText _title = LocalizedText.empty;
  LocalizedText _body = LocalizedText.empty;
  String _route = '';
  String? _imageUrl;
  bool _sending = false;

  /// Bumped after a send so the trilingual fields rebuild empty.
  int _generation = 0;
  final _imageId = const Uuid().v4();

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final ok = await confirmAction(
      context,
      title: 'Send to every customer?',
      message: 'This pushes “${_title.en}” to all customers who allow notifications and adds it to everyone’s '
          'notification list. It cannot be unsent.',
      confirmLabel: 'Send now',
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      final result = await ref
          .read(broadcastRepositoryProvider)
          .send(title: _title, body: _body, route: _route, imageUrl: _imageUrl);
      if (!mounted) return;
      showMessage(context, 'Sent to ${result.sent} device(s).');
      setState(() {
        _title = LocalizedText.empty;
        _body = LocalizedText.empty;
        _route = '';
        _imageUrl = null;
        _generation++;
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        showMessage(
            context,
            e.code == 'not-found' || e.code == 'unavailable' || e.code == 'internal'
                ? 'The sendBroadcast function is not deployed yet.'
                : 'Could not send: ${e.message ?? e.code}');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final canSend = session != null && (session.isSuper || session.role == AdminRole.ops || session.role == AdminRole.content);
    final composer = Form(
      key: _form,
      child: SectionCard(
        key: ValueKey(_generation),
        title: 'New broadcast',
        children: [
          TrilingualField(
            label: 'Title',
            value: _title,
            maxLength: BroadcastRepository.titleMax,
            onChanged: (v) => setState(() => _title = v),
          ),
          TrilingualField(
            label: 'Message',
            value: _body,
            maxLines: 3,
            maxLength: BroadcastRepository.bodyMax,
            onChanged: (v) => setState(() => _body = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: _route,
            decoration: const InputDecoration(labelText: 'When tapped, open'),
            items: [for (final (r, l) in broadcastRoutes) DropdownMenuItem(value: r, child: Text(l))],
            onChanged: (v) => setState(() => _route = v ?? ''),
          ),
          const SizedBox(height: AppSpacing.md),
          ImageField(
            label: 'Image (optional)',
            value: _imageUrl,
            onChanged: (v) => setState(() => _imageUrl = v),
            storagePath: () => 'broadcasts/$_imageId.jpg',
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Preview', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          _Preview(title: _title, body: _body),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: !canSend || _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: const Text('Send to all customers'),
            ),
          ),
          if (!canSend)
            Text('Your role cannot send broadcasts.', style: TextStyle(color: AppColors.textMuted(context))),
        ],
      ),
    );

    return AdminScaffold(
      title: 'Notifications',
      selectedRoute: AdminRoutes.notifications,
      body: LayoutBuilder(builder: (context, c) {
        const history = _History();
        if (c.maxWidth < 1100) {
          return ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
            composer,
            const SizedBox(height: AppSpacing.md),
            const SectionCard(title: 'Sent broadcasts', children: [history]),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [composer])),
          Expanded(
            flex: 2,
            child: ListView(padding: const EdgeInsets.all(AppSpacing.md), children: const [
              SectionCard(title: 'Sent broadcasts', children: [history]),
            ]),
          ),
        ]);
      }),
    );
  }
}

/// Roughly how the push looks on a phone, in each language.
class _Preview extends StatelessWidget {
  const _Preview({required this.title, required this.body});
  final LocalizedText title;
  final LocalizedText body;

  @override
  Widget build(BuildContext context) {
    Widget card(String t, String b, TextDirection dir) => Directionality(
          textDirection: dir,
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.line(context)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.card_giftcard, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.isEmpty ? 'Title' : t, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(b.isEmpty ? 'Message' : b, maxLines: 3, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        );
    return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
      card(title.en, body.en, TextDirection.ltr),
      card(title.ar ?? title.en, body.ar ?? body.en, TextDirection.rtl),
      card(title.ku ?? title.en, body.ku ?? body.en, TextDirection.rtl),
    ]);
  }
}

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(broadcastHistoryProvider);
    final fmt = DateFormat('yyyy-MM-dd HH:mm', 'en_US');
    return history.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Could not load history: $e'),
      data: (list) => list.isEmpty
          ? Text('Nothing sent yet.', style: TextStyle(color: AppColors.textMuted(context)))
          : Column(children: [
              for (final r in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.notification.title.en),
                  subtitle: Text([
                    r.notification.body.en,
                    [
                      if (r.notification.createdAt != null) fmt.format(r.notification.createdAt!.toLocal()),
                      if (r.sentCount != null) '${r.sentCount} device(s)',
                      if (r.notification.route != null) '→ ${r.notification.route}',
                    ].join(' · '),
                  ].join('\n')),
                  isThreeLine: true,
                ),
            ]),
    );
  }
}
