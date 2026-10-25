import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';

enum SpecialRequestType { gift, support }

/// `special_requests/{id}` (SRS §5.17, §5.24, §6.14). The customer creates it
/// (status submitted); admins move the status and send quotes; accepting a
/// quote goes through the `acceptQuote` function, which creates the order.
class SpecialRequestModel {
  const SpecialRequestModel({
    required this.id,
    required this.userId,
    this.type = SpecialRequestType.gift,
    required this.text,
    this.images = const [],
    this.status = SpecialRequestStatus.submitted,
    this.quoteAmount,
    this.quoteNote,
    this.orderId,
    this.assignedAdminUid,
    this.customerName,
    this.customerPhone,
    this.lastMessageAt,
    this.lastMessageBy,
    this.rejectReason,
    this.quotedBy,
    this.quotedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final SpecialRequestType type;
  final String text;

  /// Up to 5 image URLs (Storage `special_requests/{uid}/{id}/{n}.jpg`).
  final List<String> images;
  final SpecialRequestStatus status;
  final int? quoteAmount;
  final String? quoteNote;
  final String? orderId;
  final String? assignedAdminUid;

  /// Snapshot for the admin inbox (users are private).
  final String? customerName;
  final String? customerPhone;
  final DateTime? lastMessageAt;

  /// `customer` or `admin` — who wrote last (unread hints).
  final String? lastMessageBy;

  /// Set by an admin when rejecting (also posted in the thread).
  final String? rejectReason;

  /// Admin uid + time of the current quote.
  final String? quotedBy;
  final DateTime? quotedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const maxImages = 5;
  static const maxText = 1000;

  bool get canAcceptQuote => status == SpecialRequestStatus.quoted && (quoteAmount ?? 0) > 0 && orderId == null;

  factory SpecialRequestModel.fromMap(String id, Map<String, dynamic> map) => SpecialRequestModel(
        id: id,
        userId: map['userId'] as String? ?? '',
        type: FirestoreParse.enumValue(SpecialRequestType.values, map['type'], SpecialRequestType.gift),
        text: map['text'] as String? ?? '',
        images: FirestoreParse.stringList(map['images']),
        status: FirestoreParse.enumValue(SpecialRequestStatus.values, map['status'], SpecialRequestStatus.submitted),
        quoteAmount: FirestoreParse.integerOrNull(map['quoteAmount']),
        quoteNote: FirestoreParse.stringOrNull(map['quoteNote']),
        orderId: FirestoreParse.stringOrNull(map['orderId']),
        assignedAdminUid: FirestoreParse.stringOrNull(map['assignedAdminUid']),
        customerName: FirestoreParse.stringOrNull(map['customerName']),
        customerPhone: FirestoreParse.stringOrNull(map['customerPhone']),
        lastMessageAt: FirestoreParse.date(map['lastMessageAt']),
        lastMessageBy: FirestoreParse.stringOrNull(map['lastMessageBy']),
        rejectReason: FirestoreParse.stringOrNull(map['rejectReason']),
        quotedBy: FirestoreParse.stringOrNull(map['quotedBy']),
        quotedAt: FirestoreParse.date(map['quotedAt']),
        createdAt: FirestoreParse.date(map['createdAt']),
        updatedAt: FirestoreParse.date(map['updatedAt']),
      );
}

/// `special_requests/{id}/messages/{id}`.
class SpecialRequestMessage {
  const SpecialRequestMessage({
    required this.id,
    required this.senderUid,
    required this.role,
    required this.text,
    this.images = const [],
    this.at,
  });

  final String id;
  final String senderUid;

  /// `customer` or `admin`.
  final String role;
  final String text;
  final List<String> images;
  final DateTime? at;

  bool get isFromAdmin => role == 'admin';

  factory SpecialRequestMessage.fromMap(String id, Map<String, dynamic> map) => SpecialRequestMessage(
        id: id,
        senderUid: map['senderUid'] as String? ?? '',
        role: map['role'] as String? ?? 'customer',
        text: map['text'] as String? ?? '',
        images: FirestoreParse.stringList(map['images']),
        at: FirestoreParse.date(map['at']),
      );
}
