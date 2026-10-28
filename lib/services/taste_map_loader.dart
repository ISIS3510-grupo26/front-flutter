import '../models/nearby_pick.dart';
import 'lru_cache.dart';
import 'location_service.dart';
import 'recommendations_service_adapter.dart';

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

  const TasteMapLoaded({
    required this.picks,
    required this.userLat,
    required this.userLng,
    required this.usedFallback,
    this.fromCache = false,
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

  TasteMapLoader({
    this._location = const LocationService(),
    required this._recommendations,
    required this._currentUserId,
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
      return TasteMapLoaded(
        picks: picks,
        userLat: lat,
        userLng: lng,
        usedFallback: usedFallback,
      );
    } catch (_) {
      return const TasteMapFailed(TasteMapFailure.network);
    }
  }
}
