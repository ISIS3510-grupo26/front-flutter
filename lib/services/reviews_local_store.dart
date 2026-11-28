import 'package:hive/hive.dart';

import '../models/review_page.dart';

/// A page of reviews saved on the phone, with the user's votes of that
/// restaurant when it was saved.
class SavedReviewPage {
  final ReviewPage page;
  final Set<int> votes;
  final DateTime savedAt;

  const SavedReviewPage({required this.page, required this.votes, required this.savedAt});
}

/// Everything saved for one restaurant, put together for the offline view.
class SavedReviews {
  /// Every saved review of the restaurant, once each (from any order,
  /// filter or page); the screen orders and filters them itself.
  final List<ReviewItem> reviews;

  /// The user's votes from the most recently saved page.
  final Set<int> votes;

  /// When the oldest of the pages used was saved: "reviews from HH:mm"
  /// never claims the copy is newer than it is.
  final DateTime savedAt;

  const SavedReviews({required this.reviews, required this.votes, required this.savedAt});
}

/// A Helpful vote the server hasn't received yet.
class PendingHelpful {
  final int reviewId;
  final String spotId;

  /// true = marked, false = unmarked: the last thing the student did.
  final bool desired;
  final DateTime updatedAt;

  const PendingHelpful({
    required this.reviewId,
    required this.spotId,
    required this.desired,
    required this.updatedAt,
  });
}

/// Local storage strategy for "All reviews": Hive (key-value), the same
/// database as [HiveStore] and [FavoritesLocalStore], with two boxes of plain
/// maps (no TypeAdapters). campus_bites.db (SQLite) is not touched.
///
/// - `review_pages`: query key (spot|sort|stars|q|page) -> the page's
///   reviews, total, the user's votes and `savedAt`. Without network the
///   screen joins every saved page of a restaurant and orders, filters and
///   searches them on the phone.
/// - `helpful_pending`: reviewId -> {spotId, desired, updatedAt}. The key is
///   the review, so marking and unmarking it offline leave one entry with the
///   last state, like favorites.
///
/// Both boxes belong to the signed-in user and are emptied on sign out.
class ReviewsLocalStore {
  static const pagesBox = 'review_pages';
  static const pendingBox = 'helpful_pending';

  /// The oldest pages are dropped over this, so the box can't grow forever.
  static const maxPages = 60;

  final Box<Map> _pages;
  final Box<Map> _pending;

  ReviewsLocalStore._(this._pages, this._pending);

  /// Hive must already be initialized (main() opens [HiveStore] first).
  static Future<ReviewsLocalStore> open() async {
    final boxes = await Future.wait([
      Hive.openBox<Map>(pagesBox),
      Hive.openBox<Map>(pendingBox),
    ]);
    return ReviewsLocalStore._(boxes[0], boxes[1]);
  }

  // ---------- Pages (the copy) ----------

  Future<void> savePage(ReviewQuery query, ReviewPage page, Set<int> votes, {DateTime? now}) async {
    await _pages.put(query.key, {
      'spotId': query.spotId,
      'items': [for (final item in page.items) item.toJson()],
      'page': page.page,
      'pageSize': page.pageSize,
      'total': page.total,
      'votes': votes.toList(),
      'savedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
    });
    await _trim();
  }

  SavedReviewPage? page(ReviewQuery query) {
    final map = _pages.get(query.key);
    return map == null ? null : _read(map);
  }

  /// Every saved review of [spotId], or null when none was ever saved.
  SavedReviews? saved(String spotId) {
    final pages = [
      for (final map in _pages.values)
        if (map['spotId'] == spotId) _read(map),
    ]..sort((a, b) => a.savedAt.compareTo(b.savedAt));
    if (pages.isEmpty) return null;
    final byId = <int, ReviewItem>{};
    // Oldest first, so the newest copy of a review (its latest helpful
    // count) is the one that stays.
    for (final saved in pages) {
      for (final item in saved.page.items) {
        byId[item.id] = item;
      }
    }
    return SavedReviews(reviews: byId.values.toList(), votes: pages.last.votes, savedAt: pages.first.savedAt);
  }

  SavedReviewPage _read(Map<dynamic, dynamic> map) => SavedReviewPage(
        page: ReviewPage(
          items: [
            for (final item in map['items'] as List<dynamic>)
              ReviewItem.fromJson(Map<String, dynamic>.from(item as Map)),
          ],
          page: map['page'] as int,
          pageSize: map['pageSize'] as int,
          total: map['total'] as int,
        ),
        votes: {for (final id in map['votes'] as List<dynamic>) id as int},
        savedAt: DateTime.parse(map['savedAt'] as String),
      );

  Future<void> _trim() async {
    final extra = _pages.length - maxPages;
    if (extra <= 0) return;
    final oldestFirst = _pages.keys.toList()
      ..sort((a, b) => (_pages.get(a)!['savedAt'] as String).compareTo(_pages.get(b)!['savedAt'] as String));
    await _pages.deleteAll(oldestFirst.take(extra));
  }

  // ---------- Pending Helpful votes ----------

  List<PendingHelpful> get pending => [
        for (final key in _pending.keys)
          PendingHelpful(
            reviewId: int.parse(key as String),
            spotId: _pending.get(key)!['spotId'] as String,
            desired: _pending.get(key)!['desired'] as bool,
            updatedAt: DateTime.parse(_pending.get(key)!['updatedAt'] as String),
          ),
      ];

  /// reviewId -> the vote waiting to be sent.
  Map<int, bool> get pendingVotes => {for (final p in pending) p.reviewId: p.desired};

  /// Collapses by review: a second tap on the same review overwrites the first.
  Future<PendingHelpful> queue(String spotId, int reviewId, {required bool desired, DateTime? now}) async {
    final change = PendingHelpful(
      reviewId: reviewId,
      spotId: spotId,
      desired: desired,
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
    await _pending.put('$reviewId', {
      'spotId': spotId,
      'desired': desired,
      'updatedAt': change.updatedAt.toIso8601String(),
    });
    return change;
  }

  /// Forgets [change] after the server got it, unless the student tapped
  /// that review again in the meantime (then the newer vote stays pending).
  Future<void> markSent(PendingHelpful change) async {
    final current = _pending.get('${change.reviewId}');
    if (current != null &&
        DateTime.parse(current['updatedAt'] as String).isAtSameMomentAs(change.updatedAt)) {
      await _pending.delete('${change.reviewId}');
    }
  }

  /// Sign out: both boxes belong to the user who is leaving.
  Future<void> clear() => Future.wait([_pages.clear(), _pending.clear()]);
}
