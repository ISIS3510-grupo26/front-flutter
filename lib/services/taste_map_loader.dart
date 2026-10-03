import '../models/nearby_pick.dart';
import '../repositories/recommendations_repository.dart';
import 'location_service.dart';

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

  const TasteMapLoaded({
    required this.picks,
    required this.userLat,
    required this.userLng,
    required this.usedFallback,
  });
}

/// Finds the nearest highest-rated spots the current user hasn't tried yet.
/// Unlike the saved-places map, a missing location is not a failure: the
/// campus center is used instead.
class TasteMapLoader {
  static const campusLat = 4.6018;
  static const campusLng = -74.0661;

  final LocationService _location;
  final RecommendationsRepository _recommendations;
  final String? Function() _currentUserId;

  TasteMapLoader({
    this._location = const LocationService(),
    required this._recommendations,
    required this._currentUserId,
  });

  Future<TasteMapState> load() async {
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

    try {
      final picks = await _recommendations.fetchNearbyPicks(
        userId: userId,
        lat: lat,
        lng: lng,
      );
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
