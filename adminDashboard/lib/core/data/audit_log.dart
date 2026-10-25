import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';

/// Every dashboard mutation writes an audit entry in the SAME batch as the
/// change, so there is never a change without its record (SRS §9,
/// adminDashboard/CLAUDE.md): `admin_audit_log/{id}` =
/// `adminUid, action, target, before, after, at`.
class AuditLog {
  AuditLog._();

  /// e.g. `product.update`, `category.reorder`, `settings.general.update`.
  static void add(
    WriteBatch batch,
    FirebaseFirestore db, {
    required String adminUid,
    required String action,
    required String target,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) {
    batch.set(db.collection(FirestorePaths.adminAuditLog).doc(), _entry(adminUid, action, target, before, after));
  }

  /// [add] for a transaction: the entry is written with `tx.set`, so it
  /// commits (or not) together with the transaction's other writes.
  static void addTx(
    Transaction tx,
    FirebaseFirestore db, {
    required String adminUid,
    required String action,
    required String target,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) {
    tx.set(db.collection(FirestorePaths.adminAuditLog).doc(), _entry(adminUid, action, target, before, after));
  }

  static Map<String, dynamic> _entry(
          String adminUid, String action, String target, Map<String, dynamic>? before, Map<String, dynamic>? after) =>
      {
        'adminUid': adminUid,
        'action': action,
        'target': target,
        'before': before == null ? null : _plain(before),
        'after': after == null ? null : _plain(after),
        'at': FieldValue.serverTimestamp(),
      };

  /// Sentinels like serverTimestamp can't be stored inside a map value; keep
  /// the audit snapshot to plain data.
  static Map<String, dynamic> _plain(Map<String, dynamic> map) => {
        for (final e in map.entries)
          if (e.value is! FieldValue) e.key: e.value is Map<String, dynamic> ? _plain(e.value as Map<String, dynamic>) : e.value,
      };
}
