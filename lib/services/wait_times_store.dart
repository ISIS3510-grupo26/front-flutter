import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/best_time.dart';
import '../models/wait_time.dart';
import '../repositories/api_exception.dart';
import '../repositories/wait_times_repository.dart';
import 'best_time_loader.dart';

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
///
/// Sprint 4: it also keeps the last "Best time to go" (BQ15) of each window. It is the same data (wait reports)
/// summarized by hour, so it lives in the same database: version 2 adds three tables (see [_createBestTimeTables]).
class WaitTimesStore implements BestTimeStorage {
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

  /// BQ15: replaces the saved copy of that window in one transaction, so a copy is never half old and half new.
  @override
  Future<void> saveBestTimes(BestTimeReport report, {required DateTime savedAt}) async {
    final db = await _db;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final table in ['best_time_reports', 'best_time_spots', 'best_time_hours']) {
        batch.delete(table, where: 'days = ?', whereArgs: [report.days]);
      }
      batch.insert('best_time_reports', {
        'days': report.days,
        'min_reports': report.minReports,
        'total_reports': report.totalReports,
        'saved_at': savedAt.toUtc().toIso8601String(),
      });
      void addHours(String spotId, List<HourlyWait> hours) {
        for (final wait in hours) {
          batch.insert('best_time_hours', {
            'days': report.days,
            'spot_id': spotId,
            'hour': wait.hour,
            'avg_minutes': wait.avgMinutes,
            'reports': wait.reports,
          });
        }
      }

      addHours(_campusRow, report.campusByHour);
      for (final (position, spot) in report.spots.indexed) {
        batch.insert('best_time_spots', {
          'days': report.days,
          'spot_id': spot.spotId,
          'position': position,
          'name': spot.name,
          'emoji': spot.emoji,
          'reports': spot.reports,
          'best_hour': spot.bestHour,
          'best_avg': spot.bestAvgMinutes,
          'worst_hour': spot.worstHour,
          'worst_avg': spot.worstAvgMinutes,
        });
        addHours(spot.spotId, spot.byHour);
      }
      await batch.commit(noResult: true);
    });
  }

  /// BQ15: the saved copy of that window, with the restaurants in the order the backend sent them.
  @override
  Future<({BestTimeReport report, DateTime savedAt})?> readBestTimes(int days) async {
    final db = await _db;
    final reports = await db.query('best_time_reports', where: 'days = ?', whereArgs: [days]);
    if (reports.isEmpty) return null;
    final spotRows = await db.query('best_time_spots', where: 'days = ?', whereArgs: [days], orderBy: 'position');
    final hourRows = await db.query('best_time_hours', where: 'days = ?', whereArgs: [days], orderBy: 'hour');

    // spot_id -> its hours, in one pass over the rows.
    final hours = <String, List<HourlyWait>>{};
    for (final row in hourRows) {
      hours.putIfAbsent(row['spot_id'] as String, () => []).add(HourlyWait(
            hour: row['hour'] as int,
            avgMinutes: (row['avg_minutes'] as num).toDouble(),
            reports: row['reports'] as int,
          ));
    }
    final saved = reports.first;
    return (
      report: BestTimeReport(
        days: days,
        minReports: saved['min_reports'] as int,
        totalReports: saved['total_reports'] as int,
        campusByHour: hours[_campusRow] ?? const [],
        spots: [
          for (final row in spotRows)
            BestTimeSpot(
              spotId: row['spot_id'] as String,
              name: row['name'] as String,
              emoji: row['emoji'] as String,
              reports: row['reports'] as int,
              bestHour: row['best_hour'] as int?,
              bestAvgMinutes: (row['best_avg'] as num?)?.toDouble(),
              worstHour: row['worst_hour'] as int?,
              worstAvgMinutes: (row['worst_avg'] as num?)?.toDouble(),
              byHour: hours[row['spot_id']] ?? const [],
            ),
        ],
      ),
      savedAt: DateTime.parse(saved['saved_at'] as String).toLocal(),
    );
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
      // 2: Best time to go (Sprint 4).
      version: 2,
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
        await _createBestTimeTables(db);
      },
      // Phones that already had version 1 keep their wait times and pending reports, only the new tables are added.
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createBestTimeTables(db);
      },
    );

/// One row per window (7 or 28 days), one per restaurant of that window and one per hour with reports. The
/// campus hours (all restaurants together) use [_campusRow] as spot_id. The key of every table starts with
/// `days`, so saving a window replaces only that window.
Future<void> _createBestTimeTables(Database db) async {
  await db.execute('''
    CREATE TABLE best_time_reports (
      days INTEGER PRIMARY KEY,
      min_reports INTEGER NOT NULL,
      total_reports INTEGER NOT NULL,
      saved_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE best_time_spots (
      days INTEGER NOT NULL,
      spot_id TEXT NOT NULL,
      position INTEGER NOT NULL,
      name TEXT NOT NULL,
      emoji TEXT NOT NULL,
      reports INTEGER NOT NULL,
      best_hour INTEGER,
      best_avg REAL,
      worst_hour INTEGER,
      worst_avg REAL,
      PRIMARY KEY (days, spot_id)
    )''');
  await db.execute('''
    CREATE TABLE best_time_hours (
      days INTEGER NOT NULL,
      spot_id TEXT NOT NULL,
      hour INTEGER NOT NULL,
      avg_minutes REAL NOT NULL,
      reports INTEGER NOT NULL,
      PRIMARY KEY (days, spot_id, hour)
    )''');
}

/// spot_id of the campus hours in best_time_hours. No restaurant id is empty.
const _campusRow = '';
