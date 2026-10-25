import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../models/notification_model.dart';

/// In-app notifications (SRS §4.5, §5.5): the user's own docs plus broadcasts
/// (`userId == "all"`). Broadcast docs are shared, so their "read" state is
/// kept on the device instead of in Firestore.
class NotificationsRepository {
  NotificationsRepository(this._db, this._prefs);
  final FirebaseFirestore _db;
  final SharedPreferences _prefs;

  static const _readBroadcastsKey = 'read_broadcasts';
  static const _hiddenBroadcastsKey = 'hidden_broadcasts';

  /// Fires when a broadcast's device-local read / hidden state changes, so
  /// [watch] re-emits (Firestore itself doesn't change in that case).
  final _localChanges = StreamController<void>.broadcast();

  /// Newest first: the list screen reads [listLimit], the Home bell
  /// [bellLimit] (SRS §8 read budget).
  static const listLimit = 100;
  static const bellLimit = 20;

  Stream<List<NotificationModel>> watch(String uid, {int limit = listLimit}) {
    final query = _db
        .collection(FirestorePaths.notifications)
        .where('userId', whereIn: [uid, 'all'])
        .orderBy('createdAt', descending: true)
        .limit(limit);
    QuerySnapshot<Map<String, dynamic>>? last;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? remote;
    StreamSubscription<void>? local;
    late final StreamController<List<NotificationModel>> out;
    out = StreamController<List<NotificationModel>>(
      onListen: () {
        remote = query.snapshots().listen((s) {
          last = s;
          out.add(_apply(s));
        }, onError: out.addError);
        local = _localChanges.stream.listen((_) {
          if (last != null) out.add(_apply(last!));
        });
      },
      onCancel: () async {
        await remote?.cancel();
        await local?.cancel();
      },
    );
    return out.stream;
  }

  List<NotificationModel> _apply(QuerySnapshot<Map<String, dynamic>> s) {
    final hidden = _prefs.getStringList(_hiddenBroadcastsKey) ?? const [];
    final read = _prefs.getStringList(_readBroadcastsKey) ?? const [];
    return [
      for (final d in s.docs)
        if (!hidden.contains(d.id)) _withLocalRead(NotificationModel.fromMap(d.id, d.data()), read),
    ];
  }

  NotificationModel _withLocalRead(NotificationModel n, List<String> read) => n.isBroadcast && read.contains(n.id)
      ? NotificationModel(
          id: n.id,
          userId: n.userId,
          title: n.title,
          body: n.body,
          type: n.type,
          route: n.route,
          targetId: n.targetId,
          imageUrl: n.imageUrl,
          isRead: true,
          createdAt: n.createdAt,
        )
      : n;

  Future<void> markRead(NotificationModel n) async {
    if (n.isRead) return;
    if (n.isBroadcast) {
      await _prefs.setStringList(_readBroadcastsKey, {...?_prefs.getStringList(_readBroadcastsKey), n.id}.toList());
      _localChanges.add(null);
      return;
    }
    // Rules allow the owner to change only `isRead` (+ updatedAt).
    await _db.doc('${FirestorePaths.notifications}/${n.id}').update({'isRead': true});
  }

  Future<void> markAllRead(List<NotificationModel> list) async {
    final batch = _db.batch();
    var writes = 0;
    final broadcastIds = <String>[];
    for (final n in list.where((n) => !n.isRead)) {
      if (n.isBroadcast) {
        broadcastIds.add(n.id);
      } else if (writes < 450) {
        batch.update(_db.doc('${FirestorePaths.notifications}/${n.id}'), {'isRead': true});
        writes++;
      }
    }
    if (broadcastIds.isNotEmpty) {
      await _prefs.setStringList(
          _readBroadcastsKey, {...?_prefs.getStringList(_readBroadcastsKey), ...broadcastIds}.toList());
      _localChanges.add(null);
    }
    if (writes > 0) await batch.commit();
  }

  void dispose() => _localChanges.close();

  /// Swipe to delete: own docs are deleted; broadcasts are hidden on this device.
  Future<void> remove(NotificationModel n) async {
    if (n.isBroadcast) {
      await _prefs.setStringList(
          _hiddenBroadcastsKey, {...?_prefs.getStringList(_hiddenBroadcastsKey), n.id}.toList());
      _localChanges.add(null);
      return;
    }
    await _db.doc('${FirestorePaths.notifications}/${n.id}').delete();
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  final repo = NotificationsRepository(ref.watch(firestoreProvider), ref.watch(sharedPreferencesProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final notificationsProvider = StreamProvider<List<NotificationModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationsRepositoryProvider).watch(uid);
});

/// The newest [NotificationsRepository.bellLimit] notifications, for the
/// Home bell: opening Home doesn't pay for the whole list (SRS §8).
final latestNotificationsProvider = StreamProvider<List<NotificationModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationsRepositoryProvider).watch(uid, limit: NotificationsRepository.bellLimit);
});

/// Gold dot on the Home bell (SRS §4.5): unread among the newest ones.
final unreadNotificationsProvider = Provider<int>(
  (ref) => (ref.watch(latestNotificationsProvider).valueOrNull ?? const []).where((n) => !n.isRead).length,
);
