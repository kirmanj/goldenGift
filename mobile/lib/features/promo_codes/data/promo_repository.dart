import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/utils/promo_rules.dart';
import '../../../models/promo_code_model.dart';
import '../../cart/presentation/providers/cart_lines.dart';
import '../../profile/presentation/providers/profile_providers.dart';

/// Promo codes (SRS §5.23, §6.9). The app previews a code with the shared
/// [PromoRules]; `placeOrder` re-checks every rule and owns the counters.
class PromoRepository {
  PromoRepository(this._db);
  final FirebaseFirestore _db;

  /// Listed codes: public, active, not expired; soonest expiry first.
  Stream<List<PromoCodeModel>> watchPublic({DateTime Function() now = DateTime.now}) => _db
          .collection(FirestorePaths.promoCodes)
          .where('isPublic', isEqualTo: true)
          .where('isActive', isEqualTo: true)
          .limit(100)
          .snapshots()
          .map((s) {
        final at = now();
        final list = [
          for (final d in s.docs) PromoCodeModel.fromMap(d.id, d.data()),
        ].where((p) => p.expiresAt == null || at.isBefore(p.expiresAt!)).toList();
        list.sort((a, b) => (a.expiresAt ?? DateTime(9999)).compareTo(b.expiresAt ?? DateTime(9999)));
        return list;
      });

  /// A code typed in the cart (private codes too). Null when it doesn't exist.
  Future<PromoCodeModel?> find(String code) async {
    final id = PromoCodeModel.normalize(code);
    if (id.isEmpty || id.contains('/')) return null;
    try {
      final snap = await _db.doc('${FirestorePaths.promoCodes}/$id').get();
      return snap.exists ? PromoCodeModel.fromMap(snap.id, snap.data()!) : null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'not-found') return null;
      rethrow;
    }
  }

  /// How many times [uid] has used [code] (`promo_codes/{code}/usages/{uid}`).
  Future<int> usageCount(String code, String uid) async {
    final snap = await _db.doc(FirestorePaths.promoUsageDoc(PromoCodeModel.normalize(code), uid)).get();
    return snap.exists ? (snap.data()?['count'] as num?)?.toInt() ?? 0 : 0;
  }
}

final promoRepositoryProvider = Provider<PromoRepository>((ref) => PromoRepository(ref.watch(firestoreProvider)));

final publicPromosProvider =
    StreamProvider.autoDispose<List<PromoCodeModel>>((ref) => ref.watch(promoRepositoryProvider).watchPublic());

/// The code applied in the cart, kept across restarts in `cart_promo` (cleared
/// with the other `cart_*` keys on logout).
class AppliedPromoController extends StateNotifier<String?> {
  AppliedPromoController(super.initial, this._write);
  static const prefsKey = 'cart_promo';

  final Future<void> Function(String? code) _write;

  void apply(String code) {
    state = PromoCodeModel.normalize(code);
    _write(state);
  }

  void remove() {
    state = null;
    _write(null);
  }
}

final appliedPromoProvider = StateNotifierProvider<AppliedPromoController, String?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AppliedPromoController(
    prefs.getString(AppliedPromoController.prefsKey),
    (code) => code == null
        ? prefs.remove(AppliedPromoController.prefsKey)
        : prefs.setString(AppliedPromoController.prefsKey, code),
  );
});

/// The applied code checked against the current cart; null when none is applied.
final promoEvaluationProvider = FutureProvider.autoDispose<(PromoCodeModel?, PromoEvaluation)?>((ref) async {
  final code = ref.watch(appliedPromoProvider);
  if (code == null) return null;
  final summary = ref.watch(cartSummaryProvider).valueOrNull;
  final products = ref.watch(cartProductsProvider).valueOrNull ?? const {};
  if (summary == null) return null;
  final repo = ref.watch(promoRepositoryProvider);
  final promo = await repo.find(code);
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  final usage = promo == null || uid == null ? 0 : await repo.usageCount(code, uid);
  final orders = ref.watch(currentUserProfileProvider).valueOrNull?.totalOrders ?? 0;
  final lines = [
    for (final l in summary.lines.where((l) => l.counts))
      PromoLine(
        productId: l.item.productId,
        storeId: l.item.storeId,
        categoryIds: products[l.item.productId]?.categoryIds ?? const [],
        lineTotal: l.effectiveLineTotal,
      ),
  ];
  return (
    promo,
    PromoRules.evaluate(promo, lines: lines, now: DateTime.now(), userUsageCount: usage, userOrderCount: orders),
  );
});
