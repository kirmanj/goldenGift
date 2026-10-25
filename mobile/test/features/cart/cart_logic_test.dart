import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/cart/data/cart_stores.dart';
import 'package:golden_gift/features/cart/presentation/providers/cart_controller.dart';
import 'package:golden_gift/features/cart/presentation/providers/cart_lines.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/store_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

CartItemModel _item(String id, {String product = 'frame', String store = 's1', String color = 'walnut', int qty = 1, int unit = 40000}) =>
    CartItemModel(
      id: id,
      productId: product,
      storeId: store,
      titleSnapshot: LocalizedText(product),
      unitPrice: unit,
      qty: qty,
      selections: [
        CartSelection(
          groupId: 'color',
          type: OptionType.imageVariant,
          label: const LocalizedText('Frame Color'),
          valueId: color,
          valueLabel: LocalizedText(color),
          priceDelta: color == 'walnut' ? 5000 : 0,
        ),
      ],
      preparationDays: 2,
    );

ProductModel _product({String id = 'frame', int price = 35000, bool active = true, int? stock, int? colorStock}) => ProductModel(
      id: id,
      title: LocalizedText(id),
      storeId: 's1',
      price: price,
      isActive: active,
      stock: stock,
      optionGroups: [
        OptionGroup(id: 'color', type: OptionType.imageVariant, label: const LocalizedText('Frame Color'), values: [
          OptionValue(id: 'walnut', label: const LocalizedText('Walnut'), priceDelta: 5000, stock: colorStock),
          const OptionValue(id: 'black', label: LocalizedText('Black')),
        ]),
      ],
    );

/// In-memory store standing in for Firestore in controller tests.
class _MemoryStore implements CartStore {
  final items = <String, CartItemModel>{};
  final _changes = StreamController<List<CartItemModel>>.broadcast();
  List<CartItemModel> get _list => items.values.toList();

  @override
  Stream<List<CartItemModel>> watch() async* {
    yield _list;
    yield* _changes.stream;
  }

  @override
  Future<List<CartItemModel>> read() async => _list;

  @override
  Future<void> upsert(CartItemModel item) async {
    items[item.id] = item;
    _changes.add(_list);
  }

  @override
  Future<void> remove(String itemId) async {
    items.remove(itemId);
    _changes.add(_list);
  }

  @override
  Future<void> clear() async {
    items.clear();
    _changes.add(_list);
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  group('LocalCartStore (guests)', () {
    test('persists lines across restarts under a cart_ key, so logout clears it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await LocalCartStore(prefs).upsert(_item('a'));
      await LocalCartStore(prefs).upsert(_item('b', color: 'black'));
      final restored = await LocalCartStore(prefs).read();
      expect(restored.map((i) => i.id), ['a', 'b']);
      expect(restored.first.selections.single.valueLabel!.en, 'walnut');
      expect(restored.first.addedAt, isNotNull);
      expect(LocalCartStore.key.startsWith('cart_'), isTrue);
    });

    test('a corrupt local cart reads as empty instead of crashing', () async {
      SharedPreferences.setMockInitialValues({LocalCartStore.key: '{not json'});
      expect(await LocalCartStore(await SharedPreferences.getInstance()).read(), isEmpty);
    });
  });

  group('CartController', () {
    late _MemoryStore local;
    late _MemoryStore remote;
    late CartController cart;

    setUp(() {
      local = _MemoryStore();
      remote = _MemoryStore();
      cart = CartController(remoteStore: (_) => remote, localStore: local);
    });
    tearDown(() => cart.dispose());

    test('identical configuration increments quantity; a different one is a new line', () async {
      await cart.onAuthChanged(null);
      await _settle();
      await cart.add(_item('a'));
      await _settle();
      await cart.add(_item('b', qty: 2));
      await _settle();
      await cart.add(_item('c', color: 'black'));
      await _settle();
      expect(local.items.length, 2);
      expect(local.items['a']!.qty, 3);
      expect(cart.state.count, 4);
    });

    test("a guest's cart moves into the account on sign-in, merging identical lines (SRS §2.1)", () async {
      await cart.onAuthChanged(null);
      await cart.add(_item('g1', qty: 2));
      await cart.add(_item('g2', color: 'black'));
      remote.items['r1'] = _item('r1');
      await cart.onAuthChanged('u1');
      await _settle();
      expect(local.items, isEmpty);
      expect(remote.items.keys.toSet(), {'r1', 'g2'});
      expect(remote.items['r1']!.qty, 3);
      expect(cart.state.items.length, 2);
    });

    test('quantity is clamped to 1…99 and lines can be removed', () async {
      await cart.onAuthChanged('u1');
      await cart.add(_item('a'));
      await _settle();
      await cart.setQty('a', 150);
      await _settle();
      expect(remote.items['a']!.qty, CartController.maxQty);
      await cart.setQty('a', 0);
      await _settle();
      expect(remote.items['a']!.qty, 1);
      await cart.remove('a');
      await _settle();
      expect(cart.state.items, isEmpty);
    });
  });

  group('cart lines (SRS §5.10)', () {
    test('available line at the snapshot price', () {
      final line = resolveLine(_item('a'), _product());
      expect(line.status, CartLineStatus.ok);
      expect(line.effectiveLineTotal, 40000);
    });

    test('gone, inactive, out of stock, removed or sold-out option, suspended store → unavailable', () {
      expect(resolveLine(_item('a'), null).status, CartLineStatus.unavailable);
      expect(resolveLine(_item('a'), _product(active: false)).status, CartLineStatus.unavailable);
      expect(resolveLine(_item('a'), _product(stock: 0)).status, CartLineStatus.unavailable);
      expect(resolveLine(_item('a', qty: 5), _product(stock: 2)).status, CartLineStatus.unavailable);
      expect(resolveLine(_item('a', color: 'pink'), _product()).status, CartLineStatus.unavailable);
      expect(resolveLine(_item('a'), _product(colorStock: 0)).status, CartLineStatus.unavailable);
      const suspended = StoreModel(id: 's1', name: LocalizedText('S'), status: StoreStatus.suspended);
      expect(resolveLine(_item('a'), _product(), store: suspended).status, CartLineStatus.unavailable);
    });

    test('a price change is flagged and the new price is used', () {
      final line = resolveLine(_item('a', qty: 2), _product(price: 30000));
      expect(line.status, CartLineStatus.priceChanged);
      expect(line.currentUnitPrice, 35000);
      expect(line.effectiveLineTotal, 70000);
    });

    test('totals exclude unavailable lines; lines group by store', () {
      final summary = summarize(
        [_item('a', qty: 2), _item('b', product: 'gone'), _item('c', product: 'mug', store: 's2', color: 'black', unit: 12000)],
        {'frame': _product(), 'mug': _product(id: 'mug', price: 12000)},
      );
      expect(summary.subtotal, 80000 + 12000);
      expect(summary.orderableCount, 3);
      expect(summary.hasUnavailable, isTrue);
      expect(summary.canCheckout, isTrue);
      expect(summary.groups.map((g) => g.storeId), ['s1', 's2']);
      expect(summary.maxPreparationDays, 2);
    });
  });

  test('FirestoreCartStore writes carts/{uid}/items and reads them back', () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreCartStore(db, 'u1');
    await store.upsert(_item('a', qty: 2));
    final items = await store.read();
    expect(items.single.qty, 2);
    expect(items.single.toMap()['lineTotal'], 80000);
    final raw = await db.doc('carts/u1/items/a').get();
    expect(raw.data()!['addedAt'], isNotNull);
    await store.clear();
    expect(await store.read(), isEmpty);
  });
}
