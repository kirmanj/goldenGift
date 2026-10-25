import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../models/reel_model.dart';
import '../../products/data/product_query.dart';
import 'reel_derived.dart';

/// The Reels filter (SRS §5.27): one category, price bands, one gift type.
@immutable
class ReelFilter {
  const ReelFilter({this.categoryId, this.priceBands = const {}, this.giftFor});

  final String? categoryId;
  final Set<int> priceBands;
  final GiftAudience? giftFor;

  /// All five bands = no price filter.
  bool get filtersPrice => priceBands.isNotEmpty && priceBands.length < PriceBands.count;

  /// Filters on (the badge on the filter button).
  int get activeCount => (categoryId != null ? 1 : 0) + (filtersPrice ? 1 : 0) + (giftFor != null ? 1 : 0);

  bool get isEmpty => activeCount == 0;

  ReelFilter copyWith({
    String? categoryId,
    bool clearCategory = false,
    Set<int>? priceBands,
    GiftAudience? giftFor,
    bool clearGiftFor = false,
  }) =>
      ReelFilter(
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        priceBands: priceBands ?? this.priceBands,
        giftFor: clearGiftFor ? null : (giftFor ?? this.giftFor),
      );

  @override
  bool operator ==(Object other) =>
      other is ReelFilter &&
      other.categoryId == categoryId &&
      setEquals(other.priceBands, priceBands) &&
      other.giftFor == giftFor;

  @override
  int get hashCode => Object.hash(categoryId, Object.hashAllUnordered(priceBands), giftFor);

  @override
  String toString() => 'ReelFilter($categoryId, $priceBands, $giftFor)';
}

/// One page of the feed.
class ReelFeedPage {
  const ReelFeedPage({required this.items, required this.hasMore, this.cursor});

  final List<ReelModel> items;
  final bool hasMore;
  final DocumentSnapshot<Object?>? cursor;
}

/// The Reels feed (SRS §5.27, §6.4a): visible reels, newest first. Category
/// and gift type are ONE array filter (`filterKeys`), price bands an `in`.
class ReelsRepository {
  ReelsRepository(this._db);
  final FirebaseFirestore _db;

  static const pageSize = 8;

  Query<Map<String, dynamic>> buildQuery(ReelFilter filter) {
    Query<Map<String, dynamic>> query =
        _db.collection(FirestorePaths.reels).where('visible', isEqualTo: true);
    final key = ReelKeys.filterKey(categoryId: filter.categoryId, audience: filter.giftFor);
    if (key != null) query = query.where('filterKeys', arrayContains: key);
    if (filter.filtersPrice) query = query.where('priceBand', whereIn: filter.priceBands.toList()..sort());
    return query.orderBy('createdAt', descending: true);
  }

  Future<ReelFeedPage> fetch(ReelFilter filter, {DocumentSnapshot<Object?>? after, int limit = pageSize}) async {
    var query = buildQuery(filter);
    if (after != null) query = query.startAfterDocument(after);
    final snap = await query.limit(limit).get();
    return ReelFeedPage(
      items: [
        for (final d in snap.docs)
          // A reel without a playable URL is skipped rather than shown broken.
          if ((d.data()['videoUrl'] as String? ?? '').isNotEmpty) ReelModel.fromMap(d.id, d.data()),
      ],
      hasMore: snap.docs.length == limit,
      cursor: snap.docs.isEmpty ? after : snap.docs.last,
    );
  }
}

final reelsRepositoryProvider = Provider<ReelsRepository>((ref) => ReelsRepository(ref.watch(firestoreProvider)));
