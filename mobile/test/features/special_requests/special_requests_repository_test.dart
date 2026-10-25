import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/services/image_upload_service.dart';
import 'package:golden_gift/features/product_details/domain/product_configuration.dart';
import 'package:golden_gift/features/special_requests/data/special_requests_repository.dart';
import 'package:golden_gift/models/special_request_model.dart';

class FakeUploads implements ImageUploadService {
  final folders = <String>[];
  @override
  Future<List<String>> upload(String folder, List<PickedPhoto> photos, {ValueChanged<double>? onProgress}) async {
    folders.add(folder);
    onProgress?.call(1);
    return [for (var i = 0; i < photos.length; i++) 'https://img/$folder/${i + 1}.jpg'];
  }
}

void main() {
  final photo = PickedPhoto(Uint8List.fromList([1, 2, 3]));

  test('create uploads into the request folder, writes a submitted request, caps images at 5', () async {
    final db = FakeFirebaseFirestore();
    final uploads = FakeUploads();
    final repo = SpecialRequestsRepository(db, uploads, (_, __) async => null);
    final id = await repo.create(uid: 'u1', text: '  A wooden box with our names  ', photos: List.filled(7, photo), customerName: 'Sara');

    final doc = (await db.doc(FirestorePaths.specialRequestDoc(id)).get()).data()!;
    expect(uploads.folders.single, 'special_requests/u1/$id');
    expect(doc['text'], 'A wooden box with our names');
    expect(doc['status'], 'submitted');
    expect(doc['type'], 'gift');
    expect(doc['userId'], 'u1');
    expect((doc['images'] as List), hasLength(5));
    expect(doc['lastMessageBy'], 'customer');

    final mine = await repo.watchMine('u1').first;
    expect(mine.single.status, SpecialRequestStatus.submitted);
  });

  test('support messages (Contact Us form) need no images', () async {
    final db = FakeFirebaseFirestore();
    final uploads = FakeUploads();
    final id = await SpecialRequestsRepository(db, uploads, (_, __) async => null)
        .create(uid: 'u1', text: 'Where is my order?', type: SpecialRequestType.support);
    expect(uploads.folders, isEmpty);
    expect((await db.doc(FirestorePaths.specialRequestDoc(id)).get()).data()!['type'], 'support');
  });

  test('a customer message lands in the thread and marks the request', () async {
    final db = FakeFirebaseFirestore();
    final repo = SpecialRequestsRepository(db, FakeUploads(), (_, __) async => null);
    final id = await repo.create(uid: 'u1', text: 'Idea');
    await repo.sendMessage(uid: 'u1', requestId: id, text: ' Any update? ');
    final messages = await repo.watchMessages(id).first;
    expect(messages.single.text, 'Any update?');
    expect(messages.single.role, 'customer');
    expect(messages.single.isFromAdmin, isFalse);
  });

  test('a quote can be accepted only once and acceptQuote gets the checkout choices', () async {
    expect(
      SpecialRequestModel.fromMap('r', {'userId': 'u', 'text': 't', 'status': 'quoted', 'quoteAmount': 90000}).canAcceptQuote,
      isTrue,
    );
    expect(
      SpecialRequestModel.fromMap('r', {'userId': 'u', 'text': 't', 'status': 'quoted', 'quoteAmount': 90000, 'orderId': 'o'})
          .canAcceptQuote,
      isFalse,
    );
    final sent = <Map<String, dynamic>>[];
    final repo = SpecialRequestsRepository(FakeFirebaseFirestore(), FakeUploads(), (name, data) async {
      expect(name, 'acceptQuote');
      sent.add(data);
      return {'orderId': 'o1', 'orderNumber': 'GG-2610-00010', 'total': 93000, 'deliveryDate': '2026-10-25'};
    });
    final placed = await repo.acceptQuote(AcceptQuoteRequest(
      requestId: 'r1',
      clientRequestId: 'c1',
      addressId: 'home',
      deliveryDate: DateTime(2026, 10, 25),
      deliverySlot: 'evening',
    ));
    expect(placed.total, 93000);
    expect(sent.single, {
      'requestId': 'r1',
      'clientRequestId': 'c1',
      'addressId': 'home',
      'deliveryDate': '2026-10-25',
      'deliverySlot': 'evening',
      'paymentMethod': PaymentMethod.cashOnDelivery.name,
    });
  });
}
