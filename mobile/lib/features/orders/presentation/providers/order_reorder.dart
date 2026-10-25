import 'package:uuid/uuid.dart';

import '../../../../models/cart_item_model.dart';
import '../../../../models/order_model.dart';
import '../../../cart/presentation/providers/cart_controller.dart';

/// Reorder (SRS §5.12): every line of [order] goes back into the cart as a new
/// line (new id, same personalization); the cart re-checks price and stock.
/// Also "Try again" after a failed online payment (§5.11).
Future<void> addOrderLinesToCart(CartController cart, OrderModel order) async {
  const uuid = Uuid();
  for (final item in order.items) {
    final l = item.line;
    await cart.add(CartItemModel(
      id: uuid.v4(),
      productId: l.productId,
      storeId: l.storeId,
      titleSnapshot: l.titleSnapshot,
      imageSnapshot: l.imageSnapshot,
      unitPrice: l.unitPrice,
      qty: l.qty,
      selections: l.selections,
      preparationDays: l.preparationDays,
    ));
  }
}
