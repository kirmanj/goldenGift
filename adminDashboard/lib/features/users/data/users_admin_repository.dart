import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/core/utils/firestore_parse.dart';
import 'package:golden_gift/models/address_model.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/referral_model.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:golden_gift/models/wallet_model.dart';

import '../../../core/session/admin_session.dart';
import '../../notifications/data/broadcast_repository.dart' show CallableInvoker;
import 'user_search.dart';

/// Who may do what in the Users module (SRS §9). Content editors and sellers
/// never open it; finance adjusts wallets but doesn't block; ops blocks but
/// doesn't touch money.
class UsersAccess {
  UsersAccess._();

  static bool canView(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops || r == AdminRole.finance;
  static bool canBlock(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops;
  static bool canAdjustWallet(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.finance;
}

/// `users/{uid}` plus the fields the shared model doesn't carry.
class AdminUserRecord {
  const AdminUserRecord({required this.user, this.deletedAt, this.updatedAt});
  final UserModel user;
  final DateTime? deletedAt;
  final DateTime? updatedAt;

  factory AdminUserRecord.fromMap(String uid, Map<String, dynamic> map) => AdminUserRecord(
        user: UserModel.fromMap(uid, map),
        deletedAt: FirestoreParse.date(map['deletedAt']),
        updatedAt: FirestoreParse.date(map['updatedAt']),
      );
}

/// One wallet change for the `adjustWallet` callable (roles super | finance).
class WalletAdjustment {
  const WalletAdjustment({required this.uid, required this.bucket, required this.amount, required this.reason, this.requestId});
  final String uid;
  final WalletBucket bucket;

  /// Signed whole IQD: + credit, − debit.
  final int amount;
  final String reason;

  /// Idempotency key: a retried submit of the same adjustment (e.g. after a
  /// lost response) is applied once by the function.
  final String? requestId;

  static const maxAmount = 10000000;
  static const reasonMin = 3;
  static const reasonMax = 300;

  Map<String, dynamic> toPayload() => {
        'uid': uid,
        'bucket': bucket.name,
        'amount': amount,
        'reason': reason.trim(),
        if (requestId != null) 'requestId': requestId,
      };

  /// The bucket's value after this adjustment.
  int resultFor(WalletModel wallet) => (bucket == WalletBucket.balance ? wallet.balance : wallet.credits) + amount;

  /// Client-side mirror of the function's checks (it re-checks atomically).
  List<String> validate(WalletModel current) {
    final errors = <String>[];
    if (amount == 0) errors.add('Enter an amount other than 0.');
    if (amount.abs() > maxAmount) errors.add('At most ${CurrencyFormatter.format(maxAmount)} per adjustment.');
    final r = reason.trim();
    if (r.length < reasonMin) errors.add('A reason of at least $reasonMin characters is required.');
    if (r.length > reasonMax) errors.add('Keep the reason under $reasonMax characters.');
    final result = resultFor(current);
    if (result < 0) {
      errors.add('This would take the ${bucketLabel(bucket).toLowerCase()} below zero '
          '(${CurrencyFormatter.format(result)}).');
    }
    return errors;
  }
}

String bucketLabel(WalletBucket b) => switch (b) {
      WalletBucket.balance => 'Balance',
      WalletBucket.credits => 'Credits',
    };

class WalletAdjustResult {
  const WalletAdjustResult({required this.balance, required this.credits, this.txnId});
  final int balance;
  final int credits;
  final String? txnId;
}

class WalletAdjustmentInvalid implements Exception {
  const WalletAdjustmentInvalid(this.errors);
  final List<String> errors;
  @override
  String toString() => errors.join('\n');
}

/// Users module data (SRS §9 Users, §6.1, §6.11). Reads go straight to
/// Firestore; the two mutations are callables that also write the audit entry
/// (the dashboard never writes `wallets` or `isBlocked` itself — §6.11, §6.17).
class UsersAdminRepository {
  UsersAdminRepository(this._db, this._call);
  final FirebaseFirestore _db;
  final CallableInvoker _call;

  static const pageSize = 50;
  static const txnLimit = 50;
  static const orderLimit = 50;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection(FirestorePaths.users);

  /// Newest users, or the users matching [q]. Indexes: single-field only.
  Query<Map<String, dynamic>> query(UserSearchQuery q) => switch (q.mode) {
        UserSearchMode.recent => _users.orderBy('createdAt', descending: true),
        UserSearchMode.phone => _users.where('phone', whereIn: q.phoneValues),
        UserSearchMode.email => _users.where('email', isEqualTo: q.text),
        UserSearchMode.name => _users.orderBy('name').startAt([q.text]).endAt(['${q.text}']),
      };

  Stream<List<UserModel>> watchList(UserSearchQuery q, {int limit = pageSize}) => query(q)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) UserModel.fromMap(d.id, d.data())]);

  Stream<AdminUserRecord?> watchUser(String uid) => _db
      .doc(FirestorePaths.userDoc(uid))
      .snapshots()
      .map((d) => d.exists ? AdminUserRecord.fromMap(d.id, d.data()!) : null);

  Future<UserModel?> getUser(String uid) async {
    if (uid.isEmpty || uid.contains('/')) return null;
    final d = await _db.doc(FirestorePaths.userDoc(uid)).get();
    return d.exists ? UserModel.fromMap(d.id, d.data()!) : null;
  }

  /// Null until `onUserCreate` has created the wallet.
  Stream<WalletModel?> watchWallet(String uid) =>
      _db.doc(FirestorePaths.walletDoc(uid)).snapshots().map((d) => d.exists ? WalletModel.fromMap(d.data()!) : null);

  Stream<List<WalletTxn>> watchTransactions(String uid, {int limit = txnLimit}) => _db
      .collection(FirestorePaths.walletTxns(uid))
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) WalletTxn.fromMap(d.id, d.data())]);

  /// Index: orders (userId ASC, createdAt DESC) — already in firestore.indexes.json.
  Stream<List<OrderModel>> watchOrders(String uid, {int limit = orderLimit}) => _db
      .collection(FirestorePaths.orders)
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) OrderModel.fromMap(d.id, d.data())]);

  Stream<List<AddressModel>> watchAddresses(String uid) => _db
      .collection(FirestorePaths.userAddresses(uid))
      .snapshots()
      .map((s) => [for (final d in s.docs) AddressModel.fromMap(d.id, d.data())]
        ..sort((a, b) => a.isDefault == b.isDefault ? a.label.compareTo(b.label) : (a.isDefault ? -1 : 1)));

  /// Referrals the user made, newest first (sorted here — same query as the
  /// app's Invite & Earn, so no composite index).
  Stream<List<ReferralModel>> watchReferralsMade(String uid) => _db
      .collection(FirestorePaths.referrals)
      .where('referrerUid', isEqualTo: uid)
      .limit(200)
      .snapshots()
      .map((s) => [for (final d in s.docs) ReferralModel.fromMap(d.id, d.data())]
        ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0))));

  /// The `admins/{uid}.name` of whoever made an adjustment.
  Future<String?> adminName(String uid) async {
    if (uid.isEmpty || uid.contains('/')) return null;
    final d = await _db.doc('${FirestorePaths.admins}/$uid').get();
    return FirestoreParse.stringOrNull(d.data()?['name']);
  }

  /// `adjustWallet` — the function moves the money, writes the
  /// `adminAdjustment` transaction (with balanceAfter / creditsAfter) and the
  /// audit entry atomically. [current] is only for the client-side checks.
  Future<WalletAdjustResult> adjustWallet(WalletAdjustment a, {required WalletModel current}) async {
    final errors = a.validate(current);
    if (errors.isNotEmpty) throw WalletAdjustmentInvalid(errors);
    final res = await _call('adjustWallet', a.toPayload());
    final data = res is Map ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
    return WalletAdjustResult(
      balance: FirestoreParse.integer(data['balance'], a.bucket == WalletBucket.balance ? a.resultFor(current) : current.balance),
      credits: FirestoreParse.integer(data['credits'], a.bucket == WalletBucket.credits ? a.resultFor(current) : current.credits),
      txnId: FirestoreParse.stringOrNull(data['txnId']),
    );
  }

  /// The payload sent to `setUserBlocked` (exposed for tests).
  static Map<String, dynamic> blockPayload({required String uid, required bool blocked, String? reason}) => {
        'uid': uid,
        'blocked': blocked,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      };

  /// `setUserBlocked` — sets `isBlocked`, disables the Auth account, revokes
  /// sessions and audits. Returns the new state.
  Future<bool> setBlocked({required String uid, required bool blocked, String? reason}) async {
    final res = await _call('setUserBlocked', blockPayload(uid: uid, blocked: blocked, reason: reason));
    final data = res is Map ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
    return FirestoreParse.boolean(data['blocked'], blocked);
  }
}

final usersAdminRepositoryProvider = Provider<UsersAdminRepository>((ref) => UsersAdminRepository(
      ref.watch(firestoreProvider),
      (name, data) async => (await ref.read(functionsProvider).httpsCallable(name).call<Object?>(data)).data,
    ));

final adminUsersListProvider = StreamProvider.autoDispose.family<List<UserModel>, (UserSearchQuery, int)>(
    (ref, args) => ref.watch(usersAdminRepositoryProvider).watchList(args.$1, limit: args.$2));

final adminUserProvider = StreamProvider.autoDispose
    .family<AdminUserRecord?, String>((ref, uid) => ref.watch(usersAdminRepositoryProvider).watchUser(uid));

/// One-off read for names / device ids (referrer links, the Referrals page).
final adminUserLookupProvider = FutureProvider.autoDispose
    .family<UserModel?, String>((ref, uid) => ref.watch(usersAdminRepositoryProvider).getUser(uid));

final adminWalletProvider = StreamProvider.autoDispose
    .family<WalletModel?, String>((ref, uid) => ref.watch(usersAdminRepositoryProvider).watchWallet(uid));

final adminWalletTxnsProvider = StreamProvider.autoDispose
    .family<List<WalletTxn>, String>((ref, uid) => ref.watch(usersAdminRepositoryProvider).watchTransactions(uid));

final adminUserOrdersProvider = StreamProvider.autoDispose
    .family<List<OrderModel>, String>((ref, uid) => ref.watch(usersAdminRepositoryProvider).watchOrders(uid));

final adminUserAddressesProvider = StreamProvider.autoDispose
    .family<List<AddressModel>, String>((ref, uid) => ref.watch(usersAdminRepositoryProvider).watchAddresses(uid));

final adminUserReferralsProvider = StreamProvider.autoDispose
    .family<List<ReferralModel>, String>((ref, uid) => ref.watch(usersAdminRepositoryProvider).watchReferralsMade(uid));

final adminNameProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, uid) => ref.watch(usersAdminRepositoryProvider).adminName(uid));
