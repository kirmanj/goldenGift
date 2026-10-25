import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/utils/firestore_parse.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/notification_model.dart';

/// A broadcast as shown in the history list (`notifications` with userId "all").
class BroadcastRecord {
  const BroadcastRecord({required this.notification, this.sentCount, this.sentBy});
  final NotificationModel notification;
  final int? sentCount;
  final String? sentBy;
}

class BroadcastResult {
  const BroadcastResult({required this.notificationId, required this.sent});
  final String notificationId;
  final int sent;
}

/// Broadcast composer data (SRS §9 Notifications, §7 `sendBroadcast`). The
/// callable writes the `notifications` doc (userId "all"), pushes to every
/// opted-in device in its language and records the audit entry — the
/// dashboard never writes broadcasts directly.
/// Calls a callable function by name and returns its `data`.
typedef CallableInvoker = Future<Object?> Function(String name, Map<String, dynamic> data);

class BroadcastRepository {
  BroadcastRepository(this._db, this._call);
  final FirebaseFirestore _db;
  final CallableInvoker _call;

  static const titleMax = 60;
  static const bodyMax = 180;

  Stream<List<BroadcastRecord>> watchHistory({int limit = 50}) => _db
      .collection(FirestorePaths.notifications)
      .where('userId', isEqualTo: 'all')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              BroadcastRecord(
                notification: NotificationModel.fromMap(d.id, d.data()),
                sentCount: d.data()['sentCount'] == null ? null : FirestoreParse.integer(d.data()['sentCount']),
                sentBy: FirestoreParse.stringOrNull(d.data()['sentBy']),
              ),
          ]);

  /// The payload sent to `sendBroadcast` (exposed for tests).
  static Map<String, dynamic> payload({
    required LocalizedText title,
    required LocalizedText body,
    String? route,
    String? imageUrl,
  }) =>
      {
        'title': {'en': title.en, 'ar': title.ar, 'ku': title.ku},
        'body': {'en': body.en, 'ar': body.ar, 'ku': body.ku},
        if (route != null && route.trim().isNotEmpty) 'route': route.trim(),
        if (imageUrl != null && imageUrl.trim().isNotEmpty) 'imageUrl': imageUrl.trim(),
      };

  Future<BroadcastResult> send({
    required LocalizedText title,
    required LocalizedText body,
    String? route,
    String? imageUrl,
  }) async {
    final res = await _call('sendBroadcast', payload(title: title, body: body, route: route, imageUrl: imageUrl));
    final data = res is Map ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
    return BroadcastResult(
      notificationId: data['notificationId'] as String? ?? '',
      sent: FirestoreParse.integer(data['sent']),
    );
  }
}

final broadcastRepositoryProvider = Provider<BroadcastRepository>((ref) => BroadcastRepository(
      ref.watch(firestoreProvider),
      (name, data) async => (await ref.read(functionsProvider).httpsCallable(name).call<Object?>(data)).data,
    ));

final broadcastHistoryProvider =
    StreamProvider.autoDispose<List<BroadcastRecord>>((ref) => ref.watch(broadcastRepositoryProvider).watchHistory());
