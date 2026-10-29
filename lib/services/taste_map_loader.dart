import 'package:flutter/foundation.dart';

import '../models/nearby_pick.dart';
import 'local_database.dart';
import 'lru_cache.dart';
import 'location_service.dart';
import 'recommendations_service_adapter.dart';
import 'taste_map_prefs.dart';

enum TasteMapFailure { signedOut, network }

sealed class TasteMapState {
  const TasteMapState();
}

final class TasteMapLoading extends TasteMapState {
  const TasteMapLoading();
}

final class TasteMapFailed extends TasteMapState {
  final TasteMapFailure reason;

  const TasteMapFailed(this.reason);
}

final class TasteMapLoaded extends TasteMapState {
  final List<NearbyPick> picks;
  final double userLat;
  final double userLng;

  /// True when the device position was unavailable and the picks are measured
  /// from the campus center instead.
  final bool usedFallback;

  /// True when the picks came from the LRU cache instead of the network.
  final bool fromCache;

  /// Set when the network failed and these are the picks saved on the phone
  /// at that time; null when they are fresh.
  final DateTime? offlineSavedAt;

  const TasteMapLoaded({
    required this.picks,
    required this.userLat,
    required this.userLng,
    required this.usedFallback,
    this.fromCache = false,
    this.offlineSavedAt,
  });
}

/// Finds the nearest highest-rated spots the current user hasn't tried yet.
/// Unlike the saved-places map, a missing location is not a failure: the
/// campus center is used instead.
class TasteMapLoader {
  static const campusLat = 4.6018;
  static const campusLng = -74.0661;

  final LocationService _location;
  final RecommendationsService _recommendations;
  final String? Function() _currentUserId;
  final LruCache<String, List<NearbyPick>> _cache;
  final TasteMapStorage _storage;
  final TasteMapPrefs _prefs;

  TasteMapLoader({
    this._location = const LocationService(),
    required this._recommendations,
    required this._currentUserId,
    required this._storage,
    required this._prefs,
    LruCache<String, List<NearbyPick>>? cache,
  }) : _cache = cache ?? LruCache(capacity: 8, ttl: const Duration(minutes: 5));

  /// Cache key: the user plus the position rounded to 3 decimals (about
  /// 110 m), so small GPS jitter still hits the same entry.
  static String cacheKey(String userId, double lat, double lng) =>
      '$userId@${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';

  /// Multithreading strategy: async/await. Location, network and parsing
  /// (which runs in an isolate) are awaited without blocking the UI thread.
  /// A recent result for the same spot comes from the LRU cache unless
  /// [forceRefresh] is true (the refresh button).
  Future<TasteMapState> load({bool forceRefresh = false}) async {
    final userId = _currentUserId();
    if (userId == null) return const TasteMapFailed(TasteMapFailure.signedOut);

    var lat = campusLat;
    var lng = campusLng;
    var usedFallback = false;
    try {
      final position = await _location.getCurrentPosition();
      lat = position.latitude;
      lng = position.longitude;
    } on LocationException {
      usedFallback = true;
    }

    final key = cacheKey(userId, lat, lng);
    if (!forceRefresh) {
      if (_cache.get(key) case final cached?) {
        return TasteMapLoaded(
          picks: cached,
          userLat: lat,
          userLng: lng,
          usedFallback: usedFallback,
          fromCache: true,
        );
      }
    }

    try {
      final picks = await _recommendations.nearbyPicks(
        userId: userId,
        lat: lat,
        lng: lng,
      );
      _cache.put(key, picks);
      _saveForOffline(picks, lat, lng);
      return TasteMapLoaded(
        picks: picks,
        userLat: lat,
        userLng: lng,
        usedFallback: usedFallback,
      );
    } catch (_) {
      return _loadSaved();
    }
  }

  /// Multithreading strategy: Future with handler. Saving for offline use is
  /// fire-and-forget with .then()/.catchError(): the map shows the picks
  /// right away and never waits for the disk. If a write fails, only the
  /// offline copy is lost.
  void _saveForOffline(List<NearbyPick> picks, double lat, double lng) {
    _storage
        .savePicks(picks)
        .then((_) => _prefs.save(syncedAt: DateTime.now(), lat: lat, lng: lng))
        .catchError((Object e) => debugPrint("Couldn't save the Taste Map offline: $e"));
  }

  /// Eventual connectivity: without network, the last picks saved in SQLite,
  /// centered where the student was (preferences). Only with nothing saved
  /// is it a network failure.
  Future<TasteMapState> _loadSaved() async {
    try {
      final picks = await _storage.readPicks();
      final last = await _prefs.read();
      if (picks.isNotEmpty && last != null) {
        return TasteMapLoaded(
          picks: picks,
          userLat: last.lat,
          userLng: last.lng,
          usedFallback: false,
          offlineSavedAt: last.syncedAt,
        );
      }
    } catch (e) {
      debugPrint("Couldn't read the offline Taste Map: $e");
    }
    return const TasteMapFailed(TasteMapFailure.network);
  }
}
