import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/services/callable.dart';
import '../../../models/store_model.dart';

/// "Sell on Golden Gift" form (SRS §5.25). `submitPartnerApplication` creates
/// `stores/{id}` (status pendingApproval, ownerUid = caller) plus the private
/// `stores/{id}/private/application` doc; admins approve in the dashboard.
class PartnerApplication {
  const PartnerApplication({
    required this.storeName,
    required this.ownerName,
    required this.phone,
    required this.city,
    required this.category,
    this.instagram,
    this.samplePhotos = const [],
  });

  final String storeName;
  final String ownerName;

  /// E.164.
  final String phone;
  final String city;

  /// What they sell, free text (e.g. "Engraved wood").
  final String category;
  final String? instagram;

  /// Download URLs uploaded to `partner_applications/{uid}/` (≤ 5).
  final List<String> samplePhotos;

  static const maxPhotos = 5;

  Map<String, dynamic> toMap() => {
        'storeName': storeName.trim(),
        'ownerName': ownerName.trim(),
        'phone': phone,
        'city': city,
        'category': category.trim(),
        'instagram': (instagram?.trim().isEmpty ?? true) ? null : instagram!.trim().replaceFirst(RegExp('^@'), ''),
        'samplePhotos': samplePhotos.take(maxPhotos).toList(),
      };
}

enum PartnerFailureReason { alreadyApplied, invalid, unavailable, rateLimited, unknown }

class PartnerFailure implements Exception {
  const PartnerFailure(this.reason);
  final PartnerFailureReason reason;

  factory PartnerFailure.from(Object error) {
    if (error is PartnerFailure) return error;
    if (error is FirebaseFunctionsException) {
      return PartnerFailure(switch (error.code) {
        'already-exists' => PartnerFailureReason.alreadyApplied,
        'invalid-argument' => PartnerFailureReason.invalid,
        'resource-exhausted' => PartnerFailureReason.rateLimited,
        'not-found' || 'unimplemented' || 'internal' || 'unavailable' => PartnerFailureReason.unavailable,
        _ => PartnerFailureReason.unknown,
      });
    }
    return const PartnerFailure(PartnerFailureReason.unknown);
  }
}

class PartnerRepository {
  PartnerRepository(this._db, this._call);
  final FirebaseFirestore _db;
  final CallableInvoker _call;

  /// The store this account applied for / owns, if any.
  Stream<StoreModel?> watchMine(String uid) => _db
      .collection(FirestorePaths.stores)
      .where('ownerUid', isEqualTo: uid)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : StoreModel.fromMap(s.docs.first.id, s.docs.first.data()));

  Future<String> submit(PartnerApplication application) async {
    try {
      final data = callableMap(await _call('submitPartnerApplication', application.toMap()));
      return data['storeId'] as String? ?? '';
    } catch (e) {
      throw PartnerFailure.from(e);
    }
  }
}

final partnerRepositoryProvider =
    Provider<PartnerRepository>((ref) => PartnerRepository(ref.watch(firestoreProvider), ref.watch(callableInvokerProvider)));

final myPartnerStoreProvider = StreamProvider.autoDispose<StoreModel?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(partnerRepositoryProvider).watchMine(uid);
});
