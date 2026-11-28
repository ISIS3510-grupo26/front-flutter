import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../models/telemetry_event.dart';
import 'local_database.dart';

/// A restaurant the student opened from a compatibility recommendation and
/// may still walk to (BQ9). [eventId] is the id of its recommendation_open
/// event.
class VisitCandidate {
  final String eventId;
  final String? userId;
  final String spotId;
  final double latitude;
  final double longitude;
  final DateTime openedAt;

  const VisitCandidate({
    required this.eventId,
    required this.userId,
    required this.spotId,
    required this.latitude,
    required this.longitude,
    required this.openedAt,
  });
}

/// The visit candidates saved on the phone. Tests use an in-memory fake.
abstract class VisitCandidateStorage {
  Future<void> add(VisitCandidate candidate);

  /// Every saved candidate, oldest first.
  Future<List<VisitCandidate>> all();

  Future<void> remove(Iterable<String> eventIds);

  Future<void> removeOpenedBefore(DateTime time);
}

/// Local storage strategy: relational database (sqflite), table
/// `recommendation_candidates` of campus_bites.db (version 3). A candidate
/// must survive closing the app: the student opens the recommendation, closes
/// CampusBites and walks there.
class SqliteVisitCandidateStorage implements VisitCandidateStorage {
  final Future<Database> Function() _open;

  const SqliteVisitCandidateStorage([this._open = openLocalDatabase]);

  @override
  Future<void> add(VisitCandidate c) async {
    final db = await _open();
    await db.insert(
      'recommendation_candidates',
      {
        'event_id': c.eventId,
        'user_id': c.userId,
        'spot_id': c.spotId,
        'latitude': c.latitude,
        'longitude': c.longitude,
        'opened_at': c.openedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<VisitCandidate>> all() async {
    final db = await _open();
    final rows = await db.query('recommendation_candidates', orderBy: 'opened_at');
    return [
      for (final row in rows)
        VisitCandidate(
          eventId: row['event_id'] as String,
          userId: row['user_id'] as String?,
          spotId: row['spot_id'] as String,
          latitude: (row['latitude'] as num).toDouble(),
          longitude: (row['longitude'] as num).toDouble(),
          openedAt: DateTime.parse(row['opened_at'] as String),
        ),
    ];
  }

  @override
  Future<void> remove(Iterable<String> eventIds) async {
    final ids = eventIds.toList();
    if (ids.isEmpty) return;
    final db = await _open();
    await db.delete(
      'recommendation_candidates',
      where: 'event_id IN (${List.filled(ids.length, '?').join(', ')})',
      whereArgs: ids,
    );
  }

  @override
  Future<void> removeOpenedBefore(DateTime time) async {
    final db = await _open();
    await db.delete(
      'recommendation_candidates',
      where: 'opened_at < ?',
      whereArgs: [time.toUtc().toIso8601String()],
    );
  }
}

typedef LatLngReader = Future<LatLng?> Function();

/// Where the phone is, or null when location can't be used. It never asks
/// for permission: BQ9 only uses the location the student already allowed
/// for the Taste Map, and only while the app is open.
Future<LatLng?> currentPositionIfAllowed() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
    return null;
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 15),
    ),
  );
  return LatLng(position.latitude, position.longitude);
}

/// BQ9: did the student go to the restaurants the app recommended by
/// compatibility?
///
/// [recordOpen] sends a recommendation_open event and saves the restaurant as
/// a visit candidate. [checkForVisits] looks at where the phone is and, for
/// every candidate less than [arrivalRadiusMeters] away and opened less than
/// [window] ago, sends one recommendation_visit event and forgets it.
///
/// Privacy: the position never leaves the phone and is never saved; only the
/// event with the spotId is sent. Without candidates the GPS is not used.
class RecommendationVisitTracker {
  /// Inside this distance the student is at the restaurant (GPS on campus is
  /// often 20-50 m off, and the buildings are big).
  static const arrivalRadiusMeters = 100;

  /// A visit counts only if it happens within this time after opening the
  /// recommendation; later, it was probably not because of it.
  static const window = Duration(hours: 4);

  /// How often to look while the app is in the foreground and there are
  /// candidates.
  static const checkEvery = Duration(minutes: 2);

  final VisitCandidateStorage _storage;
  final void Function(TelemetryEvent event) _send;
  final String? Function() _currentUserId;
  final LatLngReader _position;
  final DateTime Function() _now;

  /// Gets the restaurants just visited, e.g. to greet the student.
  final void Function(List<String> spotIds)? onVisited;

  Future<List<String>>? _checking;
  Timer? _timer;

  /// [send] is TelemetryQueue.enqueue: the events are saved on disk and sent
  /// when there is network (store and forward), so a visit made offline is
  /// not lost.
  RecommendationVisitTracker({
    required this._send,
    required this._currentUserId,
    this._storage = const SqliteVisitCandidateStorage(),
    this._position = currentPositionIfAllowed,
    DateTime Function()? now,
    this.onVisited,
  }) : _now = now ?? DateTime.now;

  /// The student opened [spotId], at [latitude], [longitude], from a
  /// recommendation. If the phone is already at the restaurant, the candidate
  /// is dropped: being there before opening it is not a visit because of it.
  Future<void> recordOpen({
    required String spotId,
    required double latitude,
    required double longitude,
  }) async {
    final userId = _currentUserId();
    final event = TelemetryEvent.recommendationOpen(spotId: spotId, userId: userId);
    _send(event);
    final candidate = VisitCandidate(
      eventId: event.eventId,
      userId: userId,
      spotId: spotId,
      latitude: latitude,
      longitude: longitude,
      openedAt: _now(),
    );
    await _storage.add(candidate);
    final here = await _safePosition();
    if (here != null && _metersTo(here, candidate) <= arrivalRadiusMeters) {
      await _storage.remove([candidate.eventId]);
    }
  }

  /// Multithreading strategy: single flight. Opening the app, coming back to
  /// it and the timer can ask at the same moment; they all share one check,
  /// so the GPS is read once and a visit is never sent twice.
  /// Returns the restaurants visited (each at most once).
  Future<List<String>> checkForVisits() =>
      _checking ??= _check().whenComplete(() => _checking = null);

  Future<List<String>> _check() async {
    await _storage.removeOpenedBefore(_now().subtract(window));
    final candidates = await _storage.all();
    if (candidates.isEmpty) return const [];
    final here = await _safePosition();
    if (here == null) return const [];

    final arrived = [for (final c in candidates) if (_metersTo(here, c) <= arrivalRadiusMeters) c];
    if (arrived.isEmpty) return const [];
    // Opening the same restaurant twice is still one visit: the first
    // recommendation gets it, and every candidate for that place is closed.
    final visited = <String, VisitCandidate>{};
    for (final c in arrived) {
      visited.putIfAbsent(c.spotId, () => c);
    }
    for (final c in visited.values) {
      _send(TelemetryEvent.recommendationVisit(
        spotId: c.spotId,
        userId: c.userId,
        eventId: 'visit-${c.eventId}',
      ));
    }
    await _storage.remove([
      for (final c in candidates)
        if (visited.containsKey(c.spotId)) c.eventId,
    ]);
    final spotIds = visited.keys.toList();
    onVisited?.call(spotIds);
    return spotIds;
  }

  /// Checks now and then every [checkEvery] while the app is in the
  /// foreground. The screen calls [stopWatching] when the app goes to the
  /// background: BQ9 never tracks the student with the app closed.
  void startWatching() {
    _timer?.cancel();
    _timer = Timer.periodic(checkEvery, (_) => _checkQuietly());
    _checkQuietly();
  }

  void stopWatching() {
    _timer?.cancel();
    _timer = null;
  }

  void _checkQuietly() {
    checkForVisits().catchError((Object e) {
      debugPrint("Couldn't check BQ9 visits: $e");
      return const <String>[];
    });
  }

  Future<LatLng?> _safePosition() async {
    try {
      return await _position();
    } catch (e) {
      debugPrint("Couldn't read the position for BQ9: $e");
      return null;
    }
  }

  static double _metersTo(LatLng here, VisitCandidate c) =>
      const Distance().as(LengthUnit.Meter, here, LatLng(c.latitude, c.longitude));
}
