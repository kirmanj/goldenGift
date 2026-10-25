import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/services/callable.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/utils/app_dates.dart';
import '../../../models/special_request_model.dart';
import '../../orders/data/orders_repository.dart';
import '../../product_details/domain/product_configuration.dart';

/// Accepting a quote (SRS §5.17): `acceptQuote` creates the order
/// (`orderType = specialRequest`) for the quoted amount and links it.
class AcceptQuoteRequest {
  const AcceptQuoteRequest({
    required this.requestId,
    required this.clientRequestId,
    required this.addressId,
    required this.deliveryDate,
    this.deliverySlot,
    this.paymentMethod = PaymentMethod.cashOnDelivery,
  });

  final String requestId;
  final String clientRequestId;
  final String addressId;
  final DateTime deliveryDate;
  final String? deliverySlot;
  final PaymentMethod paymentMethod;

  Map<String, dynamic> toMap() => {
        'requestId': requestId,
        'clientRequestId': clientRequestId,
        'addressId': addressId,
        'deliveryDate': AppDates.isoDate(deliveryDate),
        'deliverySlot': deliverySlot,
        'paymentMethod': paymentMethod.name,
      };
}

/// Special requests and support messages (SRS §5.17, §5.24). The customer
/// writes the request and their own messages; admins reply and quote.
class SpecialRequestsRepository {
  SpecialRequestsRepository(this._db, this._uploads, this._call);
  final FirebaseFirestore _db;
  final ImageUploadService _uploads;
  final CallableInvoker _call;

  Stream<List<SpecialRequestModel>> watchMine(String uid) => _db
      .collection(FirestorePaths.specialRequests)
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => [for (final d in s.docs) SpecialRequestModel.fromMap(d.id, d.data())]);

  Stream<SpecialRequestModel?> watch(String id) => _db
      .doc(FirestorePaths.specialRequestDoc(id))
      .snapshots()
      .map((s) => s.exists ? SpecialRequestModel.fromMap(s.id, s.data()!) : null);

  Stream<List<SpecialRequestMessage>> watchMessages(String id) => _db
      .collection(FirestorePaths.specialRequestMessages(id))
      .orderBy('at')
      .limit(500)
      .snapshots()
      .map((s) => [for (final d in s.docs) SpecialRequestMessage.fromMap(d.id, d.data())]);

  /// Uploads the images to `special_requests/{uid}/{id}/` first, then writes
  /// the request (status submitted). Returns the new id.
  Future<String> create({
    required String uid,
    required String text,
    SpecialRequestType type = SpecialRequestType.gift,
    List<PickedPhoto> photos = const [],
    String? customerName,
    String? customerPhone,
    ValueChanged<double>? onProgress,
  }) async {
    final ref = _db.collection(FirestorePaths.specialRequests).doc();
    final images = photos.isEmpty
        ? const <String>[]
        : await _uploads.upload('${FirestorePaths.specialRequests}/$uid/${ref.id}',
            photos.take(SpecialRequestModel.maxImages).toList(),
            onProgress: onProgress);
    await ref.set({
      'userId': uid,
      'type': type.name,
      'text': text.trim(),
      'images': images,
      'status': SpecialRequestStatus.submitted.name,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageBy': 'customer',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// A customer message in the thread (+ the request's last-message marker).
  Future<void> sendMessage({required String uid, required String requestId, required String text}) async {
    final batch = _db.batch();
    batch.set(_db.collection(FirestorePaths.specialRequestMessages(requestId)).doc(), {
      'senderUid': uid,
      'role': 'customer',
      'text': text.trim(),
      'images': const <String>[],
      'at': FieldValue.serverTimestamp(),
    });
    batch.update(_db.doc(FirestorePaths.specialRequestDoc(requestId)), {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageBy': 'customer',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<PlacedOrder> acceptQuote(AcceptQuoteRequest request) async {
    try {
      final data = callableMap(await _call('acceptQuote', request.toMap()));
      return PlacedOrder(
        orderId: data['orderId'] as String? ?? '',
        orderNumber: data['orderNumber'] as String? ?? '',
        total: (data['total'] as num?)?.toInt() ?? 0,
        deliveryDate: DateTime.tryParse(data['deliveryDate'] as String? ?? ''),
      );
    } catch (e) {
      throw OrderFailure.from(e);
    }
  }
}

final specialRequestsRepositoryProvider = Provider<SpecialRequestsRepository>((ref) => SpecialRequestsRepository(
      ref.watch(firestoreProvider),
      ref.watch(imageUploadServiceProvider),
      ref.watch(callableInvokerProvider),
    ));

final mySpecialRequestsProvider = StreamProvider.autoDispose<List<SpecialRequestModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(specialRequestsRepositoryProvider).watchMine(uid);
});

final specialRequestProvider = StreamProvider.autoDispose.family<SpecialRequestModel?, String>(
    (ref, id) => ref.watch(specialRequestsRepositoryProvider).watch(id));

final specialRequestMessagesProvider = StreamProvider.autoDispose.family<List<SpecialRequestMessage>, String>(
    (ref, id) => ref.watch(specialRequestsRepositoryProvider).watchMessages(id));
