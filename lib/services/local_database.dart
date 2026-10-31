import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/best_for_you.dart';
import '../models/nearby_pick.dart';
import '../models/spot_detail.dart';

/// Local storage strategy: relational database (sqflite).
///
/// `campus_bites.db` keeps what these screens need to still work offline:
/// - taste_map_picks: the last Taste Map picks, `rank` keeps the backend order.
/// - spot_details: the full `GET /spots/{id}` JSON plus when it was saved.
/// - best_for_you_spots (version 2): the last "Best for you right now"
///   ranking (BQ6), one row per restaurant.
///
/// Version 2 adds its table with an explicit migration: phones that already
/// have version 1 keep their saved picks and pages instead of starting over.
Future<Database> openLocalDatabase() => _database ??= _open();

Future<Database>? _database;

Future<Database> _open() async => openDatabase(
      join(await getDatabasesPath(), 'campus_bites.db'),
      version: 2,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createBestForYouTable(db);
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE taste_map_picks (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            emoji TEXT NOT NULL,
            rating REAL NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            distance_meters INTEGER NOT NULL,
            walk_minutes INTEGER NOT NULL,
            rank INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE spot_details (
            id TEXT PRIMARY KEY,
            json TEXT NOT NULL,
            saved_at TEXT NOT NULL
          )''');
        await _createBestForYouTable(db);
      },
    );

Future<void> _createBestForYouTable(Database db) => db.execute('''
      CREATE TABLE best_for_you_spots (
        spot_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL,
        cuisine TEXT NOT NULL,
        rating REAL NOT NULL,
        wait_minutes INTEGER,
        minutes_ago INTEGER,
        is_recent INTEGER NOT NULL,
        taste_match INTEGER,
        personalized INTEGER NOT NULL,
        rank INTEGER NOT NULL,
        saved_at TEXT NOT NULL
      )''');

/// The last Taste Map picks saved on the phone. Tests use an in-memory fake.
abstract class TasteMapStorage {
  /// Replaces every stored pick with [picks].
  Future<void> savePicks(List<NearbyPick> picks);

  /// The stored picks in the order the backend sent them.
  Future<List<NearbyPick>> readPicks();
}

class SqliteTasteMapStorage implements TasteMapStorage {
  final Future<Database> Function() _open;

  const SqliteTasteMapStorage([this._open = openLocalDatabase]);

  @override
  Future<void> savePicks(List<NearbyPick> picks) async {
    final db = await _open();
    // One transaction: the table never ends up half old, half new.
    await db.transaction((txn) async {
      await txn.delete('taste_map_picks');
      for (var i = 0; i < picks.length; i++) {
        final pick = picks[i];
        await txn.insert('taste_map_picks', {
          'id': pick.id,
          'name': pick.name,
          'emoji': pick.emoji,
          'rating': pick.rating,
          'latitude': pick.latitude,
          'longitude': pick.longitude,
          'distance_meters': pick.distanceMeters,
          'walk_minutes': pick.walkMinutes,
          'rank': i,
        });
      }
    });
  }

  @override
  Future<List<NearbyPick>> readPicks() async {
    final db = await _open();
    final rows = await db.query('taste_map_picks', orderBy: 'rank');
    return [
      for (final row in rows)
        NearbyPick(
          id: row['id'] as String,
          name: row['name'] as String,
          emoji: row['emoji'] as String,
          rating: (row['rating'] as num).toDouble(),
          latitude: (row['latitude'] as num).toDouble(),
          longitude: (row['longitude'] as num).toDouble(),
          distanceMeters: row['distance_meters'] as int,
          walkMinutes: row['walk_minutes'] as int,
        ),
    ];
  }
}

/// The last "Best for you right now" ranking saved on the phone. Tests use an
/// in-memory fake.
abstract class BestForYouStorage {
  /// Replaces the saved ranking with [ranking].
  Future<void> save(BestForYouRanking ranking, {required DateTime savedAt});

  /// The saved ranking and when it was saved, or null if there is none.
  Future<({BestForYouRanking ranking, DateTime savedAt})?> read();
}

class SqliteBestForYouStorage implements BestForYouStorage {
  final Future<Database> Function() _open;

  const SqliteBestForYouStorage([this._open = openLocalDatabase]);

  @override
  Future<void> save(BestForYouRanking ranking, {required DateTime savedAt}) async {
    final db = await _open();
    // One transaction: offline, the student never sees half of two rankings.
    await db.transaction((txn) async {
      await txn.delete('best_for_you_spots');
      for (final (rank, spot) in ranking.spots.indexed) {
        await txn.insert('best_for_you_spots', {
          'spot_id': spot.spotId,
          'name': spot.name,
          'emoji': spot.emoji,
          'cuisine': spot.cuisine,
          'rating': spot.rating,
          'wait_minutes': spot.waitMinutes,
          'minutes_ago': spot.minutesAgo,
          'is_recent': spot.isRecent ? 1 : 0,
          'taste_match': spot.tasteMatch,
          'personalized': ranking.personalized ? 1 : 0,
          'rank': rank,
          'saved_at': savedAt.toUtc().toIso8601String(),
        });
      }
    });
  }

  @override
  Future<({BestForYouRanking ranking, DateTime savedAt})?> read() async {
    final db = await _open();
    final rows = await db.query('best_for_you_spots', orderBy: 'rank');
    if (rows.isEmpty) return null;
    return (
      ranking: BestForYouRanking(
        personalized: rows.first['personalized'] == 1,
        spots: [
          for (final row in rows)
            BestForYouSpot(
              spotId: row['spot_id'] as String,
              name: row['name'] as String,
              emoji: row['emoji'] as String,
              cuisine: row['cuisine'] as String,
              rating: (row['rating'] as num).toDouble(),
              waitMinutes: row['wait_minutes'] as int?,
              minutesAgo: row['minutes_ago'] as int?,
              isRecent: row['is_recent'] == 1,
              tasteMatch: row['taste_match'] as int?,
            ),
        ],
      ),
      savedAt: DateTime.parse(rows.first['saved_at'] as String).toLocal(),
    );
  }
}

/// Restaurant pages saved on the phone. Tests use an in-memory fake.
abstract class SpotDetailStorage {
  Future<void> save(SpotDetail spot);

  /// The saved page and when it was saved, or null if it was never opened.
  Future<({SpotDetail spot, DateTime savedAt})?> read(String id);
}

class SqliteSpotDetailStorage implements SpotDetailStorage {
  final Future<Database> Function() _open;

  const SqliteSpotDetailStorage([this._open = openLocalDatabase]);

  @override
  Future<void> save(SpotDetail spot) async {
    final db = await _open();
    await db.insert(
      'spot_details',
      {
        'id': spot.id,
        'json': jsonEncode(spot.toJson()),
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<({SpotDetail spot, DateTime savedAt})?> read(String id) async {
    final db = await _open();
    final rows = await db.query('spot_details', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final row = rows.single;
    return (
      spot: SpotDetail.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>),
      savedAt: DateTime.parse(row['saved_at'] as String).toLocal(),
    );
  }
}
