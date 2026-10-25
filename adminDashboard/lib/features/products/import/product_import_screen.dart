import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';

import '../../../core/router/admin_routes.dart';
import '../../../core/session/admin_session.dart';
import '../../../core/web/browser.dart';
import '../../../core/widgets/admin_scaffold.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../stores/widgets/detail_widgets.dart';
import 'csv_codec.dart';
import 'product_csv.dart';
import 'product_importer.dart';

/// A file chosen by the admin.
class PickedCsvFile {
  const PickedCsvFile(this.name, this.bytes);
  final String name;
  final List<int> bytes;
}

/// Opens the browser's file chooser (tests override it).
final csvFilePickerProvider = Provider<Future<PickedCsvFile?> Function()>((ref) => () async {
      final result =
          await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv'], withData: true);
      final file = result?.files.singleOrNull;
      if (file?.bytes == null) return null;
      return PickedCsvFile(file!.name, file.bytes!);
    });

/// Category / store / city ids the rows may use (also fills the template's example).
final productImportRefsProvider =
    FutureProvider.autoDispose<ProductImportRefs>((ref) => ref.watch(productImporterProvider).loadRefs());

enum _RowFilter { all, errors, create, update }

/// SRS §9 Products "bulk import CSV": pick a .csv → preview with per-row,
/// per-column validation (the editor's rules) → import the valid rows in
/// batches of ≤ 400 writes, each with a `product.import` audit entry →
/// summary. Catalogue staff only (super / ops / content).
class ProductImportScreen extends ConsumerStatefulWidget {
  const ProductImportScreen({super.key});

  static const maxBytes = 5 * 1024 * 1024;
  static const maxRows = 5000;

  @override
  ConsumerState<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends ConsumerState<ProductImportScreen> {
  String? _fileName;
  ImportPlan? _plan;
  Map<int, ProductCsvRow> _rowsByNumber = const {};
  String? _fatal;
  bool _analyzing = false;
  bool _importing = false;
  (int, int)? _progress;
  ImportSummary? _summary;
  _RowFilter _filter = _RowFilter.all;
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void _downloadTemplate() {
    final refs = ref.read(productImportRefsProvider).valueOrNull;
    String? first(Set<String>? s) => s == null || s.isEmpty ? null : (s.toList()..sort()).first;
    downloadText(
      'golden-gift-products-template.csv',
      ProductCsv.template(
        exampleCategory: first(refs?.categoryIds),
        exampleStore: first(refs?.storeIds),
        exampleCity: first(refs?.cityIds),
      ),
    );
  }

  Future<void> _pick() async {
    final file = await ref.read(csvFilePickerProvider)();
    if (file == null || !mounted) return;
    setState(() {
      _fileName = file.name;
      _plan = null;
      _fatal = null;
      _summary = null;
      _progress = null;
      _filter = _RowFilter.all;
      _analyzing = true;
    });
    try {
      if (file.bytes.length > ProductImportScreen.maxBytes) {
        throw const CsvFormatException('The file is larger than 5 MB — split it into smaller files.');
      }
      final sheet = parseProductSheet(decodeCsvBytes(file.bytes));
      if (sheet.rows.isEmpty) throw const CsvFormatException('The file has a header but no product rows.');
      if (sheet.rows.length > ProductImportScreen.maxRows) {
        throw CsvFormatException('${sheet.rows.length} rows — import at most ${ProductImportScreen.maxRows} per file.');
      }
      final refs = await ref.read(productImportRefsProvider.future);
      final plan = await ref.read(productImporterProvider).analyze(sheet, refs: refs);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _rowsByNumber = {for (final r in sheet.rows) r.row: r};
      });
    } on CsvFormatException catch (e) {
      if (mounted) setState(() => _fatal = e.message);
    } catch (e) {
      if (mounted) setState(() => _fatal = 'Could not read the file: $e');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _import() async {
    final plan = _plan;
    final session = ref.read(adminSessionProvider);
    if (plan == null || session == null) return;
    final creates = plan.count(ImportAction.create), updates = plan.count(ImportAction.update);
    final skipped = plan.rows.length - creates - updates;
    final ok = await confirmAction(
      context,
      title: 'Import ${creates + updates} product${creates + updates == 1 ? '' : 's'}?',
      message: '$creates new, $updates updated'
          '${skipped == 0 ? '' : '; $skipped row${skipped == 1 ? '' : 's'} with errors or no changes will be skipped'}. '
          'Each batch of up to ${ProductImporter.productsPerBatch} products is recorded in the audit log.',
      confirmLabel: 'Import',
    );
    if (!ok || !mounted) return;
    setState(() {
      _importing = true;
      _progress = (0, creates + updates);
    });
    try {
      final summary = await ref.read(productImporterProvider).commit(
        plan,
        adminUid: session.uid,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done, total));
        },
      );
      if (mounted) setState(() => _summary = summary);
    } catch (e) {
      if (mounted) showMessage(context, 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final allowed = session != null && ProductImportAccess.canImport(session.role);
    return AdminScaffold(
      title: 'Import products',
      selectedRoute: AdminRoutes.products,
      body: !allowed
          ? CenteredNote(
              icon: Icons.lock_outline,
              text: 'Your role can’t import products. Catalogue staff (super, ops, content) can.',
              action: OutlinedButton(
                  onPressed: () => context.go(AdminRoutes.products), child: const Text('Back to products')),
            )
          : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final plan = _plan;
    final muted = TextStyle(color: AppColors.textMuted(context));
    final top = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _analyzing || _importing ? null : _pick,
                icon: _analyzing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_outlined),
                label: Text(_fileName == null ? 'Choose CSV file' : 'Choose another file'),
              ),
              OutlinedButton.icon(
                onPressed: _downloadTemplate,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download template'),
              ),
              TextButton.icon(
                onPressed: _importing ? null : () => context.go(AdminRoutes.products),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to products'),
              ),
            ]),
        const SizedBox(height: AppSpacing.sm),
        const _FormatHelp(),
        if (_fileName != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_analyzing ? 'Checking $_fileName…' : _fileName!, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
        if (_fatal != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(_fatal!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (plan != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            [
              '${plan.rows.length} row${plan.rows.length == 1 ? '' : 's'}',
              '${plan.count(ImportAction.create)} to create',
              '${plan.count(ImportAction.update)} to update',
              if (plan.count(ImportAction.unchanged) > 0) '${plan.count(ImportAction.unchanged)} without changes',
              '${plan.count(ImportAction.invalid)} with errors',
            ].join(' · '),
            style: muted,
          ),
          if (plan.sheet.ignoredColumns.isNotEmpty)
            Text('Ignored columns: ${plan.sheet.ignoredColumns.join(', ')}', style: muted),
          const SizedBox(height: AppSpacing.sm),
          if (_summary == null)
            Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('runImport'),
                    onPressed: _importing || plan.writable.isEmpty ? null : _import,
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text(plan.writable.isEmpty
                        ? 'Nothing to import'
                        : 'Import ${plan.writable.length} product${plan.writable.length == 1 ? '' : 's'}'),
                  ),
                  if (plan.count(ImportAction.invalid) > 0)
                    Text('Rows with errors are skipped — fix them in the file and choose it again.', style: muted),
                ]),
          if (_progress != null && _importing) ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: _progress!.$2 == 0 ? null : _progress!.$1 / _progress!.$2),
            const SizedBox(height: AppSpacing.xs),
            Text('Imported ${_progress!.$1} of ${_progress!.$2}…', style: muted),
          ],
          if (_summary != null) _SummaryCard(summary: _summary!),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<_RowFilter>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _RowFilter.all, label: Text('All (${plan.rows.length})')),
              ButtonSegment(value: _RowFilter.errors, label: Text('Errors (${plan.count(ImportAction.invalid)})')),
              ButtonSegment(value: _RowFilter.create, label: Text('Create (${plan.count(ImportAction.create)})')),
              ButtonSegment(value: _RowFilter.update, label: Text('Update (${plan.count(ImportAction.update)})')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ]),
    );
    if (plan == null) return SingleChildScrollView(child: top);
    final rows = [
      for (final r in plan.rows)
        if (switch (_filter) {
          _RowFilter.all => true,
          _RowFilter.errors => r.action == ImportAction.invalid,
          _RowFilter.create => r.action == ImportAction.create,
          _RowFilter.update => r.action == ImportAction.update,
        })
          r,
    ];
    return LayoutBuilder(
      builder: (context, page) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The controls scroll on their own when tall (help open, long summary),
        // leaving at least 40 % of the page to the preview.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: page.maxHeight * 0.6),
          child: SingleChildScrollView(child: top),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final width = math.max(c.maxWidth, _PreviewTable.minWidth);
            return Scrollbar(
              controller: _hScroll,
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: _PreviewTable(rows: rows, cellsByRow: _rowsByNumber),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }
}

class _FormatHelp extends StatelessWidget {
  const _FormatHelp();

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 12);
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('csvFormatHelp'),
          dense: true,
          title: const Text('CSV format'),
          subtitle: Text('UTF-8, comma separated, first row = header. Lists use |.', style: muted),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(ProductCsv.all.join(','), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: AppSpacing.sm),
            for (final c in ProductCsv.all)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      width: 130, child: Text(c, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Expanded(child: Text(ProductCsv.help[c]!, style: const TextStyle(fontSize: 12))),
                ]),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'A row without an id creates a product. A row with an existing id updates only its non-empty cells; '
              'a cell with just “${ProductCsv.clearToken}” clears an optional field (compare price, stock → unlimited, '
              'translations, lists). Sales and view counts, ratings and option groups are never changed by an import. '
              'Columns not listed here are ignored.',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final ImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Card(
      key: const ValueKey('importSummary'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Import finished',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          Text('${s.created.length} created · ${s.updated.length} updated · ${s.skipped.length} skipped'
              '${s.failed.isEmpty ? '' : ' · ${s.failed.length} failed'}'),
          for (final (row, reason) in s.failed.take(20)) Text('Row $row: $reason', style: error),
          if (s.skipped.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text('Skipped rows (${s.skipped.length})'),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (row, reason) in s.skipped.take(200))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      child: Text('Row $row: $reason', style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}

/// The preview: one line per CSV row, the problem cells in the error colour.
class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.rows, required this.cellsByRow});
  final List<ImportRowPlan> rows;
  final Map<int, ProductCsvRow> cellsByRow;

  static const _columns = <(String, String?, double)>[
    ('Row', null, 56),
    ('Action', null, 112),
    ('Id', ProductCsv.id, 190),
    ('Title', ProductCsv.title, 230),
    ('Price', ProductCsv.price, 110),
    ('Store', ProductCsv.storeId, 150),
    ('Categories', ProductCsv.categoryIds, 170),
  ];
  static const _detailsWidth = 360.0;
  static double get minWidth => _columns.fold<double>(0, (w, c) => w + c.$3) + _detailsWidth + AppSpacing.md * 2;

  @override
  Widget build(BuildContext context) {
    final header = Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted(context));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(children: [
          for (final (label, _, width) in _columns) SizedBox(width: width, child: Text(label, style: header)),
          Expanded(child: Text('Details', style: header)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: rows.isEmpty
            ? const CenteredNote(icon: Icons.filter_alt_off_outlined, text: 'No rows in this view.')
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _PreviewRow(plan: rows[i], cells: cellsByRow[rows[i].row]),
              ),
      ),
    ]);
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.plan, required this.cells});
  final ImportRowPlan plan;
  final ProductCsvRow? cells;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    final m = p.model;
    final errorColor = Theme.of(context).colorScheme.error;
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 12);

    Widget cell(String? column, String text, double width, {TextStyle? style}) {
      final bad = column != null && p.issuesFor(column).isNotEmpty;
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Row(children: [
            if (bad)
              Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(Icons.error_outline, size: 14, color: errorColor)),
            Flexible(
              child: Text(
                text.isEmpty ? '—' : text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: bad ? TextStyle(color: errorColor, fontWeight: FontWeight.w600) : style,
              ),
            ),
          ]),
        ),
      );
    }

    final raw = cells;
    final details = <Widget>[
      for (final issue in p.issues) Text(issue.toString(), style: TextStyle(color: errorColor, fontSize: 12)),
      if (p.action == ImportAction.update) Text('Changes: ${p.changedFields.join(', ')}', style: muted),
      if (p.action == ImportAction.unchanged) Text('Already up to date — skipped.', style: muted),
      if (p.action == ImportAction.create && (raw?.cell(ProductCsv.id).isEmpty ?? true))
        Text('New id from the title', style: muted),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        cell(null, '${p.row}', _PreviewTable._columns[0].$3, style: muted),
        SizedBox(
            width: _PreviewTable._columns[1].$3,
            child: Align(alignment: Alignment.centerLeft, child: _ActionPill(p.action))),
        cell(ProductCsv.id, p.id ?? raw?.cell(ProductCsv.id) ?? '', _PreviewTable._columns[2].$3),
        cell(ProductCsv.title, m?.title.en ?? raw?.cell(ProductCsv.title) ?? '', _PreviewTable._columns[3].$3,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        cell(ProductCsv.price, m != null ? CurrencyFormatter.format(m.price) : raw?.cell(ProductCsv.price) ?? '',
            _PreviewTable._columns[4].$3,
            style: TextStyle(color: AppColors.goldText(context), fontWeight: FontWeight.w700)),
        cell(ProductCsv.storeId, m?.storeId ?? raw?.cell(ProductCsv.storeId) ?? '', _PreviewTable._columns[5].$3),
        cell(ProductCsv.categoryIds, m?.categoryIds.join(', ') ?? raw?.cell(ProductCsv.categoryIds) ?? '',
            _PreviewTable._columns[6].$3),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: details)),
      ]),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill(this.action);
  final ImportAction action;

  @override
  Widget build(BuildContext context) => StatusPill(
        label: importActionLabel(action),
        color: switch (action) {
          ImportAction.create => AppColors.success,
          ImportAction.update => AppColors.info,
          ImportAction.unchanged => AppColors.textSecondary,
          ImportAction.invalid => AppColors.error,
        },
      );
}
