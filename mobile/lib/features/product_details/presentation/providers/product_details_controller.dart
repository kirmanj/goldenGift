import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/product_model.dart';
import '../../data/product_repository.dart';
import '../../domain/product_configuration.dart';

/// Everything the Product Details screen changes while the customer
/// configures a gift (SRS §5.9).
@immutable
class ProductDetailsState {
  const ProductDetailsState({this.config, this.showIssues = false, this.uploadProgress});

  /// Null until the product has loaded.
  final ProductConfiguration? config;

  /// True after the first Add to Cart attempt: from then on every group
  /// shows its validation hint live, so a fix clears it immediately.
  final bool showIssues;

  /// 0..1 while customer photos upload; null otherwise.
  final double? uploadProgress;

  bool get isUploading => uploadProgress != null;

  /// The hint to show under [groupId], or null.
  OptionIssueKind? issueFor(String groupId) {
    final c = config;
    if (!showIssues || c == null) return null;
    for (final issue in c.validate()) {
      if (issue.groupId == groupId) return issue.kind;
    }
    return null;
  }

  ProductDetailsState copyWith({
    ProductConfiguration? config,
    bool? showIssues,
    double? Function()? uploadProgress,
  }) =>
      ProductDetailsState(
        config: config ?? this.config,
        showIssues: showIssues ?? this.showIssues,
        uploadProgress: uploadProgress == null ? this.uploadProgress : uploadProgress(),
      );
}

/// Owns one product's [ProductConfiguration]. Group widgets watch only their
/// own slice (`select`), so picking a swatch rebuilds that swatch row, the
/// price and the bottom bar — never the carousel or the other groups
/// (SRS §5.9 AC: option groups render in < 16 ms frames).
class ProductDetailsController extends StateNotifier<ProductDetailsState> {
  ProductDetailsController() : super(const ProductDetailsState());

  ProductConfiguration? get config => state.config;

  /// First load, or a live update of the product document: keeps what the
  /// customer already chose and re-clamps the quantity to the new stock.
  void attach(ProductModel product) {
    final current = state.config;
    final next = current == null
        ? ProductConfiguration(product: product)
        : ProductConfiguration(product: product, selections: current.selections, qty: current.qty).setQty(current.qty);
    state = state.copyWith(config: next);
  }

  void _update(ProductConfiguration Function(ProductConfiguration c) change) {
    final c = state.config;
    if (c == null) return;
    final next = change(c);
    // Selecting a value can lower the stock limit (or raise the price);
    // keep the quantity inside the new bounds.
    state = state.copyWith(config: next.qty > next.maxQty ? next.setQty(next.qty) : next);
  }

  void select(String groupId, String valueId) => _update((c) => c.select(groupId, valueId));

  void setText(String groupId, String text) => _update((c) => c.setText(groupId, text));

  void setDate(String groupId, DateTime? date) => _update((c) => c.setDate(groupId, date));

  void addPhoto(String groupId, PickedPhoto photo, {required int maxPhotos}) => _update((c) {
        final photos = c.selectionFor(groupId).photos;
        if (photos.length >= maxPhotos) return c;
        return c.setPhotos(groupId, [...photos, photo]);
      });

  void removePhoto(String groupId, int index) => _update((c) {
        final photos = [...c.selectionFor(groupId).photos];
        if (index < 0 || index >= photos.length) return c;
        photos.removeAt(index);
        return c.setPhotos(groupId, photos);
      });

  void setQty(int qty) => _update((c) => c.setQty(qty));

  /// Turns the hints on and returns the current problems in display order.
  List<OptionIssue> revealIssues() {
    state = state.copyWith(showIssues: true);
    return state.config?.validate() ?? const [];
  }

  void setUploadProgress(double? progress) => state = state.copyWith(uploadProgress: () => progress);
}

/// One controller per open product, disposed when the screen closes.
final productDetailsControllerProvider =
    StateNotifierProvider.autoDispose.family<ProductDetailsController, ProductDetailsState, String>((ref, productId) {
  final controller = ProductDetailsController();
  ref.listen<AsyncValue<ProductModel?>>(productByIdProvider(productId), (_, next) {
    final product = next.valueOrNull;
    if (product != null) controller.attach(product);
  }, fireImmediately: true);
  return controller;
});
