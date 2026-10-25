import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/product_model.dart';

import 'data/reel_product_search.dart';

/// "Product *" of the reel editor: the chosen product with **Change**, or a
/// search by title / id over the catalogue ([reelProductSearchProvider]).
class ReelProductPicker extends ConsumerStatefulWidget {
  const ReelProductPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.missingId,
    this.errorText,
    this.enabled = true,
  });

  final ProductModel? selected;
  final ValueChanged<ProductModel> onSelected;

  /// Id of the linked product when it no longer exists (editing an old reel).
  final String? missingId;
  final String? errorText;
  final bool enabled;

  @override
  ConsumerState<ReelProductPicker> createState() => _ReelProductPickerState();
}

class _ReelProductPickerState extends ConsumerState<ReelProductPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _changing = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  void _pick(ProductModel p) {
    setState(() => _changing = false);
    widget.onSelected(p);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final theme = Theme.of(context);
    if (selected != null && !_changing) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Product *', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Row(children: [
          Expanded(child: ReelProductTile(product: selected)),
          TextButton(
            onPressed: widget.enabled ? () => setState(() => _changing = true) : null,
            child: const Text('Change'),
          ),
        ]),
        if (!selected.isActive)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text('This product is inactive — the reel stays hidden in the app until it is active again.',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
          ),
      ]);
    }
    final results = ref.watch(reelProductSearchProvider(_query));
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.missingId != null && selected == null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text('The linked product “${widget.missingId}” no longer exists — choose another one.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ),
      TextField(
        key: const ValueKey('reelProductSearch'),
        controller: _search,
        enabled: widget.enabled,
        decoration: InputDecoration(
          labelText: 'Product *',
          hintText: 'Search by title or id',
          prefixIcon: const Icon(Icons.search),
          errorText: widget.errorText,
        ),
        onChanged: _onChanged,
      ),
      const SizedBox(height: AppSpacing.xs),
      results.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => Text('Could not search products: $e', style: TextStyle(color: theme.colorScheme.error)),
        data: (list) => list.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(_query.isEmpty ? 'No products yet.' : 'No products match “$_query”.', style: muted),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_query.isEmpty) Text('Newest products', style: muted),
                for (final p in list)
                  InkWell(
                    key: ValueKey('pickProduct-${p.id}'),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    onTap: widget.enabled ? () => _pick(p) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: ReelProductTile(product: p),
                    ),
                  ),
              ]),
      ),
      if (selected != null)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(onPressed: () => setState(() => _changing = false), child: const Text('Keep current product')),
        ),
    ]);
  }
}

/// Thumbnail, English title and "id · price · Inactive" of a product.
class ReelProductTile extends StatelessWidget {
  const ReelProductTile({super.key, required this.product});
  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = product;
    final placeholder = ColoredBox(
      color: AppColors.field(context),
      child: Icon(Icons.image_outlined, size: 20, color: AppColors.textMuted(context)),
    );
    final image = p.mainImage;
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: SizedBox(
          width: 40,
          height: 40,
          child: image == null
              ? placeholder
              : Image.network(image, fit: BoxFit.cover, cacheWidth: 80, errorBuilder: (_, __, ___) => placeholder),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.title.en.isEmpty ? p.id : p.title.en,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${p.id} · '),
              TextSpan(
                text: CurrencyFormatter.format(p.price),
                style: TextStyle(color: AppColors.goldText(context), fontWeight: FontWeight.w700),
              ),
              if (!p.isActive) const TextSpan(text: ' · Inactive', style: TextStyle(color: AppColors.warning)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context)),
          ),
        ]),
      ),
    ]);
  }
}
