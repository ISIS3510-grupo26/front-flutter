import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

/// A comparison the student made, for "Recent comparisons".
class ComparisonEntry {
  final String firstId;
  final String secondId;
  final String firstName;
  final String secondName;
  final String firstEmoji;
  final String secondEmoji;
  final DateTime comparedAt;

  const ComparisonEntry({
    required this.firstId,
    required this.secondId,
    required this.firstName,
    required this.secondName,
    required this.firstEmoji,
    required this.secondEmoji,
    required this.comparedAt,
  });

  /// The same pair in either order is one entry.
  String get pairId => ([firstId, secondId]..sort()).join('|');
}

/// Tests use an in-memory fake.
abstract class ComparisonHistoryStorage {
  /// Saves [entry] as the most recent one; old entries may be dropped.
  Future<void> save(ComparisonEntry entry);

  /// Newest first.
  Future<List<ComparisonEntry>> recent();
}

/// Local storage strategy: relational database (sqflite), table
/// `comparisons` of campus_bites.db (version 3). The list must be there
/// offline and after closing the app, and it is ordered and trimmed with SQL.
class SqliteComparisonHistory implements ComparisonHistoryStorage {
  static const keep = 10;

  final Future<Database> Function() _open;

  const SqliteComparisonHistory([this._open = openLocalDatabase]);

  @override
  Future<void> save(ComparisonEntry e) async {
    final db = await _open();
    // One transaction: the new row and the trim happen together.
    await db.transaction((txn) async {
      await txn.insert(
        'comparisons',
        {
          'pair_id': e.pairId,
          'first_id': e.firstId,
          'second_id': e.secondId,
          'first_name': e.firstName,
          'second_name': e.secondName,
          'first_emoji': e.firstEmoji,
          'second_emoji': e.secondEmoji,
          'compared_at': e.comparedAt.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.rawDelete(
        'DELETE FROM comparisons WHERE pair_id NOT IN '
        '(SELECT pair_id FROM comparisons ORDER BY compared_at DESC LIMIT ?)',
        [keep],
      );
    });
  }

  @override
  Future<List<ComparisonEntry>> recent() async {
    final db = await _open();
    final rows = await db.query('comparisons', orderBy: 'compared_at DESC', limit: keep);
    return [
      for (final row in rows)
        ComparisonEntry(
          firstId: row['first_id'] as String,
          secondId: row['second_id'] as String,
          firstName: row['first_name'] as String,
          secondName: row['second_name'] as String,
          firstEmoji: row['first_emoji'] as String,
          secondEmoji: row['second_emoji'] as String,
          comparedAt: DateTime.parse(row['compared_at'] as String).toLocal(),
        ),
    ];
  }
}
