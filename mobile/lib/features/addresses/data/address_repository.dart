import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../models/address_model.dart';

/// `users/{uid}/addresses` (SRS §5.20). Exactly one default: setting a
/// default and saving happen in one batch.
class AddressRepository {
  AddressRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid) => _db.collection(FirestorePaths.userAddresses(uid));

  Stream<List<AddressModel>> watch(String uid) => _col(uid).snapshots().map((s) {
        final list = [for (final d in s.docs) AddressModel.fromMap(d.id, d.data())];
        list.sort((a, b) => a.isDefault == b.isDefault ? a.label.compareTo(b.label) : (a.isDefault ? -1 : 1));
        return list;
      });

  /// Creates (empty id) or updates. The first address is always the default.
  Future<AddressModel> save(String uid, AddressModel address) async {
    final existing = await _col(uid).get();
    final isFirst = existing.docs.isEmpty || (existing.docs.length == 1 && existing.docs.first.id == address.id);
    final makeDefault = address.isDefault || isFirst;
    final ref = address.id.isEmpty ? _col(uid).doc() : _col(uid).doc(address.id);
    final saved = address.copyWith(id: ref.id, isDefault: makeDefault);
    final batch = _db.batch();
    if (makeDefault) {
      for (final d in existing.docs) {
        if (d.id != ref.id && (d.data()['isDefault'] == true)) batch.update(d.reference, {'isDefault': false});
      }
    }
    batch.set(ref, saved.toMap());
    await batch.commit();
    return saved;
  }

  Future<void> setDefault(String uid, String addressId) async {
    final existing = await _col(uid).get();
    final batch = _db.batch();
    for (final d in existing.docs) {
      final shouldBe = d.id == addressId;
      if ((d.data()['isDefault'] == true) != shouldBe) batch.update(d.reference, {'isDefault': shouldBe});
    }
    await batch.commit();
  }

  /// Deleting the default promotes another address so one stays default.
  Future<void> delete(String uid, String addressId) async {
    final existing = await _col(uid).get();
    final batch = _db.batch();
    final target = existing.docs.where((d) => d.id == addressId).firstOrNull;
    if (target == null) return;
    batch.delete(target.reference);
    if (target.data()['isDefault'] == true) {
      final next = existing.docs.where((d) => d.id != addressId).firstOrNull;
      if (next != null) batch.update(next.reference, {'isDefault': true});
    }
    await batch.commit();
  }
}

final addressRepositoryProvider = Provider<AddressRepository>((ref) => AddressRepository(ref.watch(firestoreProvider)));

final addressesProvider = StreamProvider<List<AddressModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(addressRepositoryProvider).watch(uid);
});

final defaultAddressProvider = Provider<AddressModel?>((ref) {
  final list = ref.watch(addressesProvider).valueOrNull ?? const [];
  return list.where((a) => a.isDefault).firstOrNull ?? list.firstOrNull;
});
