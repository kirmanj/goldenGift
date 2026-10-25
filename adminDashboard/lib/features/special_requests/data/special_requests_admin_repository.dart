import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/special_request_model.dart';

import '../../../core/data/audit_log.dart';
import '../../../core/session/admin_session.dart';

/// Who may answer requests (SRS §9 Special requests). Other roles read only.
class SpecialRequestsAccess {
  SpecialRequestsAccess._();

  static bool canView(AdminRole r) => r != AdminRole.seller;
  static bool canAct(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops;
}

class SpecialRequestRules {
  SpecialRequestRules._();

  static const maxMessage = 1000;
  static const minQuote = 1000;
  static const maxQuote = 100000000;
  static const maxQuoteNote = 500;
  static const maxReason = 500;
}

/// Inbox filters (SRS §9: statuses; type gift / support; awaiting a reply).
class SpecialRequestFilters {
  const SpecialRequestFilters({this.status, this.type, this.awaitingReply = false});
  final SpecialRequestStatus? status;
  final SpecialRequestType? type;

  /// Last message is the customer's (`lastMessageBy == customer`).
  final bool awaitingReply;

  SpecialRequestFilters copyWith({
    SpecialRequestStatus? status,
    bool clearStatus = false,
    SpecialRequestType? type,
    bool clearType = false,
    bool? awaitingReply,
  }) =>
      SpecialRequestFilters(
        status: clearStatus ? null : (status ?? this.status),
        type: clearType ? null : (type ?? this.type),
        awaitingReply: awaitingReply ?? this.awaitingReply,
      );

  @override
  bool operator ==(Object other) =>
      other is SpecialRequestFilters && other.status == status && other.type == type && other.awaitingReply == awaitingReply;

  @override
  int get hashCode => Object.hash(status, type, awaitingReply);
}

String specialRequestStatusLabel(SpecialRequestStatus s) => switch (s) {
      SpecialRequestStatus.submitted => 'Submitted',
      SpecialRequestStatus.inReview => 'In review',
      SpecialRequestStatus.quoted => 'Quoted',
      SpecialRequestStatus.accepted => 'Accepted',
      SpecialRequestStatus.rejected => 'Rejected',
      SpecialRequestStatus.completed => 'Completed',
    };

String specialRequestTypeLabel(SpecialRequestType t) => switch (t) {
      SpecialRequestType.gift => 'Gift idea',
      SpecialRequestType.support => 'Support',
    };

/// Status moves staff make (SRS §5.17): submitted → inReview | rejected;
/// inReview → quoted (Send quote) | rejected; quoted → inReview (withdraw the
/// quote) | rejected; accepted → completed. Accepting is the customer's
/// (`acceptQuote` creates the order). Support messages are never quoted;
/// they are closed with inReview → completed instead.
List<SpecialRequestStatus> requestTransitions(SpecialRequestModel r) => switch (r.status) {
      SpecialRequestStatus.submitted => const [SpecialRequestStatus.inReview, SpecialRequestStatus.rejected],
      SpecialRequestStatus.inReview => r.type == SpecialRequestType.support
          ? const [SpecialRequestStatus.completed, SpecialRequestStatus.rejected]
          : const [SpecialRequestStatus.quoted, SpecialRequestStatus.rejected],
      SpecialRequestStatus.quoted => const [SpecialRequestStatus.inReview, SpecialRequestStatus.rejected],
      SpecialRequestStatus.accepted => const [SpecialRequestStatus.completed],
      SpecialRequestStatus.rejected || SpecialRequestStatus.completed => const [],
    };

bool canSendQuote(SpecialRequestModel r) => requestTransitions(r).contains(SpecialRequestStatus.quoted);

String? validateQuote(int? amount, String note) {
  if (amount == null || amount <= 0) return 'Enter the quoted amount.';
  if (amount < SpecialRequestRules.minQuote) {
    return 'A quote is at least ${CurrencyFormatter.format(SpecialRequestRules.minQuote)}.';
  }
  if (amount > SpecialRequestRules.maxQuote) {
    return 'A quote is at most ${CurrencyFormatter.format(SpecialRequestRules.maxQuote)}.';
  }
  if (note.trim().length > SpecialRequestRules.maxQuoteNote) {
    return 'Keep the note under ${SpecialRequestRules.maxQuoteNote} characters.';
  }
  return null;
}

/// What the customer reads in the thread when a quote is sent.
String quoteMessage(int amount, String note) =>
    note.trim().isEmpty ? 'Quote: ${CurrencyFormatter.format(amount)}' : 'Quote: ${CurrencyFormatter.format(amount)} — ${note.trim()}';

const quoteWithdrawnMessage = 'The quote was withdrawn — we will send you an updated one.';

class SpecialRequestException implements Exception {
  const SpecialRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Inbox + thread writes (SRS §5.17, §5.24, §9). Every write is ONE batch:
/// the message / request change and its `admin_audit_log` entry.
class SpecialRequestsAdminRepository {
  SpecialRequestsAdminRepository(this._db);
  final FirebaseFirestore _db;

  static const pageSize = 50;

  /// Equality filters + `lastMessageAt` desc (indexes: status / type /
  /// lastMessageBy each with lastMessageAt; Firestore merges them).
  Query<Map<String, dynamic>> query(SpecialRequestFilters f) {
    Query<Map<String, dynamic>> q = _db.collection(FirestorePaths.specialRequests);
    if (f.status != null) q = q.where('status', isEqualTo: f.status!.name);
    if (f.type != null) q = q.where('type', isEqualTo: f.type!.name);
    if (f.awaitingReply) q = q.where('lastMessageBy', isEqualTo: 'customer');
    return q.orderBy('lastMessageAt', descending: true);
  }

  Stream<List<SpecialRequestModel>> watch(SpecialRequestFilters f, {int limit = pageSize}) => query(f)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) SpecialRequestModel.fromMap(d.id, d.data())]);

  Stream<SpecialRequestModel?> watchOne(String id) => _db
      .doc(FirestorePaths.specialRequestDoc(id))
      .snapshots()
      .map((d) => d.exists ? SpecialRequestModel.fromMap(d.id, d.data()!) : null);

  Stream<List<SpecialRequestMessage>> watchMessages(String id) => _db
      .collection(FirestorePaths.specialRequestMessages(id))
      .orderBy('at')
      .limit(500)
      .snapshots()
      .map((s) => [for (final d in s.docs) SpecialRequestMessage.fromMap(d.id, d.data())]);

  DocumentReference<Map<String, dynamic>> _doc(String id) => _db.doc(FirestorePaths.specialRequestDoc(id));

  void _addMessage(WriteBatch batch, String requestId, String adminUid, String text) =>
      batch.set(_db.collection(FirestorePaths.specialRequestMessages(requestId)).doc(), {
        'senderUid': adminUid,
        'role': 'admin',
        'text': text,
        'images': const <String>[],
        'at': FieldValue.serverTimestamp(),
      });

  static Map<String, dynamic> _lastMessageMarkers() => {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageBy': 'admin',
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static void _requireAdmin(String uid) {
    if (uid.isEmpty) throw StateError('Not signed in as an admin.');
  }

  /// Admin reply; a new request moves to In review automatically.
  Future<void> reply(SpecialRequestModel request, String text, {required String adminUid}) async {
    _requireAdmin(adminUid);
    final t = text.trim();
    if (t.isEmpty) throw const SpecialRequestException('Write a message first.');
    if (t.length > SpecialRequestRules.maxMessage) {
      throw const SpecialRequestException('Keep the message under ${SpecialRequestRules.maxMessage} characters.');
    }
    final startsReview = request.status == SpecialRequestStatus.submitted;
    final batch = _db.batch();
    _addMessage(batch, request.id, adminUid, t);
    batch.update(_doc(request.id), {
      ..._lastMessageMarkers(),
      if (startsReview) 'status': SpecialRequestStatus.inReview.name,
    });
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'specialRequest.reply',
        target: _doc(request.id).path,
        before: {'status': request.status.name},
        after: {
          'status': (startsReview ? SpecialRequestStatus.inReview : request.status).name,
          'text': t,
        });
    await batch.commit();
  }

  /// Send quote: status quoted + amount / note + a "Quote: X IQD — note" message.
  Future<void> sendQuote(SpecialRequestModel request, {required int amount, String note = '', required String adminUid}) async {
    _requireAdmin(adminUid);
    if (!canSendQuote(request)) {
      throw SpecialRequestException('A ${specialRequestStatusLabel(request.status).toLowerCase()} request cannot be quoted.');
    }
    final error = validateQuote(amount, note);
    if (error != null) throw SpecialRequestException(error);
    final n = note.trim();
    final batch = _db.batch();
    _addMessage(batch, request.id, adminUid, quoteMessage(amount, n));
    batch.update(_doc(request.id), {
      ..._lastMessageMarkers(),
      'status': SpecialRequestStatus.quoted.name,
      'quoteAmount': amount,
      'quoteNote': n.isEmpty ? null : n,
      'quotedBy': adminUid,
      'quotedAt': FieldValue.serverTimestamp(),
    });
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'specialRequest.quote',
        target: _doc(request.id).path,
        before: {'status': request.status.name, 'quoteAmount': request.quoteAmount},
        after: {'status': SpecialRequestStatus.quoted.name, 'quoteAmount': amount, 'quoteNote': n.isEmpty ? null : n});
    await batch.commit();
  }

  /// Every other move in [requestTransitions]. Rejecting needs a reason
  /// (also posted in the thread); withdrawing a quote clears it and tells
  /// the customer.
  Future<void> setStatus(SpecialRequestModel request, SpecialRequestStatus next,
      {String? reason, required String adminUid}) async {
    _requireAdmin(adminUid);
    if (next == SpecialRequestStatus.quoted) throw const SpecialRequestException('Use Send quote to quote a request.');
    if (!requestTransitions(request).contains(next)) {
      throw SpecialRequestException(
          '${specialRequestStatusLabel(request.status)} → ${specialRequestStatusLabel(next)} is not allowed.');
    }
    final r = reason?.trim() ?? '';
    final rejecting = next == SpecialRequestStatus.rejected;
    if (rejecting && r.length < 3) throw const SpecialRequestException('A reason of at least 3 characters is required.');
    if (r.length > SpecialRequestRules.maxReason) {
      throw const SpecialRequestException('Keep the reason under ${SpecialRequestRules.maxReason} characters.');
    }
    final withdrawing = request.status == SpecialRequestStatus.quoted && next == SpecialRequestStatus.inReview;
    final message = rejecting ? r : (withdrawing ? quoteWithdrawnMessage : null);
    final batch = _db.batch();
    if (message != null) _addMessage(batch, request.id, adminUid, message);
    batch.update(_doc(request.id), {
      if (message != null) ..._lastMessageMarkers() else 'updatedAt': FieldValue.serverTimestamp(),
      'status': next.name,
      if (rejecting) 'rejectReason': r,
      if (withdrawing) ...{'quoteAmount': FieldValue.delete(), 'quoteNote': FieldValue.delete()},
    });
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'specialRequest.status',
        target: _doc(request.id).path,
        before: {'status': request.status.name, if (withdrawing) 'quoteAmount': request.quoteAmount},
        after: {'status': next.name, if (r.isNotEmpty) 'reason': r});
    await batch.commit();
  }

  Future<void> assignTo(SpecialRequestModel request, {required String adminUid}) async {
    _requireAdmin(adminUid);
    final batch = _db.batch()
      ..update(_doc(request.id), {'assignedAdminUid': adminUid, 'updatedAt': FieldValue.serverTimestamp()});
    AuditLog.add(batch, _db,
        adminUid: adminUid,
        action: 'specialRequest.assign',
        target: _doc(request.id).path,
        before: {'assignedAdminUid': request.assignedAdminUid},
        after: {'assignedAdminUid': adminUid});
    await batch.commit();
  }
}

final specialRequestsAdminRepositoryProvider =
    Provider<SpecialRequestsAdminRepository>((ref) => SpecialRequestsAdminRepository(ref.watch(firestoreProvider)));

final adminSpecialRequestsProvider =
    StreamProvider.autoDispose.family<List<SpecialRequestModel>, (SpecialRequestFilters, int)>(
        (ref, args) => ref.watch(specialRequestsAdminRepositoryProvider).watch(args.$1, limit: args.$2));

final adminSpecialRequestProvider = StreamProvider.autoDispose.family<SpecialRequestModel?, String>(
    (ref, id) => ref.watch(specialRequestsAdminRepositoryProvider).watchOne(id));

final adminSpecialRequestMessagesProvider = StreamProvider.autoDispose.family<List<SpecialRequestMessage>, String>(
    (ref, id) => ref.watch(specialRequestsAdminRepositoryProvider).watchMessages(id));

/// `admins/{uid}.name` for "Assigned to" (null when unknown).
final adminNameProvider = FutureProvider.autoDispose.family<String?, String>((ref, uid) async {
  final doc = await ref.watch(firestoreProvider).doc('${FirestorePaths.admins}/$uid').get();
  return doc.data()?['name'] as String?;
});
