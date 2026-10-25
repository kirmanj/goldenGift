import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Counts Firestore document reads the way Firestore bills them, by wrapping
/// a (fake) [FirebaseFirestore] for the SRS §8 read budget (Home ≤ 60 docs):
///
/// * a query `get()` reads every returned document;
/// * a query listener reads every document of its first snapshot, then one
///   per added / changed document;
/// * a document `get()` / listener event reads 1 (a missing doc still costs 1).
///
/// Only the surface the app uses is wrapped; anything else throws so a new
/// call shows up here instead of being silently uncounted. Writes pass through.
class ReadCounter {
  /// Reads per query / document, keyed by a readable description.
  final reads = <String, int>{};

  int get total => reads.values.fold(0, (a, b) => a + b);

  void add(String what, int docs) => reads[what] = (reads[what] ?? 0) + docs;

  /// "12  products where isActive limit 6" lines, biggest first.
  String report() => (reads.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .map((e) => '${e.value.toString().padLeft(4)}  ${e.key}')
      .join('\n');
}

class CountingFirestore implements FirebaseFirestore {
  CountingFirestore(this.inner, this.counter);
  final FirebaseFirestore inner;
  final ReadCounter counter;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _CountingCollection(inner.collection(collectionPath), this);

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) => _CountingDoc(inner.doc(documentPath), this);

  @override
  Query<Map<String, dynamic>> collectionGroup(String collectionPath) =>
      _CountingQuery(inner.collectionGroup(collectionPath), this, 'group $collectionPath');

  @override
  WriteBatch batch() => _CountingBatch(inner.batch());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('CountingFirestore does not wrap ${invocation.memberName} yet');
}

DocumentReference<Map<String, dynamic>> _unwrap(DocumentReference<Map<String, dynamic>> ref) =>
    ref is _CountingDoc ? ref.inner : ref;

class _CountingBatch implements WriteBatch {
  _CountingBatch(this.inner);
  final WriteBatch inner;

  @override
  Future<void> commit() => inner.commit();

  @override
  void delete(DocumentReference document) => inner.delete(_unwrap(document as DocumentReference<Map<String, dynamic>>));

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      inner.set<Map<String, dynamic>>(
          _unwrap(document as DocumentReference<Map<String, dynamic>>), data as Map<String, dynamic>, options);

  @override
  void update(DocumentReference document, Map<String, dynamic> data) =>
      inner.update(_unwrap(document as DocumentReference<Map<String, dynamic>>), data);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('CountingFirestore batch does not wrap ${invocation.memberName} yet');
}

// A test double, like fake_cloud_firestore's own (the classes are @sealed).
// ignore: subtype_of_sealed_class
class _CountingQuery implements Query<Map<String, dynamic>> {
  _CountingQuery(this.inner, this.fs, this.label);
  final Query<Map<String, dynamic>> inner;
  final CountingFirestore fs;
  final String label;

  ReadCounter get _counter => fs.counter;

  Query<Map<String, dynamic>> _wrap(Query<Map<String, dynamic>> q, String step) => _CountingQuery(q, fs, '$label $step');

  @override
  FirebaseFirestore get firestore => fs;

  @override
  Map<String, dynamic> get parameters => inner.parameters;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) =>
      _wrap(
          inner.where(field,
              isEqualTo: isEqualTo,
              isNotEqualTo: isNotEqualTo,
              isLessThan: isLessThan,
              isLessThanOrEqualTo: isLessThanOrEqualTo,
              isGreaterThan: isGreaterThan,
              isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
              arrayContains: arrayContains,
              arrayContainsAny: arrayContainsAny,
              whereIn: whereIn,
              whereNotIn: whereNotIn,
              isNull: isNull),
          'where ${field is String ? field : (field.toString().contains('documentId') ? 'id' : field)}');

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) =>
      _wrap(inner.orderBy(field, descending: descending), 'orderBy $field');

  @override
  Query<Map<String, dynamic>> limit(int limit) => _wrap(inner.limit(limit), 'limit $limit');

  @override
  Query<Map<String, dynamic>> limitToLast(int limit) => _wrap(inner.limitToLast(limit), 'limitToLast $limit');

  @override
  Query<Map<String, dynamic>> startAfterDocument(DocumentSnapshot<Object?> documentSnapshot) =>
      _wrap(inner.startAfterDocument(documentSnapshot), 'after');

  @override
  Query<Map<String, dynamic>> startAfter(Iterable<Object?> values) => _wrap(inner.startAfter(values), 'after');

  @override
  Query<Map<String, dynamic>> startAtDocument(DocumentSnapshot<Object?> documentSnapshot) =>
      _wrap(inner.startAtDocument(documentSnapshot), 'at');

  @override
  Query<Map<String, dynamic>> startAt(Iterable<Object?> values) => _wrap(inner.startAt(values), 'at');

  @override
  Query<Map<String, dynamic>> endBeforeDocument(DocumentSnapshot<Object?> documentSnapshot) =>
      _wrap(inner.endBeforeDocument(documentSnapshot), 'before');

  @override
  Query<Map<String, dynamic>> endBefore(Iterable<Object?> values) => _wrap(inner.endBefore(values), 'before');

  @override
  Query<Map<String, dynamic>> endAtDocument(DocumentSnapshot<Object?> documentSnapshot) =>
      _wrap(inner.endAtDocument(documentSnapshot), 'end');

  @override
  Query<Map<String, dynamic>> endAt(Iterable<Object?> values) => _wrap(inner.endAt(values), 'end');

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final snap = await inner.get(options);
    _counter.add('get $label', snap.docs.length);
    return snap;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    // Billed: the first snapshot's documents, then only added / changed ones
    // (the fake re-emits identical snapshots, which Firestore doesn't bill).
    final seen = <String, String>{};
    return inner.snapshots(includeMetadataChanges: includeMetadataChanges, source: source).map((snap) {
      var reads = 0;
      for (final d in snap.docs) {
        final data = d.data().toString();
        if (seen[d.id] != data) reads++;
        seen[d.id] = data;
      }
      _counter.add('listen $label', reads);
      return snap;
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('CountingFirestore query does not wrap ${invocation.memberName} yet');
}

// A test double, like fake_cloud_firestore's own (the classes are @sealed).
// ignore: subtype_of_sealed_class
class _CountingCollection extends _CountingQuery implements CollectionReference<Map<String, dynamic>> {
  _CountingCollection(this.collection, CountingFirestore fs) : super(collection, fs, collection.path);
  final CollectionReference<Map<String, dynamic>> collection;

  @override
  String get id => collection.id;

  @override
  String get path => collection.path;

  @override
  DocumentReference<Map<String, dynamic>>? get parent {
    final p = collection.parent;
    return p == null ? null : _CountingDoc(p, fs);
  }

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _CountingDoc(collection.doc(path), fs);

  @override
  Future<DocumentReference<Map<String, dynamic>>> add(Map<String, dynamic> data) async =>
      _CountingDoc(await collection.add(data), fs);
}

// A test double, like fake_cloud_firestore's own (the classes are @sealed).
// ignore: subtype_of_sealed_class
class _CountingDoc implements DocumentReference<Map<String, dynamic>> {
  _CountingDoc(this.inner, this.fs);
  final DocumentReference<Map<String, dynamic>> inner;
  final CountingFirestore fs;

  @override
  FirebaseFirestore get firestore => fs;

  @override
  String get id => inner.id;

  @override
  String get path => inner.path;

  @override
  CollectionReference<Map<String, dynamic>> get parent => _CountingCollection(inner.parent, fs);

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _CountingCollection(inner.collection(collectionPath), fs);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final snap = await inner.get(options);
    fs.counter.add('get doc $path', 1);
    return snap;
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) =>
      _docListen(inner.snapshots(includeMetadataChanges: includeMetadataChanges, source: source));

  /// 1 read for the first event, then 1 per real change.
  Stream<DocumentSnapshot<Map<String, dynamic>>> _docListen(Stream<DocumentSnapshot<Map<String, dynamic>>> events) {
    String? last;
    var first = true;
    return events.map((snap) {
      final data = snap.data().toString();
      if (first || data != last) fs.counter.add('listen doc $path', 1);
      first = false;
      last = data;
      return snap;
    });
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) => inner.set(data, options);

  @override
  Future<void> update(Map<Object, Object?> data) => inner.update(data);

  @override
  Future<void> delete() => inner.delete();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('CountingFirestore doc does not wrap ${invocation.memberName} yet');
}
