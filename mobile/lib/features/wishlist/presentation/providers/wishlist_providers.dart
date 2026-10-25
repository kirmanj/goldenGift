import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../data/wishlist_repository.dart';
import '../widgets/wishlist_list_sheets.dart';

/// The signed-in customer's saved gifts, newest first (empty for guests).
final wishlistItemsProvider = StreamProvider<List<WishlistItem>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(wishlistRepositoryProvider).watch(uid);
});

/// Product ids for the hearts on every product card.
final wishlistIdsProvider = Provider<Set<String>>((ref) =>
    {for (final i in ref.watch(wishlistItemsProvider).valueOrNull ?? const <WishlistItem>[]) i.productId});

/// The customer's lists: the default list first, then the named ones
/// (SRS §5.15, Phase 9). Guests (and a missing doc) get the default only.
final wishlistListsProvider = StreamProvider<List<WishlistList>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const [WishlistList.defaultList]);
  return ref.watch(wishlistRepositoryProvider).watchLists(uid);
});

/// The lists, the default-only list until they load.
final wishlistListsOrDefaultProvider = Provider<List<WishlistList>>(
    (ref) => ref.watch(wishlistListsProvider).valueOrNull ?? const [WishlistList.defaultList]);

/// productId → listId for every saved gift.
final wishlistListOfProvider = Provider<Map<String, String>>((ref) => {
      for (final i in ref.watch(wishlistItemsProvider).valueOrNull ?? const <WishlistItem>[]) i.productId: i.listId,
    });

/// The list's name as the customer sees it (the default list is translated).
String wishlistListName(AppLocalizations l10n, WishlistList list) =>
    list.isDefault || list.name.trim().isEmpty ? l10n.wishlistDefaultList : list.name;

void _logAddToWishlist(WidgetRef ref, ProductModel product) =>
    unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.addToWishlist, {
      'currency': 'IQD',
      'value': product.price,
      'items': [
        {'item_id': product.id, 'price': product.price},
      ],
    }));

/// Heart tap anywhere (SRS §5.8, §5.9, §5.15). Guests get "Sign in to continue"
/// (AUTH-5). Saves to the default list or removes the gift from whichever
/// list holds it. Returns the new state, or null when nothing changed.
Future<bool?> toggleWishlist(BuildContext context, WidgetRef ref, ProductModel product) async {
  if (!await requireSignIn(context, ref)) return null;
  final uid = ref.read(authStateProvider).valueOrNull?.uid;
  if (uid == null) return null;
  final repo = ref.read(wishlistRepositoryProvider);
  final saved = ref.read(wishlistIdsProvider).contains(product.id);
  try {
    if (saved) {
      await repo.remove(uid, product.id);
      return false;
    }
    await repo.add(uid, product);
    _logAddToWishlist(ref, product);
    return true;
  } catch (_) {
    return null;
  }
}

/// "Save to…" (long-press on a heart, SRS §5.15 Phase 9): pick a list — or
/// create one — and save [product] there (moving it if it was saved
/// elsewhere). Returns the chosen list, or null when nothing changed.
Future<WishlistList?> saveToWishlistList(BuildContext context, WidgetRef ref, ProductModel product) async {
  if (!await requireSignIn(context, ref)) return null;
  if (!context.mounted) return null;
  final uid = ref.read(authStateProvider).valueOrNull?.uid;
  if (uid == null) return null;
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final current = ref.read(wishlistListOfProvider)[product.id];
  final list = await showWishlistListPicker(context, title: l10n.wishlistSaveTo, selectedId: current);
  if (list == null || list.id == current) return null;
  final repo = ref.read(wishlistRepositoryProvider);
  try {
    if (current == null) {
      await repo.add(uid, product, listId: list.id);
      _logAddToWishlist(ref, product);
    } else {
      await repo.moveItem(uid, product.id, list.id);
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.wishlistSavedTo(wishlistListName(l10n, list)))));
    return list;
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
    return null;
  }
}
