import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/wait_time.dart';
import '../repositories/api_exception.dart';
import '../repositories/wait_times_repository.dart';

/// What the wait times screen had the last time it loaded, to show it offline.
class SavedWaitTimes {
  final List<LastWaitTime> waits;
  final DateTime savedAt;

  /// spotId -> minutes of the report the student made offline and that is still waiting to be sent.
  final Map<String, int> pending;

  const SavedWaitTimes({required this.waits, required this.savedAt, required this.pending});
}

/// Local storage strategy: relational database (sqflite) + preferences.
/// The time of the last successful load is a single small value, so it goes to SharedPreferences instead of a table.
class WaitTimesStore {
  static const _savedAtKey = 'waitTimes.savedAt';

  final SharedPreferencesAsync _prefs;
  final Future<Database> Function() _openDb;
  late final Future<Database> _db = _openDb();

  /// The send in progress. If the app opens and the connection comes back at the same time, both get this 
  /// same Future and nothing is sent twice.
  Future<int>? _flushing;

  WaitTimesStore({SharedPreferencesAsync? prefs, Future<Database> Function()? openDb})
      : _prefs = prefs ?? SharedPreferencesAsync(),
        _openDb = openDb ?? _openWaitTimesDatabase;

  /// Saves the list the backend sent. It is an upsert inside one transaction: the whole list is updated or nothing is
  Future<void> saveLatest(List<LastWaitTime> waits, DateTime savedAt) async {
    final db = await _db;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final (position, wait) in waits.indexed) {
        batch.execute(
          'INSERT INTO spot_waits (spot_id, position, name, emoji, minutes, minutes_ago, is_recent, recent_reports) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(spot_id) DO UPDATE SET position = excluded.position, name = excluded.name, '
          'emoji = excluded.emoji, minutes = excluded.minutes, minutes_ago = excluded.minutes_ago, '
          'is_recent = excluded.is_recent, recent_reports = excluded.recent_reports',
          [
            wait.spotId,
            position,
            wait.name,
            wait.emoji,
            wait.minutes,
            wait.minutesAgo,
            wait.isRecent ? 1 : 0,
            wait.recentReports,
          ],
        );
      }
      await batch.commit(noResult: true);
    });
    await _prefs.setString(_savedAtKey, savedAt.toUtc().toIso8601String());
  }

  /// The saved list with the newest pending report of each restaurant, in the order the backend sent it. 
  /// Null if it never loaded.
  Future<SavedWaitTimes?> loadSaved() async {
    final savedAt = await _prefs.getString(_savedAtKey);
    if (savedAt == null) return null;
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT w.*, p.minutes AS pending_minutes FROM spot_waits w '
      'LEFT JOIN pending_reports p ON p.spot_id = w.spot_id '
      'AND p.reported_at = (SELECT MAX(reported_at) FROM pending_reports WHERE spot_id = w.spot_id) '
      'ORDER BY w.position',
    );
    if (rows.isEmpty) return null;
    return SavedWaitTimes(
      waits: [for (final row in rows) LastWaitTime.fromRow(row)],
      savedAt: DateTime.parse(savedAt).toLocal(),
      pending: {
        for (final row in rows)
          if (row['pending_minutes'] != null) row['spot_id'] as String: row['pending_minutes'] as int,
      },
    );
  }

  Future<void> addPending(WaitReport report) async {
    final db = await _db;
    await db.insert(
      'pending_reports',
      {
        'report_id': report.reportId,
        'spot_id': report.spotId,
        'minutes': report.minutes,
        'reported_at': report.reportedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Reports waiting to be sent, oldest first.
  Future<List<WaitReport>> pendingReports() async {
    final db = await _db;
    final rows = await db.query('pending_reports', orderBy: 'reported_at');
    return [
      for (final row in rows)
        WaitReport(
          reportId: row['report_id'] as String,
          spotId: row['spot_id'] as String,
          minutes: row['minutes'] as int,
          reportedAt: DateTime.parse(row['reported_at'] as String),
        ),
    ];
  }

  /// spotId -> minutes of the newest pending report.
  Future<Map<String, int>> pendingBySpot() async =>
      {for (final report in await pendingReports()) report.spotId: report.minutes};

  Future<void> removePending(String reportId) async {
    final db = await _db;
    await db.delete('pending_reports', where: 'report_id = ?', whereArgs: [reportId]);
  }

  /// Eventual connectivity (store and forward): sends the reports made offline, oldest first, and deletes each 
  /// one only after the backend accepts it. A network failure stops the loop (still offline) and the rest
  /// stay saved.
  Future<int> flush(WaitTimesRepository repository) =>
      _flushing ??= _flush(repository).whenComplete(() => _flushing = null);

  Future<int> _flush(WaitTimesRepository repository) async {
    var sent = 0;
    for (final report in await pendingReports()) {
      try {
        await repository.send(report);
        sent++;
      } on ApiException catch (e) {
        if (e.statusCode >= 500) break;
      } on Exception catch (e) {
        if (isNetworkError(e)) break;
        rethrow;
      }
      await removePending(report.reportId);
    }
    return sent;
  }
}

Future<Database> _openWaitTimesDatabase() async => openDatabase(
      join(await getDatabasesPath(), 'wait_times.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE spot_waits (
            spot_id TEXT PRIMARY KEY,
            position INTEGER NOT NULL,
            name TEXT NOT NULL,
            emoji TEXT NOT NULL,
            minutes INTEGER,
            minutes_ago INTEGER,
            is_recent INTEGER NOT NULL,
            recent_reports INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE pending_reports (
            report_id TEXT PRIMARY KEY,
            spot_id TEXT NOT NULL REFERENCES spot_waits(spot_id),
            minutes INTEGER NOT NULL,
            reported_at TEXT NOT NULL
          )''');
      },
    );
