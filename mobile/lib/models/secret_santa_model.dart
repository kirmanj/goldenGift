import '../core/utils/firestore_parse.dart';

enum SecretSantaType { family, friends, work }

enum SecretSantaStatus { open, drawn, closed }

/// `secret_santa_groups/{id}` (SRS §5.16, §6.14). Members join with the
/// invite code; only the organiser can draw (`drawSecretSanta`).
class SecretSantaGroup {
  const SecretSantaGroup({
    required this.id,
    required this.name,
    this.type = SecretSantaType.friends,
    this.budget = 0,
    this.exchangeDate,
    required this.organiserUid,
    this.status = SecretSantaStatus.open,
    required this.inviteCode,
    this.memberUids = const [],
    this.drawnAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final SecretSantaType type;

  /// IQD per gift (0 = no budget) — "Shop for them" filters by it.
  final int budget;
  final DateTime? exchangeDate;
  final String organiserUid;
  final SecretSantaStatus status;

  /// 8 characters, used in the join link.
  final String inviteCode;

  /// Denormalized for `array-contains` "my groups" queries and rules.
  final List<String> memberUids;
  final DateTime? drawnAt;
  final DateTime? createdAt;

  static const minMembers = 3;
  static const maxMembers = 50;

  bool isOrganiser(String uid) => organiserUid == uid;
  bool get canDraw => status == SecretSantaStatus.open && memberUids.length >= minMembers;

  /// The public join link (SRS §5.16).
  String get joinLink => 'https://goldengift.app/s/$inviteCode';

  factory SecretSantaGroup.fromMap(String id, Map<String, dynamic> map) => SecretSantaGroup(
        id: id,
        name: map['name'] as String? ?? '',
        type: FirestoreParse.enumValue(SecretSantaType.values, map['type'], SecretSantaType.friends),
        budget: FirestoreParse.integer(map['budget']),
        exchangeDate: FirestoreParse.date(map['exchangeDate']),
        organiserUid: map['organiserUid'] as String? ?? '',
        status: FirestoreParse.enumValue(SecretSantaStatus.values, map['status'], SecretSantaStatus.open),
        inviteCode: map['inviteCode'] as String? ?? '',
        memberUids: FirestoreParse.stringList(map['memberUids']),
        drawnAt: FirestoreParse.date(map['drawnAt']),
        createdAt: FirestoreParse.date(map['createdAt']),
      );
}

/// `secret_santa_groups/{id}/members/{uid}` — visible to every member.
/// Assignments are NOT stored here (Firestore can't hide single fields):
/// see [SecretSantaAssignment].
class SecretSantaMember {
  const SecretSantaMember({
    required this.uid,
    required this.name,
    this.phone,
    this.joinedAt,
    this.wishlistNote,
    this.exclusions = const [],
  });

  final String uid;
  final String name;
  final String? phone;
  final DateTime? joinedAt;

  /// What this member would like (shown to whoever draws them).
  final String? wishlistNote;

  /// Members this person must not be assigned (organiser-set, optional).
  final List<String> exclusions;

  static const maxWishlistNote = 300;

  factory SecretSantaMember.fromMap(String uid, Map<String, dynamic> map) => SecretSantaMember(
        uid: uid,
        name: map['name'] as String? ?? '',
        phone: FirestoreParse.stringOrNull(map['phone']),
        joinedAt: FirestoreParse.date(map['joinedAt']),
        wishlistNote: FirestoreParse.stringOrNull(map['wishlistNote']),
        exclusions: FirestoreParse.stringList(map['exclusions']),
      );
}

/// `secret_santa_groups/{id}/assignments/{giverUid}` — written only by
/// `drawSecretSanta`, readable only by that giver (and admins), so each
/// member sees just their own assignee (SRS §5.16).
class SecretSantaAssignment {
  const SecretSantaAssignment({
    required this.giverUid,
    required this.assigneeUid,
    required this.assigneeName,
    this.assigneeWishlistNote,
    this.drawnAt,
  });

  final String giverUid;
  final String assigneeUid;
  final String assigneeName;
  final String? assigneeWishlistNote;
  final DateTime? drawnAt;

  factory SecretSantaAssignment.fromMap(String giverUid, Map<String, dynamic> map) => SecretSantaAssignment(
        giverUid: giverUid,
        assigneeUid: map['assigneeUid'] as String? ?? '',
        assigneeName: map['assigneeName'] as String? ?? '',
        assigneeWishlistNote: FirestoreParse.stringOrNull(map['assigneeWishlistNote']),
        drawnAt: FirestoreParse.date(map['drawnAt']),
      );
}
