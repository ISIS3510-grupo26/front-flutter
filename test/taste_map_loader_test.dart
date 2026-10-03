import 'package:campus_bites/models/nearby_pick.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/recommendations_repository.dart';
import 'package:campus_bites/services/location_service.dart';
import 'package:campus_bites/services/taste_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class _FakeLocation implements LocationService {
  final LocationFailure? failure;

  const _FakeLocation({this.failure});

  @override
  Future<Position> getCurrentPosition() async {
    if (failure case final f?) throw LocationException(f);
    return Position(
      latitude: 4.65,
      longitude: -74.05,
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

class _FakeRecommendations extends Fake implements RecommendationsRepository {
  final Object? error;
  double? lastLat;
  double? lastLng;

  _FakeRecommendations({this.error});

  @override
  Future<List<NearbyPick>> fetchNearbyPicks({
    required String userId,
    required double lat,
    required double lng,
  }) async {
    if (error case final e?) throw e;
    lastLat = lat;
    lastLng = lng;
    return const [
      NearbyPick(
        id: 'nitro-coffee',
        name: 'Nitro Coffee & Brew',
        emoji: '☕',
        rating: 5.0,
        latitude: 4.6019,
        longitude: -74.0658,
        distanceMeters: 0,
        walkMinutes: 0,
      ),
    ];
  }
}

void main() {
  test('returns the picks for the device position', () async {
    final recommendations = _FakeRecommendations();
    final loader = TasteMapLoader(
      location: const _FakeLocation(),
      recommendations: recommendations,
      currentUserId: () => 'u1',
    );

    final state = await loader.load();
    expect(state, isA<TasteMapLoaded>());
    final loaded = state as TasteMapLoaded;
    expect(loaded.picks.single.id, 'nitro-coffee');
    expect(loaded.usedFallback, isFalse);
    expect(loaded.userLat, 4.65);
    expect(loaded.userLng, -74.05);
    expect(recommendations.lastLat, 4.65);
    expect(recommendations.lastLng, -74.05);
  });

  test('falls back to the campus center when location is denied', () async {
    final recommendations = _FakeRecommendations();
    final loader = TasteMapLoader(
      location: const _FakeLocation(failure: LocationFailure.permissionDenied),
      recommendations: recommendations,
      currentUserId: () => 'u1',
    );

    final loaded = await loader.load() as TasteMapLoaded;
    expect(loaded.usedFallback, isTrue);
    expect(loaded.userLat, TasteMapLoader.campusLat);
    expect(loaded.userLng, TasteMapLoader.campusLng);
    expect(recommendations.lastLat, TasteMapLoader.campusLat);
    expect(recommendations.lastLng, TasteMapLoader.campusLng);
    expect(loaded.picks, hasLength(1));
  });

  test('reports signed out when there is no user', () async {
    final loader = TasteMapLoader(
      location: const _FakeLocation(),
      recommendations: _FakeRecommendations(),
      currentUserId: () => null,
    );

    final state = await loader.load();
    expect((state as TasteMapFailed).reason, TasteMapFailure.signedOut);
  });

  test('reports a network failure when the API call fails', () async {
    final loader = TasteMapLoader(
      location: const _FakeLocation(),
      recommendations: _FakeRecommendations(error: const ApiException(500)),
      currentUserId: () => 'u1',
    );

    final state = await loader.load();
    expect((state as TasteMapFailed).reason, TasteMapFailure.network);
  });
}
