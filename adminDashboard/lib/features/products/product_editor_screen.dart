import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/store_model.dart';

import '../../core/router/admin_routes.dart';
import '../../core/session/admin_session.dart';
import '../../core/widgets/admin_scaffold.dart';
import '../../core/widgets/form_widgets.dart';
import 'data/products_admin_repository.dart';
import 'domain/product_draft.dart';
import 'widgets/leave_guard_stub.dart' if (dart.library.js_interop) 'widgets/leave_guard_web.dart';
import 'widgets/option_group_builder.dart';
import 'widgets/product_form_fields.dart';

/// Unsaved-changes state of the open product editor, shared with the router
/// (`GoRoute.onExit: ProductEditorGuard.onExit`) and the browser tab
/// (`beforeunload`).
class ProductEditorGuard {
  ProductEditorGuard._();

  static Object? _owner;

  static bool get hasUnsavedChanges => _owner != null;

  static void _update(Object owner, bool dirty) {
    if (dirty) {
      _owner = owner;
    } else if (identical(_owner, owner)) {
      _owner = null;
    }
    setBrowserLeaveWarning(_owner != null);
  }

  /// For `GoRoute(onExit: …)` on the new / edit product routes.
  static Future<bool> onExit(BuildContext context, GoRouterState state) => confirmLeave(context);

  /// True when there is nothing to lose or the admin chose to discard.
  static Future<bool> confirmLeave(BuildContext context) async {
    if (!hasUnsavedChanges) return true;
    final discard = await confirmAction(
      context,
      title: 'Discard unsaved changes?',
      message: 'This product has changes that haven’t been saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (discard) {
      _owner = null;
      setBrowserLeaveWarning(false);
    }
    return discard;
  }
}

/// Create / edit a product (SRS §9 "Products", §6.4, §5.9 option groups).
///
/// Partner accounts (SRS §9 Seller view) create and edit only their own
/// store's products: the store is locked to theirs, Featured and Delete are
/// hidden, and another store's product is not opened.
class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, this.productId});

  /// null = new product.
  final String? productId;

  @override
  ConsumerState<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();

  ProductDraft? _draft;
  Object? _loadError;
  bool _notFound = false;
  String _savedFingerprint = '';
  bool _dirty = false;
  bool _saving = false;
  List<String> _errors = const [];

  /// Upload folder of a product that has no id yet (fixed at the first upload).
  String? _provisionalId;

  @override
  void initState() {
    super.initState();
    if (widget.productId == null) {
      _setDraft(ProductDraft());
      // Default store: the only / first one, once they're loaded.
      // Sellers: always their own store.
      ref.listenManual<AdminSession?>(adminSessionProvider, (_, session) {
        final d = _draft;
        if (session == null || !session.isSeller || d == null || !d.isNew || d.storeId == session.storeId) return;
        setState(() {
          d.storeId = session.storeId;
          if (!_dirty) _savedFingerprint = d.fingerprint();
        });
      }, fireImmediately: true);
      ref.listenManual<AsyncValue<List<StoreModel>>>(productStoreOptionsProvider, (_, next) {
        final stores = next.valueOrNull;
        final d = _draft;
        if (ref.read(adminSessionProvider)?.isSeller ?? false) return;
        if (stores == null || stores.isEmpty || d == null || d.storeId != null) return;
        setState(() {
          d.storeId = stores.first.id;
          if (!_dirty) _savedFingerprint = d.fingerprint();
        });
      }, fireImmediately: true);
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    ProductEditorGuard._update(this, false);
    _scroll.dispose();
    super.dispose();
  }

  void _setDraft(ProductDraft d) {
    _draft = d;
    _savedFingerprint = d.fingerprint();
    _dirty = false;
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final p = await ref.read(productsAdminRepositoryProvider).load(widget.productId!);
      if (!mounted) return;
      setState(() {
        if (p == null) {
          _notFound = true;
        } else {
          _setDraft(ProductDraft.fromModel(p));
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// Every field calls this after changing the draft.
  void _changed() {
    final d = _draft!;
    setState(() {
      _dirty = d.fingerprint() != _savedFingerprint;
      // Once a save has failed, keep the list of problems live.
      if (_errors.isNotEmpty) _errors = d.validate();
    });
    ProductEditorGuard._update(this, _dirty);
  }

  String _storageFolder() {
    final d = _draft!;
    final id = d.id ?? (_provisionalId ??= _newFolderId(d));
    return 'products/$id';
  }

  String _newFolderId(ProductDraft d) {
    final slug = slugify(d.title.en);
    return slug.isNotEmpty ? slug : ref.read(productsAdminRepositoryProvider).autoId();
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _save() async {
    final d = _draft!;
    final fieldsOk = _formKey.currentState?.validate() ?? true;
    final errors = d.validate();
    if (!fieldsOk || errors.isNotEmpty) {
      setState(() {
        _errors = errors.isEmpty ? const ['Fix the highlighted fields.'] : errors;
        if (errors.any((e) => e.startsWith('Option group'))) {
          for (final g in d.groups) {
            g.expanded = true;
          }
        }
      });
      _scrollToTop();
      return;
    }
    final session = ref.read(adminSessionProvider);
    final uid = session?.uid;
    if (uid == null) {
      showMessage(context, 'Your session has ended — sign in again.');
      return;
    }
    if (session!.isSeller) {
      if (!d.isNew && d.storeId != session.storeId) return;
      d.storeId = session.storeId;
    }
    setState(() {
      _saving = true;
      _errors = const [];
    });
    final repo = ref.read(productsAdminRepositoryProvider);
    try {
      final isNew = d.isNew;
      final id = d.id ?? await repo.newProductId(d.title.en);
      await repo.save(d.toModel(id), isNew: isNew, adminUid: uid);
      if (!mounted) return;
      d
        ..id = id
        ..lockIds();
      setState(() {
        _savedFingerprint = d.fingerprint();
        _dirty = false;
        _saving = false;
      });
      ProductEditorGuard._update(this, false);
      showMessage(context, isNew ? 'Product created' : 'Product saved');
      if (isNew) context.go(AdminRoutes.product(id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = ['Could not save: $e'];
      });
      _scrollToTop();
    }
  }

  Future<void> _delete() async {
    final d = _draft!;
    final ok = await confirmAction(
      context,
      title: 'Delete product?',
      message: 'Delete “${d.title.en}” permanently? Customers will no longer see it. '
          'To hide it for now, turn off Active instead.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final uid = ref.read(adminSessionProvider)?.uid;
    if (uid == null) {
      showMessage(context, 'Your session has ended — sign in again.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(productsAdminRepositoryProvider).delete(d.id!, adminUid: uid);
      if (!mounted) return;
      _dirty = false;
      ProductEditorGuard._update(this, false);
      showMessage(context, 'Product deleted');
      context.go(AdminRoutes.products);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = ['Could not delete: $e'];
      });
    }
  }

  Future<void> _backToList() async {
    if (await ProductEditorGuard.confirmLeave(context) && mounted) context.go(AdminRoutes.products);
  }

  /// A seller opened another store's product.
  bool _isForeign(AdminSession? session) {
    final d = _draft;
    return session != null && session.isSeller && d != null && !d.isNew && d.storeId != session.storeId;
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    final session = ref.watch(adminSessionProvider);
    final seller = session?.isSeller ?? false;
    final foreign = _isForeign(session);
    return AdminScaffold(
      title: widget.productId == null ? 'New product' : 'Edit product',
      selectedRoute: AdminRoutes.products,
      actions: [
        if (d != null && !d.isNew && !seller)
          IconButton(
            tooltip: 'Delete product',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : _delete,
          ),
        if (d != null && !foreign)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ),
      ],
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loadError != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        text: 'Could not load the product. $_loadError',
        action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_notFound) {
      return _CenteredMessage(
        icon: Icons.search_off,
        text: 'Product “${widget.productId}” doesn’t exist.',
        action: OutlinedButton(onPressed: () => context.go(AdminRoutes.products), child: const Text('All products')),
      );
    }
    final d = _draft;
    if (d == null) return const Center(child: CircularProgressIndicator());
    if (_isForeign(ref.watch(adminSessionProvider))) {
      return _CenteredMessage(
        icon: Icons.lock_outline,
        text: 'This product belongs to another store.',
        action: OutlinedButton(onPressed: () => context.go(AdminRoutes.products), child: const Text('Your products')),
      );
    }

    return Form(
      key: _formKey,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1000;
        final basics = _basics(d);
        final images = _images(d);
        final options = OptionGroupBuilder(groups: d.groups, onChanged: _changed, storageFolder: _storageFolder);
        final side = [_visibility(d), _pricing(d), _availability(d), _organisation(d), _cities(d)];
        return SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _header(d),
                if (_errors.isNotEmpty) ...[const SizedBox(height: AppSpacing.md), _ErrorPanel(errors: _errors)],
                const SizedBox(height: AppSpacing.md),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _stack([basics, images, options])),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(width: 360, child: _stack(side)),
                  ])
                else
                  _stack([basics, ...side, images, options]),
                const SizedBox(height: AppSpacing.xl),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _stack(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          children[i],
        ],
      ]);

  TextStyle? _muted(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  Widget _header(ProductDraft d) => Row(children: [
        TextButton.icon(onPressed: _backToList, icon: const Icon(Icons.arrow_back), label: const Text('All products')),
        const Spacer(),
        if (_dirty)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Text('Unsaved changes', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (!d.isNew) SelectableText('id: ${d.id}', style: _muted(context)),
      ]);

  Widget _basics(ProductDraft d) => SectionCard(title: 'Basics', children: [
        TrilingualField(
          label: 'Title',
          value: d.title,
          onChanged: (t) {
            d.title = t;
            _changed();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TrilingualField(
          label: 'Description',
          value: d.description,
          required: false,
          maxLines: 6,
          onChanged: (t) {
            d.description = t;
            _changed();
          },
        ),
      ]);

  Widget _images(ProductDraft d) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Images',
      trailing: TextButton.icon(
        onPressed: () {
          d.addImageSlot();
          _changed();
        },
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add image'),
      ),
      children: [
        Text('The first image is the main image (product card, cart). Upload or paste a URL.', style: _muted(context)),
        const SizedBox(height: AppSpacing.sm),
        if (d.images.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('No images yet.', style: _muted(context)),
          ),
        for (final (i, slot) in d.images.indexed)
          Padding(
            key: ObjectKey(slot),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 44,
                child: Column(children: [
                  Text('${i + 1}', style: Theme.of(context).textTheme.titleSmall),
                  if (i == 0)
                    Container(
                      margin: const EdgeInsets.only(top: AppSpacing.xs),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text('Main', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onPrimary)),
                    ),
                ]),
              ),
              Expanded(
                child: ImageField(
                  label: 'Image ${i + 1}',
                  value: slot.url,
                  previewSize: 72,
                  storagePath: () => '${_storageFolder()}/${slot.storageIndex}.jpg',
                  onChanged: (url) {
                    slot.url = url;
                    _changed();
                  },
                ),
              ),
              Column(children: [
                IconButton(
                  tooltip: 'Move image up',
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  onPressed: i > 0
                      ? () {
                          d.images.insert(i - 1, d.images.removeAt(i));
                          _changed();
                        }
                      : null,
                ),
                IconButton(
                  tooltip: 'Move image down',
                  icon: const Icon(Icons.arrow_downward, size: 20),
                  onPressed: i < d.images.length - 1
                      ? () {
                          d.images.insert(i + 1, d.images.removeAt(i));
                          _changed();
                        }
                      : null,
                ),
                IconButton(
                  tooltip: 'Remove image',
                  icon: Icon(Icons.close, size: 20, color: scheme.error),
                  onPressed: () {
                    d.images.remove(slot);
                    _changed();
                  },
                ),
              ]),
            ]),
          ),
      ],
    );
  }

  Widget _visibility(ProductDraft d) => SectionCard(title: 'Visibility', children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Shown in the app'),
          value: d.isActive,
          onChanged: (v) {
            d.isActive = v;
            _changed();
          },
        ),
        if (!(ref.watch(adminSessionProvider)?.isSeller ?? false))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Featured'),
            subtitle: const Text('Home ▸ Featured'),
            value: d.isFeatured,
            onChanged: (v) {
              d.isFeatured = v;
              _changed();
            },
          ),
      ]);

  Widget _pricing(ProductDraft d) {
    final price = d.price, compare = d.compareAtPrice;
    Widget hint;
    if (compare != null && price != null && compare <= price) {
      hint = Text('Must be greater than the price, or empty.',
          style: _muted(context)?.copyWith(color: Theme.of(context).colorScheme.error));
    } else if (compare != null && price != null && price > 0) {
      final pct = ((compare - price) * 100 / compare).round();
      hint = Text('Shows −$pct% · ${CurrencyFormatter.format(price)} instead of ${CurrencyFormatter.format(compare)}',
          style: _muted(context));
    } else {
      hint = Text('Optional: the old price, shown struck through.', style: _muted(context));
    }
    return SectionCard(title: 'Pricing', children: [
      MoneyField(
        label: 'Price',
        value: d.price,
        onChanged: (v) {
          d.price = v;
          _changed();
        },
      ),
      const SizedBox(height: AppSpacing.sm),
      MoneyField(
        label: 'Compare-at price',
        value: d.compareAtPrice,
        required: false,
        onChanged: (v) {
          d.compareAtPrice = v;
          _changed();
        },
      ),
      const SizedBox(height: AppSpacing.xs),
      hint,
    ]);
  }

  Widget _availability(ProductDraft d) => SectionCard(title: 'Availability & stock', children: [
        DropdownButtonFormField<ProductAvailability>(
          initialValue: d.availability,
          decoration: const InputDecoration(labelText: 'Availability'),
          items: [
            for (final a in ProductAvailability.values)
              DropdownMenuItem(value: a, child: Text(availabilityLabel(a))),
          ],
          onChanged: (v) {
            if (v == null) return;
            d.availability = v;
            _changed();
          },
        ),
        if (d.availability != ProductAvailability.sameDay) ...[
          const SizedBox(height: AppSpacing.sm),
          IntField(
            key: const ValueKey('preparationDays'),
            label: d.availability == ProductAvailability.preparationDays ? 'Preparation days *' : 'Preparation days',
            value: d.preparationDays,
            helperText: 'Days needed before it can ship',
            validator: (v) =>
                d.availability == ProductAvailability.preparationDays && (v ?? 0) < 1 ? 'At least 1' : null,
            onChanged: (v) {
              d.preparationDays = v;
              _changed();
            },
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        IntField(
          label: 'Stock',
          value: d.stock,
          helperText: 'Empty = unlimited',
          onChanged: (v) {
            d.stock = v;
            _changed();
          },
        ),
      ]);

  Widget _organisation(ProductDraft d) {
    final stores = ref.watch(productStoreOptionsProvider);
    final categories = ref.watch(productCategoryOptionsProvider);
    return SectionCard(title: 'Organisation', children: [
      stores.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load stores: $e'),
        data: (list) => _storePicker(d, list),
      ),
      const SizedBox(height: AppSpacing.md),
      Text('Categories', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      categories.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load categories: $e'),
        data: (list) => _categoryPicker(d, list),
      ),
      const SizedBox(height: AppSpacing.md),
      GiftForField(
        selected: d.giftFor,
        onChanged: (audience, selected) {
          d.setGiftFor(audience, selected);
          _changed();
        },
      ),
      const SizedBox(height: AppSpacing.md),
      TagsField(
        tags: d.tags,
        onChanged: (tags) {
          d.tags
            ..clear()
            ..addAll(tags);
          _changed();
        },
      ),
    ]);
  }

  Widget _storePicker(ProductDraft d, List<StoreModel> stores) {
    final session = ref.watch(adminSessionProvider);
    if (session != null && session.isSeller) {
      final own = stores.where((s) => s.id == session.storeId).firstOrNull;
      return DropdownButtonFormField<String>(
        key: ValueKey('store-locked:${session.storeId}'),
        initialValue: session.storeId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Store', helperText: 'Your store'),
        items: [
          DropdownMenuItem(
            value: session.storeId,
            child: Text(own?.name.en ?? session.storeId ?? '', overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: null,
      );
    }
    final known = stores.any((s) => s.id == d.storeId);
    return DropdownButtonFormField<String>(
      key: ValueKey('store:${d.storeId}'),
      initialValue: d.storeId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Store *',
        helperText: stores.isEmpty ? 'No stores yet — create one first.' : null,
      ),
      items: [
        for (final s in stores)
          DropdownMenuItem(
            value: s.id,
            child: Text(s.isActive ? s.name.en : '${s.name.en} (${s.status.name})', overflow: TextOverflow.ellipsis),
          ),
        if (d.storeId != null && !known) DropdownMenuItem(value: d.storeId, child: Text('${d.storeId} (missing)')),
      ],
      validator: (v) => v == null ? 'Required' : null,
      onChanged: (v) {
        d.storeId = v;
        _changed();
      },
    );
  }

  Widget _categoryPicker(ProductDraft d, List<CategoryModel> categories) {
    if (categories.isEmpty && d.categoryIds.isEmpty) {
      return Text('No categories yet (Categories module).', style: _muted(context));
    }
    return ChipMultiSelect(
      options: {for (final c in categories) c.id: c.title.en.isEmpty ? c.id : c.title.en},
      dimmed: {for (final c in categories) if (!c.isActive) c.id},
      selected: d.categoryIds,
      onChanged: (ids) {
        d.categoryIds
          ..clear()
          ..addAll(ids);
        _changed();
      },
    );
  }

  Widget _cities(ProductDraft d) {
    final cities = ref.watch(productCityOptionsProvider);
    return SectionCard(title: 'Delivery cities', children: [
      Text(
        d.availableCities.isEmpty
            ? 'Deliverable to every city (none selected).'
            : 'Only the ${d.availableCities.length} selected cit${d.availableCities.length == 1 ? 'y' : 'ies'}.',
        style: _muted(context),
      ),
      const SizedBox(height: AppSpacing.sm),
      cities.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load cities: $e'),
        data: (List<CityModel> list) => list.isEmpty && d.availableCities.isEmpty
            ? Text('No cities configured yet (Settings ▸ Cities).', style: _muted(context))
            : ChipMultiSelect(
                options: {for (final c in list) c.id: c.name.en.isEmpty ? c.id : c.name.en},
                dimmed: {for (final c in list) if (!c.isActive) c.id},
                selected: d.availableCities,
                onChanged: (ids) {
                  d.availableCities
                    ..clear()
                    ..addAll(ids);
                  _changed();
                },
              ),
      ),
      if (d.availableCities.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () {
              d.availableCities.clear();
              _changed();
            },
            child: const Text('Clear — deliver everywhere'),
          ),
        ),
    ]);
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.errors});
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: scheme.onErrorContainer);
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.sm),
            Text('Fix these before saving', style: style.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          for (final e in errors)
            Padding(padding: const EdgeInsets.only(top: AppSpacing.xs), child: Text('• $e', style: style)),
        ]),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
          ]),
        ),
      );
}
