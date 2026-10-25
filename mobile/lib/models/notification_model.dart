import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';

/// `notifications/{id}` (SRS §4.5, §6.13). `userId == "all"` = broadcast.
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    this.type = '',
    this.route,
    this.targetId,
    this.imageUrl,
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String userId;
  final LocalizedText title;
  final LocalizedText body;

  /// orderStatus, referralNotApplied, specialRequestReply, referralCredited,
  /// giftCardReceived, secretSantaDraw, broadcast…
  final String type;

  /// In-app route to open on tap (e.g. `/orders/abc`).
  final String? route;
  final String? targetId;
  final String? imageUrl;
  final bool isRead;
  final DateTime? createdAt;

  bool get isBroadcast => userId == 'all';

  factory NotificationModel.fromMap(String id, Map<String, dynamic> map) {
    final data = FirestoreParse.map(map['data']);
    return NotificationModel(
      id: id,
      userId: map['userId'] as String? ?? '',
      title: LocalizedText.fromMap(map, 'title'),
      body: LocalizedText.fromMap(map, 'body'),
      type: map['type'] as String? ?? '',
      route: FirestoreParse.stringOrNull(data['route']),
      targetId: FirestoreParse.stringOrNull(data['id']),
      imageUrl: FirestoreParse.stringOrNull(map['imageUrl']),
      isRead: FirestoreParse.boolean(map['isRead']),
      createdAt: FirestoreParse.date(map['createdAt']),
    );
  }
}
