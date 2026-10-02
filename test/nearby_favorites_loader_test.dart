import 'package:campus_bites/models/nearby_favorite.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/favorites_repository.dart';
import 'package:campus_bites/services/location_service.dart';
import 'package:campus_bites/services/nearby_favorites_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class _FakeLocation implements LocationService {
  final LocationFailure? failure;

  const _FakeLocation({this.failure});

  @override
  Future<Position> getCurrentPosition() async {
    if (failure case final f?) throw LocationException(f);
    return Position(
      latitude: 4.6,
      longitude: -74.06,
      timestamp: DateTime(2026),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Future<bool> openSettings() async => true;
}

class _FakeFavorites extends Fake implements FavoritesRepository {
  final Object? error;

  _FakeFavorites({this.error});

  @override
  Future<List<NearbyFavorite>> fetchOpenNearby({
    required String userId,
    required double lat,
    required double lng,
    int maxWalkMinutes = 15,
  }) async {
    if (error case final e?) throw e;
    return const [NearbyFavorite(id: 'green-bowl-co', walkMinutes: 4)];
  }
}

NearbyFavoritesLoader _loader({
  String? userId = 'u1',
  LocationFailure? locationFailure,
  Object? apiError,
}) =>
    NearbyFavoritesLoader(
      location: _FakeLocation(failure: locationFailure),
      favorites: _FakeFavorites(error: apiError),
      currentUserId: () => userId,
    );

void main() {
  test('returns walk minutes keyed by spot id', () async {
    final state = await _loader().load();
    expect(state, isA<NearbyLoaded>());
    expect((state as NearbyLoaded).walkMinutes, {'green-bowl-co': 4});
  });

  test('reports signed out when there is no user', () async {
    final state = await _loader(userId: null).load();
    expect((state as NearbyFailed).failure, NearbyFailure.signedOut);
  });

  test('maps each location failure', () async {
    const expected = {
      LocationFailure.serviceDisabled: NearbyFailure.locationOff,
      LocationFailure.permissionDenied: NearbyFailure.locationDenied,
      LocationFailure.permissionDeniedForever: NearbyFailure.locationBlocked,
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      final state = await _loader(locationFailure: key).load();
      expect((state as NearbyFailed).failure, value, reason: '$key');
    }
  });

  test('reports a network failure when the API call fails', () async {
    final state = await _loader(apiError: const ApiException(500)).load();
    expect((state as NearbyFailed).failure, NearbyFailure.network);
  });
}
