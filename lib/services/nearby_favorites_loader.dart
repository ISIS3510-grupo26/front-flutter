import '../repositories/favorites_repository.dart';
import 'location_service.dart';

enum NearbyFailure { signedOut, locationOff, locationDenied, locationBlocked, network }

sealed class NearbyState {
  const NearbyState();
}

final class NearbyLoading extends NearbyState {
  const NearbyLoading();
}

final class NearbyFailed extends NearbyState {
  final NearbyFailure failure;

  const NearbyFailed(this.failure);
}

final class NearbyLoaded extends NearbyState {
  /// Walk minutes keyed by spot id, for saved spots that are open now.
  final Map<String, int> walkMinutes;

  const NearbyLoaded(this.walkMinutes);
}

/// Finds the current user's saved spots that are open now and within
/// [maxWalkMinutes] of the device.
class NearbyFavoritesLoader {
  static const maxWalkMinutes = 15;

  final LocationService _location;
  final FavoritesRepository _favorites;
  final String? Function() _currentUserId;

  NearbyFavoritesLoader({
    this._location = const LocationService(),
    required this._favorites,
    required this._currentUserId,
  });

  Future<NearbyState> load() async {
    final userId = _currentUserId();
    if (userId == null) return const NearbyFailed(NearbyFailure.signedOut);

    try {
      final position = await _location.getCurrentPosition();
      final results = await _favorites.fetchOpenNearby(
        userId: userId,
        lat: position.latitude,
        lng: position.longitude,
        maxWalkMinutes: maxWalkMinutes,
      );
      return NearbyLoaded({for (final r in results) r.id: r.walkMinutes});
    } on LocationException catch (e) {
      return NearbyFailed(switch (e.reason) {
        LocationFailure.serviceDisabled => NearbyFailure.locationOff,
        LocationFailure.permissionDenied => NearbyFailure.locationDenied,
        LocationFailure.permissionDeniedForever => NearbyFailure.locationBlocked,
      });
    } catch (_) {
      return const NearbyFailed(NearbyFailure.network);
    }
  }

  Future<bool> openLocationSettings() => _location.openSettings();
}
