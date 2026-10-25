import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/product_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import 'data/products_admin_repository.dart';
import 'domain/product_search.dart';
import 'import/product_importer.dart' show ProductImportAccess;

enum _ActiveFilter { all, active, inactive }

/// Products table (SRS §9 "Products"): newest first, 50 per page, search,
/// category / active filters, inline Active & Featured toggles, "Rebuild
/// search keywords", "Import CSV" (catalogue staff).
///
/// Partner accounts (SRS §9 Seller view) see only their own store's products,
/// without the Featured toggle and the catalogue-wide keyword rebuild.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  static const _allCategories = '';

  final _search = TextEditingController();
  Timer? _debounce;
  String _categoryId = _allCategories;
  _ActiveFilter _active = _ActiveFilter.all;

  List<ProductModel> _rows = const [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _generation = 0;

  /// Whole-catalogue hits for a one-word search (`searchKeywords array-contains`).
  String? _keyword;
  List<ProductModel> _keywordHits = const [];
  bool _searching = false;
  int _searchGeneration = 0;

  bool _rebuilding = false;
  int _rebuildScanned = 0;

  /// Inline toggles applied before the next reload: id → field → value.
  final _flagOverrides = <String, Map<String, bool>>{};
  final _busyToggles = <String>{};

  ProductsAdminRepository get _repo => ref.read(productsAdminRepositoryProvider);

  /// The seller's store (null = staff see every store). Nothing loads until
  /// the session is known, so a seller never gets the whole catalogue.
  String? _storeScope;
  bool _scopeKnown = false;

  bool get _isSeller => _storeScope != null;

  String? get _categoryFilter => _categoryId == _allCategories ? null : _categoryId;

  bool? get _activeFilter => switch (_active) {
        _ActiveFilter.all => null,
        _ActiveFilter.active => true,
        _ActiveFilter.inactive => false,
      };

  @override
  void initState() {
    super.initState();
    ref.listenManual<AdminSession?>(adminSessionProvider, (_, session) {
      if (session == null) return;
      final scope = session.isSeller ? (session.storeId ?? '-') : null;
      if (_scopeKnown && scope == _storeScope) return;
      _storeScope = scope;
      _scopeKnown = true;
      _keyword = null;
      _reload();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!_scopeKnown) return;
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.fetchPage(categoryId: _categoryFilter, isActive: _activeFilter, storeId: _storeScope);
      if (!mounted || gen != _generation) return;
      setState(() {
        _rows = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
        _flagOverrides.clear();
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.fetchPage(
          categoryId: _categoryFilter, isActive: _activeFilter, storeId: _storeScope, after: _cursor);
      if (!mounted || gen != _generation) return;
      setState(() {
        _rows = [..._rows, ...page.items];
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) showMessage(context, 'Could not load more products: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runKeywordSearch);
  }

  Future<void> _runKeywordSearch() async {
    if (!mounted || !_scopeKnown) return;
    final keyword = singleSearchKeyword(_search.text);
    if (keyword == _keyword && keyword != null) return;
    final gen = ++_searchGeneration;
    if (keyword == null) {
      setState(() {
        _keyword = null;
        _keywordHits = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final hits = await _repo.searchKeyword(keyword, storeId: _storeScope);
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _keyword = keyword;
        _keywordHits = hits;
        _searching = false;
      });
    } catch (_) {
      // The client filter over the loaded pages still works.
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _keyword = keyword;
        _keywordHits = const [];
        _searching = false;
      });
    }
  }

  bool _flag(ProductModel p, String field) =>
      _flagOverrides[p.id]?[field] ?? (field == 'isActive' ? p.isActive : p.isFeatured);

  bool _passesFilters(ProductModel p) =>
      (_storeScope == null || p.storeId == _storeScope) &&
      (_categoryFilter == null || p.categoryIds.contains(_categoryFilter)) &&
      (_activeFilter == null || _flag(p, 'isActive') == _activeFilter);

  /// Loaded rows filtered by the search box, plus whole-catalogue keyword hits.
  List<ProductModel> get _visible {
    final query = _search.text.trim();
    if (query.isEmpty) return _rows;
    final byId = <String, ProductModel>{
      for (final p in _rows)
        if (matchesProductSearch(p, query)) p.id: p,
    };
    if (_keyword != null && _keyword == singleSearchKeyword(query)) {
      for (final p in _keywordHits) {
        if (_passesFilters(p)) byId.putIfAbsent(p.id, () => p);
      }
    }
    return byId.values.toList()
      ..sort((a, b) {
        if (a.createdAt == null || b.createdAt == null) return a.createdAt == null ? 1 : -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
  }

  Future<void> _toggle(ProductModel p, String field, bool value) async {
    final uid = ref.read(adminSessionProvider)?.uid;
    if (uid == null) return;
    final key = '${p.id}.$field';
    setState(() {
      _busyToggles.add(key);
      (_flagOverrides[p.id] ??= {})[field] = value;
    });
    try {
      await _repo.setFlag(p.id, field, value, adminUid: uid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _flagOverrides[p.id]![field] = !value);
      showMessage(context, 'Could not update “${p.title.en}”: $e');
    } finally {
      if (mounted) setState(() => _busyToggles.remove(key));
    }
  }

  Future<void> _rebuildKeywords() async {
    final ok = await confirmAction(
      context,
      title: 'Rebuild search keywords?',
      message: 'Recomputes searchKeywords and the other derived query fields (price band, city keys, '
          'gift-type keys, discount flag) of every product with the app’s tokenizer. Only products whose fields '
          'changed are written.',
      confirmLabel: 'Rebuild',
    );
    if (!ok || !mounted) return;
    final uid = ref.read(adminSessionProvider)?.uid;
    if (uid == null) return;
    setState(() {
      _rebuilding = true;
      _rebuildScanned = 0;
    });
    try {
      final r = await _repo.rebuildSearchFields(
        adminUid: uid,
        onProgress: (n) {
          if (mounted) setState(() => _rebuildScanned = n);
        },
      );
      if (!mounted) return;
      showMessage(
        context,
        r.updated == 0
            ? 'All ${r.scanned} products were already up to date.'
            : 'Updated ${r.updated} of ${r.scanned} products.',
      );
      _keyword = null;
      unawaited(_reload());
      unawaited(_runKeywordSearch());
    } catch (e) {
      if (mounted) showMessage(context, 'Rebuild failed: $e');
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(productCategoryOptionsProvider).valueOrNull ?? const <CategoryModel>[];
    final names = {for (final c in categories) c.id: c.title.en.isEmpty ? c.id : c.title.en};
    final session = ref.watch(adminSessionProvider);
    final canImport = !_isSeller && session != null && ProductImportAccess.canImport(session.role);
    return AdminScaffold(
      title: 'Products',
      selectedRoute: AdminRoutes.products,
      actions: [
        if (canImport)
          TextButton.icon(
            key: const ValueKey('importCsv'),
            onPressed: () => context.go(AdminRoutes.productImport),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Import CSV'),
          ),
        if (!_isSeller)
          TextButton.icon(
            onPressed: _rebuilding ? null : _rebuildKeywords,
            icon: _rebuilding
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.manage_search),
            label: Text(_rebuilding ? 'Rebuilding… $_rebuildScanned' : 'Rebuild search keywords'),
          ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AdminRoutes.productNew),
        icon: const Icon(Icons.add),
        label: const Text('New product'),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_rebuilding) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: _toolbar(categories),
        ),
        Expanded(child: _table(names)),
      ]),
    );
  }

  Widget _toolbar(List<CategoryModel> categories) {
    final hasCategory = categories.any((c) => c.id == _categoryId);
    return Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(
        width: 320,
        child: TextField(
          key: const ValueKey('productSearch'),
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Search title, id or tag',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _onSearchChanged('');
                        },
                      ),
          ),
          onChanged: _onSearchChanged,
        ),
      ),
      SizedBox(
        width: 240,
        child: DropdownButtonFormField<String>(
          key: const ValueKey('categoryFilter'),
          initialValue: _categoryId == _allCategories || hasCategory ? _categoryId : _allCategories,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            const DropdownMenuItem(value: _allCategories, child: Text('All categories')),
            for (final c in categories)
              DropdownMenuItem(
                value: c.id,
                child: Text(c.title.en.isEmpty ? c.id : c.title.en, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            setState(() => _categoryId = v ?? _allCategories);
            _reload();
          },
        ),
      ),
      SegmentedButton<_ActiveFilter>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: _ActiveFilter.all, label: Text('All')),
          ButtonSegment(value: _ActiveFilter.active, label: Text('Active')),
          ButtonSegment(value: _ActiveFilter.inactive, label: Text('Inactive')),
        ],
        selected: {_active},
        onSelectionChanged: (s) {
          setState(() => _active = s.first);
          _reload();
        },
      ),
    ]);
  }

  Widget _table(Map<String, String> categoryNames) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not load products. $_error', textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: _reload, child: const Text('Retry')),
        ]),
      );
    }
    final rows = _visible;
    final filtered = _search.text.trim().isNotEmpty || _categoryFilter != null || _activeFilter != null;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xxl * 2),
        itemCount: rows.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return _HeaderRow(wide: wide, showFeatured: !_isSeller);
          if (i == rows.length + 1) return _footer(rows.length, filtered);
          final p = rows[i - 1];
          return _ProductRow(
            key: ValueKey(p.id),
            product: p,
            wide: wide,
            categoryNames: categoryNames,
            isActive: _flag(p, 'isActive'),
            isFeatured: _flag(p, 'isFeatured'),
            activeBusy: _busyToggles.contains('${p.id}.isActive'),
            featuredBusy: _busyToggles.contains('${p.id}.isFeatured'),
            showFeatured: !_isSeller,
            onToggle: (field, value) => _toggle(p, field, value),
            onOpen: () => context.go(AdminRoutes.product(p.id)),
          );
        },
      );
    });
  }

  Widget _footer(int shown, bool filtered) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(children: [
        if (shown == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(filtered ? 'No products match.' : 'No products yet — add the first one.'),
          )
        else
          Text('$shown shown', style: muted),
        if (_hasMore) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _loadingMore ? null : _loadMore,
            child: _loadingMore
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Load more'),
          ),
        ],
      ]),
    );
  }
}

const _thumbSize = 48.0;
const _priceWidth = 130.0;
const _availabilityWidth = 150.0;
const _toggleWidth = 80.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.wide, this.showFeatured = true});
  final bool wide;
  final bool showFeatured;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        child: Row(children: [
          const SizedBox(width: _thumbSize + AppSpacing.md),
          Expanded(flex: 4, child: Text('Product', style: style)),
          if (wide) Expanded(flex: 3, child: Text('Categories', style: style)),
          SizedBox(width: _priceWidth, child: Text('Price', style: style, textAlign: TextAlign.end)),
          const SizedBox(width: AppSpacing.md),
          SizedBox(width: _availabilityWidth, child: Text('Availability', style: style)),
          SizedBox(width: _toggleWidth, child: Text('Active', style: style, textAlign: TextAlign.center)),
          if (showFeatured)
            SizedBox(width: _toggleWidth, child: Text('Featured', style: style, textAlign: TextAlign.center)),
          const SizedBox(width: 24),
        ]),
      ),
      const Divider(height: 1),
    ]);
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    super.key,
    required this.product,
    required this.wide,
    required this.categoryNames,
    required this.isActive,
    required this.isFeatured,
    required this.activeBusy,
    required this.featuredBusy,
    required this.onToggle,
    required this.onOpen,
    this.showFeatured = true,
  });

  final ProductModel product;
  final bool wide;
  final Map<String, String> categoryNames;
  final bool isActive;
  final bool isFeatured;
  final bool activeBusy;
  final bool featuredBusy;
  final void Function(String field, bool value) onToggle;
  final VoidCallback onOpen;

  /// Hidden for sellers (featuring is Golden Gift's call).
  final bool showFeatured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final p = product;
    final categories = [for (final id in p.categoryIds) categoryNames[id] ?? id].join(', ');
    return Column(children: [
      InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          child: Row(children: [
            _Thumb(url: p.mainImage),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 4,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  p.title.en.isEmpty ? '(untitled)' : p.title.en,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  wide || categories.isEmpty ? p.id : '${p.id} · $categories',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ]),
            ),
            if (wide)
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(categories.isEmpty ? '—' : categories,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  Text(
                    p.giftFor.isEmpty ? 'Gift for: not set' : p.giftFor.map(giftAudienceLabel).join(' · '),
                    key: ValueKey('giftFor-${p.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: p.giftFor.isEmpty ? muted?.copyWith(color: scheme.error) : muted,
                  ),
                ]),
              ),
            SizedBox(
              width: _priceWidth,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  CurrencyFormatter.format(p.price),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.goldText(context), fontWeight: FontWeight.w700),
                ),
                if (p.hasDiscount)
                  Text(CurrencyFormatter.format(p.compareAtPrice!),
                      style: muted?.copyWith(decoration: TextDecoration.lineThrough)),
              ]),
            ),
            const SizedBox(width: AppSpacing.md),
            SizedBox(width: _availabilityWidth, child: _Availability(product: p)),
            SizedBox(
              width: _toggleWidth,
              child: Center(
                child: Switch(
                  key: ValueKey('active-${p.id}'),
                  value: isActive,
                  onChanged: activeBusy ? null : (v) => onToggle('isActive', v),
                ),
              ),
            ),
            if (showFeatured)
              SizedBox(
                width: _toggleWidth,
                child: Center(
                  child: Switch(
                    key: ValueKey('featured-${p.id}'),
                    value: isFeatured,
                    onChanged: featuredBusy ? null : (v) => onToggle('isFeatured', v),
                  ),
                ),
              ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
      const Divider(height: 1),
    ]);
  }
}

class _Availability extends StatelessWidget {
  const _Availability({required this.product});
  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = product;
    final error = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error);
    final normal = theme.textTheme.bodySmall;
    final (label, style) = switch (p.availability) {
      ProductAvailability.sameDay => ('Same day', normal),
      ProductAvailability.preparationDays => ('${p.preparationDays} day${p.preparationDays == 1 ? '' : 's'} prep', normal),
      ProductAvailability.outOfStock => ('Out of stock', error),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: style),
      if (p.stock != null) Text('Stock ${p.stock}', style: p.stock! <= 0 ? error : normal),
    ]);
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: SizedBox(
        width: _thumbSize,
        height: _thumbSize,
        child: url == null
            ? placeholder
            : Image.network(
                url!,
                fit: BoxFit.cover,
                cacheWidth: (_thumbSize * 2).round(),
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}
