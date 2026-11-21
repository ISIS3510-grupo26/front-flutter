/// Which restaurant wins a row of the comparison.
enum CompareSide { first, second, none }

/// One row of Compare: the value of each restaurant and which one is better.
class CompareRow {
  final String label;
  final String first;
  final String second;
  final CompareSide winner;

  const CompareRow({
    required this.label,
    required this.first,
    required this.second,
    this.winner = CompareSide.none,
  });
}

/// What one side of the comparison needs. [detail] is the restaurant page as
/// JSON (`SpotDetail.toJson()`), or null when it isn't available offline.
/// Plain data only, so it can be sent to an isolate.
class CompareSideInput {
  final String id;
  final Map<String, dynamic>? detail;

  /// The student's compatibility with this place (null: use the catalog %).
  final int? match;

  /// Last wait reported in the last 2 hours (BQ4), null when there is none.
  final int? waitMinutes;

  /// From the catalog on the phone, for a side whose page is missing.
  final String fallbackName;
  final String fallbackEmoji;

  const CompareSideInput({
    required this.id,
    required this.detail,
    required this.match,
    required this.waitMinutes,
    required this.fallbackName,
    required this.fallbackEmoji,
  });
}

/// Two restaurants side by side.
class SpotComparison {
  final String firstId;
  final String secondId;
  final String firstName;
  final String secondName;
  final String firstEmoji;
  final String secondEmoji;
  final List<CompareRow> rows;

  /// False when one of the pages is missing (offline and never opened).
  final bool complete;

  const SpotComparison({
    required this.firstId,
    required this.secondId,
    required this.firstName,
    required this.secondName,
    required this.firstEmoji,
    required this.secondEmoji,
    required this.rows,
    required this.complete,
  });

  int get firstWins => rows.where((r) => r.winner == CompareSide.first).length;
  int get secondWins => rows.where((r) => r.winner == CompareSide.second).length;

  /// Rows where one of the two is better (cuisine, for example, never is).
  int get decidedRows => rows.where((r) => r.winner != CompareSide.none).length;

  /// "Conda de Bons wins 4 of 5", "It's a tie, 2 each" or null if incomplete.
  String? get verdict {
    if (!complete) return null;
    final total = firstWins + secondWins;
    if (total == 0) return 'They are even on everything we can compare.';
    if (firstWins == secondWins) return "It's a tie, $firstWins each.";
    final (name, wins) = firstWins > secondWins ? (firstName, firstWins) : (secondName, secondWins);
    return '$name wins $wins of $total.';
  }
}

/// Builds the table and the winners. It runs in an isolate (see
/// CompareLoader), so it is a top-level function over plain data.
SpotComparison buildSpotComparison(({CompareSideInput first, CompareSideInput second}) input) {
  final a = input.first;
  final b = input.second;
  final da = a.detail;
  final db = b.detail;

  String text(Map<String, dynamic>? d, String Function(Map<String, dynamic>) f) => d == null ? '—' : f(d);
  CompareSide best(num? x, num? y, {required bool higherIsBetter}) {
    if (x == null || y == null || x == y) return CompareSide.none;
    return (x > y) == higherIsBetter ? CompareSide.first : CompareSide.second;
  }

  int? match(CompareSideInput s) => s.detail == null ? null : s.match ?? (s.detail!['affinityPercent'] as int);
  double? rating(Map<String, dynamic>? d) => d == null ? null : (d['rating'] as num).toDouble();
  int? walk(Map<String, dynamic>? d) => d == null ? null : d['walkMinutes'] as int;
  int? price(Map<String, dynamic>? d) => d == null ? null : lowestPrice(d['price'] as String);
  int? veggie(Map<String, dynamic>? d) => d == null ? null : ((d['isVegetarian'] as bool) ? 1 : 0);
  String wait(CompareSideInput s) => s.detail == null
      ? '—'
      : s.waitMinutes == null
          ? 'No recent report'
          : '${s.waitMinutes} min';

  final rows = [
    CompareRow(
      label: 'Taste match',
      first: match(a) == null ? '—' : '${match(a)}%',
      second: match(b) == null ? '—' : '${match(b)}%',
      winner: best(match(a), match(b), higherIsBetter: true),
    ),
    CompareRow(
      label: 'Rating',
      first: text(da, (d) => '${rating(d)!.toStringAsFixed(1)} ★ (${d['totalReviews']})'),
      second: text(db, (d) => '${rating(d)!.toStringAsFixed(1)} ★ (${d['totalReviews']})'),
      winner: best(rating(da), rating(db), higherIsBetter: true),
    ),
    CompareRow(
      label: 'Price',
      first: text(da, (d) => d['price'] as String),
      second: text(db, (d) => d['price'] as String),
      winner: best(price(da), price(db), higherIsBetter: false),
    ),
    CompareRow(
      label: 'Walk',
      first: text(da, (d) => '${d['walkMinutes']} min'),
      second: text(db, (d) => '${d['walkMinutes']} min'),
      winner: best(walk(da), walk(db), higherIsBetter: false),
    ),
    CompareRow(
      label: 'Wait now',
      first: wait(a),
      second: wait(b),
      winner: da == null || db == null
          ? CompareSide.none
          : best(a.waitMinutes, b.waitMinutes, higherIsBetter: false),
    ),
    CompareRow(
      label: 'Vegetarian',
      first: text(da, (d) => (d['isVegetarian'] as bool) ? 'Yes' : 'No'),
      second: text(db, (d) => (d['isVegetarian'] as bool) ? 'Yes' : 'No'),
      winner: best(veggie(da), veggie(db), higherIsBetter: true),
    ),
    CompareRow(
      label: 'Cuisine',
      first: text(da, (d) => cuisineOf(d['subtitle'] as String)),
      second: text(db, (d) => cuisineOf(d['subtitle'] as String)),
    ),
  ];

  return SpotComparison(
    firstId: a.id,
    secondId: b.id,
    firstName: da?['name'] as String? ?? a.fallbackName,
    secondName: db?['name'] as String? ?? b.fallbackName,
    firstEmoji: da?['emoji'] as String? ?? a.fallbackEmoji,
    secondEmoji: db?['emoji'] as String? ?? b.fallbackEmoji,
    rows: rows,
    complete: da != null && db != null,
  );
}

/// '$12.000 - $22.000 COP' -> 12000; '$6.500 COP' -> 6500; null if there is
/// no number. Ranges compare by their lowest price.
int? lowestPrice(String price) {
  final match = RegExp(r'(\d[\d.,]*)').firstMatch(price);
  if (match == null) return null;
  return int.tryParse(match.group(1)!.replaceAll(RegExp(r'[.,]'), ''));
}

/// 'Burgers & Fries • North Quad Plaza' -> 'Burgers & Fries'
String cuisineOf(String subtitle) => subtitle.split('•').first.trim();
