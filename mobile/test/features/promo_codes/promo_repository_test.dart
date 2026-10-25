import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/features/promo_codes/data/promo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> promo(FakeFirebaseFirestore db, String code,
          {bool isPublic = true, bool isActive = true, DateTime? expiresAt}) =>
      db.doc('${FirestorePaths.promoCodes}/$code').set({
        'code': code,
        'title': 'T $code',
        'type': 'percent',
        'value': 10,
        'isPublic': isPublic,
        'isActive': isActive,
        'perUserLimit': 1,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      });

  test('lists public active unexpired codes, soonest expiry first', () async {
    final db = FakeFirebaseFirestore();
    final now = DateTime(2026, 10, 21);
    await promo(db, 'LATER', expiresAt: DateTime(2026, 12, 1));
    await promo(db, 'SOON', expiresAt: DateTime(2026, 10, 25));
    await promo(db, 'FOREVER');
    await promo(db, 'OLD', expiresAt: DateTime(2026, 10, 1));
    await promo(db, 'HIDDEN', isPublic: false);
    await promo(db, 'OFF', isActive: false);

    final list = await PromoRepository(db).watchPublic(now: () => now).first;
    expect(list.map((p) => p.code), ['SOON', 'LATER', 'FOREVER']);
  });

  test('find works for private codes, case-insensitively; unknown → null', () async {
    final db = FakeFirebaseFirestore();
    await promo(db, 'VIP20', isPublic: false);
    final repo = PromoRepository(db);
    expect((await repo.find(' vip20 '))?.code, 'VIP20');
    expect(await repo.find('NOPE'), isNull);
    expect(await repo.find(''), isNull);
    expect(await repo.find('A/B'), isNull);
  });

  test('usage count per customer', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('${FirestorePaths.promoCodes}/VIP20/usages/u1').set({'count': 2});
    final repo = PromoRepository(db);
    expect(await repo.usageCount('vip20', 'u1'), 2);
    expect(await repo.usageCount('vip20', 'u2'), 0);
  });

  test('the applied code is normalized and survives a restart in cart_promo', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Future<void> write(String? c) =>
        c == null ? prefs.remove(AppliedPromoController.prefsKey) : prefs.setString(AppliedPromoController.prefsKey, c);
    final c = AppliedPromoController(prefs.getString(AppliedPromoController.prefsKey), write);
    c.apply(' gold10 ');
    expect(c.state, 'GOLD10');
    await Future<void>.delayed(Duration.zero);
    expect(AppliedPromoController(prefs.getString(AppliedPromoController.prefsKey), write).state, 'GOLD10');
    c.remove();
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString(AppliedPromoController.prefsKey), isNull);
  });
}
