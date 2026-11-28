import 'package:flutter/foundation.dart';

import '../models/review_page.dart';
import '../repositories/api_exception.dart';
import 'lru_cache.dart';
import 'reviews_local_store.dart';
import 'reviews_service.dart';

/// [network]: no connection and nothing of this restaurant saved on the phone.
/// [server]: the backend answered with an error or with data the app
/// couldn't read; the saved copy is not used then, so a real failure isn't
/// hidden behind old data.
enum ReviewsFailure { network, server }

sealed class ReviewsResult {
  const ReviewsResult();
}

final class ReviewsFailed extends ReviewsResult {
  final ReviewsFailure reason;

  const ReviewsFailed(this.reason);
}

final class ReviewsLoaded extends ReviewsResult {
  /// One page from the server, or every matching saved review offline.
  final List<ReviewItem> items;
  final int total;
  final bool hasMore;

  /// Reviews the user marked as Helpful, as the server knew them.
  final Set<int> votes;

  /// Set when [items] come from the copy saved on the phone: when it was saved.
  final DateTime? offlineSavedAt;

  const ReviewsLoaded({
    required this.items,
    required this.total,
    required this.hasMore,
    required this.votes,
    this.offlineSavedAt,
  });
}

/// Loads the pages of "All reviews".
///
/// - Multithreading: the page and the user's votes are independent requests,
///   so they go out at the same time with Future.wait; the page is decoded in
///   an isolate by [ReviewsServiceAdapter].
/// - Caching: an LRU cache keyed by (spotId, sort, stars, q, page).
/// - Eventual connectivity and local storage: every page that arrives is
///   saved in Hive (`review_pages`) with the votes; without network the
///   screen gets every saved review of the restaurant ordered, filtered and
///   searched on the phone.
class AllReviewsLoader {
  final ReviewsService _service;
  final ReviewsLocalStore? _local;
  final String? Function() _currentUserId;
  final LruCache<String, ({ReviewPage page, Set<int> votes})> _cache;

  AllReviewsLoader({
    required this._service,
    required this._currentUserId,
    this._local,
    LruCache<String, ({ReviewPage page, Set<int> votes})>? cache,
  }) : _cache = cache ?? newReviewPageCache();

  /// Caching strategy: LRU with capacity 12 and a TTL of 2 minutes.
  ///
  /// - 12: a student goes back and forth between a few combinations on the
  ///   same restaurant (Newest, Most helpful, 5 stars, a search) and scrolls a
  ///   couple of pages of each; 12 pages of 10 reviews is about 120 small
  ///   items in memory, and going back to any of them is instant.
  /// - 2 minutes: reviews and Helpful counts change while people use the app,
  ///   unlike the Taste Map ratings (5 minutes). Two minutes covers switching
  ///   chips and coming back without showing counts that are much too old;
  ///   Retry and reconnecting skip the cache.
  static LruCache<String, ({ReviewPage page, Set<int> votes})> newReviewPageCache({DateTime Function()? now}) =>
      LruCache(capacity: 12, ttl: const Duration(minutes: 2), now: now);

  /// [forceRefresh] skips the memory cache (Retry, reconnection).
  Future<ReviewsResult> load(ReviewQuery query, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_cache.get(query.key) case final cached?) return _loaded(cached.page, cached.votes);
    }
    final userId = _currentUserId();
    try {
      final results = await Future.wait<Object>([
        _service.page(query),
        if (userId != null) _service.myHelpfulVotes(query.spotId, userId) else Future.value(<int>{}),
      ]);
      final page = results[0] as ReviewPage;
      final votes = results[1] as Set<int>;
      _cache.put(query.key, (page: page, votes: votes));
      // Future with handler: fire-and-forget, the screen never waits for the disk.
      _local?.savePage(query, page, votes).catchError((Object e) => debugPrint("Couldn't save reviews offline: $e"));
      return _loaded(page, votes);
    } catch (error) {
      if (!isNetworkError(error)) return const ReviewsFailed(ReviewsFailure.server);
      return offline(query);
    }
  }

  /// The saved copy of [query]'s restaurant with [query]'s order, stars and
  /// search applied on the phone; one list, no more pages.
  ReviewsResult offline(ReviewQuery query) {
    final SavedReviews? saved;
    try {
      saved = _local?.saved(query.spotId);
    } catch (e) {
      debugPrint("Couldn't read saved reviews: $e");
      return const ReviewsFailed(ReviewsFailure.network);
    }
    if (saved == null) return const ReviewsFailed(ReviewsFailure.network);
    final items = applyLocalQuery(saved.reviews, query);
    return ReviewsLoaded(
      items: items,
      total: items.length,
      hasMore: false,
      votes: saved.votes,
      offlineSavedAt: saved.savedAt,
    );
  }

  static ReviewsLoaded _loaded(ReviewPage page, Set<int> votes) =>
      ReviewsLoaded(items: page.items, total: page.total, hasMore: page.hasMore, votes: votes);
}
