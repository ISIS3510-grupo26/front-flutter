import 'dart:convert';

/// Orders of "All reviews", with the value the backend expects.
enum ReviewSort {
  newest('newest', 'Newest'),
  highest('highest', 'Highest'),
  lowest('lowest', 'Lowest'),
  helpful('helpful', 'Most helpful');

  final String wire;
  final String label;

  const ReviewSort(this.wire, this.label);

  static ReviewSort fromWire(String value) =>
      values.firstWhere((sort) => sort.wire == value, orElse: () => newest);
}

/// One request of "All reviews": which restaurant, how it is ordered and
/// filtered, and which page. [key] identifies it in the memory cache and in
/// Hive.
class ReviewQuery {
  final String spotId;
  final ReviewSort sort;

  /// Only reviews with these stars; null for all.
  final int? stars;

  /// Text to look for in the review and its author; '' for none.
  final String q;
  final int page;

  const ReviewQuery({
    required this.spotId,
    this.sort = ReviewSort.newest,
    this.stars,
    this.q = '',
    this.page = 1,
  });

  String get key => '$spotId|${sort.wire}|${stars ?? ''}|$q|$page';

  ReviewQuery withPage(int page) => ReviewQuery(spotId: spotId, sort: sort, stars: stars, q: q, page: page);
}

class ReviewItem {
  final int id;
  final String authorName;
  final String initials;
  final String program;
  final int stars;
  final String text;
  final String dinedAgo;
  final int helpfulCount;

  /// Only reviews written in the app have a date; the catalog ones don't.
  final DateTime? createdAt;

  /// Text and author, normalized with [normalizeForSearch], to search the
  /// copy saved on the phone without network.
  final String searchText;

  const ReviewItem({
    required this.id,
    required this.authorName,
    required this.initials,
    required this.program,
    required this.stars,
    required this.text,
    required this.dinedAgo,
    required this.helpfulCount,
    required this.searchText,
    this.createdAt,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    final authorName = json['authorName'] as String;
    final text = json['text'] as String;
    final createdAt = json['createdAt'] as String?;
    return ReviewItem(
      id: json['id'] as int,
      authorName: authorName,
      initials: json['initials'] as String,
      program: json['program'] as String? ?? '',
      stars: json['stars'] as int,
      text: text,
      dinedAgo: json['dinedAgo'] as String,
      helpfulCount: json['helpfulCount'] as int,
      createdAt: createdAt == null ? null : DateTime.parse(createdAt),
      searchText: normalizeForSearch('$text $authorName'),
    );
  }

  /// The same shape the backend sends, so a saved page is read back with
  /// [ReviewItem.fromJson].
  Map<String, dynamic> toJson() => {
        'id': id,
        'authorName': authorName,
        'initials': initials,
        'program': program,
        'stars': stars,
        'text': text,
        'dinedAgo': dinedAgo,
        'helpfulCount': helpfulCount,
        'createdAt': createdAt?.toIso8601String(),
      };
}

class ReviewPage {
  final List<ReviewItem> items;
  final int page;
  final int pageSize;

  /// Reviews that match the filter, across every page.
  final int total;

  const ReviewPage({required this.items, required this.page, required this.pageSize, required this.total});

  bool get hasMore => page * pageSize < total;
}

/// Lowercase and without accents, so "Ñoquis" is found by "noquis" and
/// "Día" by "dia". Pure and top-level: it runs inside the isolate.
String normalizeForSearch(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_unaccented[char] ?? char);
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _unaccented = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Decodes the body of `GET /spots/{id}/reviews` and normalizes every
/// review's text for the offline search. Pure and top-level, so it can run
/// with `Isolate.run()` and be tested without one.
ReviewPage parseReviewPage(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  return ReviewPage(
    items: [
      for (final item in json['items'] as List<dynamic>) ReviewItem.fromJson(item as Map<String, dynamic>),
    ],
    page: json['page'] as int,
    pageSize: json['pageSize'] as int,
    total: json['total'] as int,
  );
}

/// The order, stars and search of [query] applied to reviews saved on the
/// phone, the same way the backend does it: [ReviewSort.newest] puts the
/// reviews with a date first (newest on top) and then the catalog ones, and
/// every order breaks ties with it.
List<ReviewItem> applyLocalQuery(Iterable<ReviewItem> reviews, ReviewQuery query) {
  final needle = normalizeForSearch(query.q);
  final matching = [
    for (final review in reviews)
      if ((query.stars == null || review.stars == query.stars) &&
          (needle.isEmpty || review.searchText.contains(needle)))
        review,
  ];

  int newest(ReviewItem a, ReviewItem b) {
    final (da, db) = (a.createdAt, b.createdAt);
    if (da != null && db != null && da != db) return db.compareTo(da);
    if ((da == null) != (db == null)) return da == null ? 1 : -1;
    return a.id.compareTo(b.id);
  }

  int Function(ReviewItem, ReviewItem) first(int Function(ReviewItem) by, {bool descending = false}) =>
      (a, b) {
        final c = descending ? by(b).compareTo(by(a)) : by(a).compareTo(by(b));
        return c != 0 ? c : newest(a, b);
      };

  matching.sort(switch (query.sort) {
    ReviewSort.newest => newest,
    ReviewSort.highest => first((r) => r.stars, descending: true),
    ReviewSort.lowest => first((r) => r.stars),
    ReviewSort.helpful => first((r) => r.helpfulCount, descending: true),
  });
  return matching;
}
