import 'package:campus_bites/models/nearby_pick.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/services/local_database.dart';
import 'package:campus_bites/services/location_service.dart';
import 'package:campus_bites/services/lru_cache.dart';
import 'package:campus_bites/services/recommendations_service_adapter.dart';
import 'package:campus_bites/services/taste_map_loader.dart';
import 'package:campus_bites/services/taste_map_prefs.dart';
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

class _FakeRecommendations implements RecommendationsService {
  Object? error;
  double? lastLat;
  double? lastLng;
  int calls = 0;

  _FakeRecommendations({this.error});

  @override
  Future<List<NearbyPick>> nearbyPicks({
    required String userId,
    required double lat,
    required double lng,
  }) async {
    calls++;
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

class _MemoryPicks implements TasteMapStorage {
  List<NearbyPick> picks = [];

  @override
  Future<void> savePicks(List<NearbyPick> picks) async => this.picks = picks;

  @override
  Future<List<NearbyPick>> readPicks() async => picks;
}

class _MemoryPrefs extends Fake implements TasteMapPrefs {
  ({DateTime syncedAt, double lat, double lng})? last;

  @override
  Future<void> save({
    required DateTime syncedAt,
    required double lat,
    required double lng,
  }) async => last = (syncedAt: syncedAt, lat: lat, lng: lng);

  @override
  Future<({DateTime syncedAt, double lat, double lng})?> read() async => last;
}

void main() {
  test('returns the picks for the device position', () async {
    final recommendations = _FakeRecommendations();
    final loader = TasteMapLoader(
      location: const _FakeLocation(),
      recommendations: recommendations,
      currentUserId: () => 'u1',
      storage: _MemoryPicks(),
      prefs: _MemoryPrefs(),
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
      storage: _MemoryPicks(),
      prefs: _MemoryPrefs(),
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
      storage: _MemoryPicks(),
      prefs: _MemoryPrefs(),
    );

    final state = await loader.load();
    expect((state as TasteMapFailed).reason, TasteMapFailure.signedOut);
  });

  group('offline', () {
    late _FakeRecommendations recommendations;
    late _MemoryPicks storage;
    late _MemoryPrefs prefs;
    late TasteMapLoader loader;

    setUp(() {
      recommendations = _FakeRecommendations();
      storage = _MemoryPicks();
      prefs = _MemoryPrefs();
      loader = TasteMapLoader(
        location: const _FakeLocation(),
        recommendations: recommendations,
        currentUserId: () => 'u1',
        storage: storage,
        prefs: prefs,
      );
    });

    test('a successful load saves the picks and where they were loaded', () async {
      final loaded = await loader.load() as TasteMapLoaded;
      await pumpEventQueue();

      expect(loaded.offlineSavedAt, isNull);
      expect(storage.picks.single.id, 'nitro-coffee');
      expect((prefs.last!.lat, prefs.last!.lng), (4.65, -74.05));
    });

    test('without network it shows the saved picks and when they were saved', () async {
      final savedAt = DateTime(2026, 10, 27, 9, 30);
      storage.picks = const [
        NearbyPick(
          id: 'green-bowl-co',
          name: 'Green Bowl Co.',
          emoji: '🥗',
          rating: 4.8,
          latitude: 4.6025,
          longitude: -74.0650,
          distanceMeters: 120,
          walkMinutes: 2,
        ),
      ];
      prefs.last = (syncedAt: savedAt, lat: 4.6018, lng: -74.0661);
      recommendations.error = const ApiException(503);

      final offline = await loader.load() as TasteMapLoaded;

      expect(offline.offlineSavedAt, savedAt);
      expect(offline.picks.single.id, 'green-bowl-co');
      expect((offline.userLat, offline.userLng), (4.6018, -74.0661));
      expect(offline.fromCache, isFalse);
    });

    test('without network and nothing saved it is a network failure', () async {
      recommendations.error = const ApiException(503);

      final state = await loader.load();

      expect((state as TasteMapFailed).reason, TasteMapFailure.network);
    });
  });

  test('reports a network failure when the API call fails', () async {
    final loader = TasteMapLoader(
      location: const _FakeLocation(),
      recommendations: _FakeRecommendations(error: const ApiException(500)),
      currentUserId: () => 'u1',
      storage: _MemoryPicks(),
      prefs: _MemoryPrefs(),
    );

    final state = await loader.load();
    expect((state as TasteMapFailed).reason, TasteMapFailure.network);
  });

  group('LRU cache', () {
    late _FakeRecommendations recommendations;
    late DateTime now;
    late TasteMapLoader loader;

    setUp(() {
      recommendations = _FakeRecommendations();
      now = DateTime(2026, 10, 27, 12);
      loader = TasteMapLoader(
        location: const _FakeLocation(),
        recommendations: recommendations,
        currentUserId: () => 'u1',
        storage: _MemoryPicks(),
        prefs: _MemoryPrefs(),
        cache: LruCache(capacity: 8, ttl: const Duration(minutes: 5), now: () => now),
      );
    });

    test('the same position within the ttl does not call the service again', () async {
      final first = await loader.load() as TasteMapLoaded;
      now = now.add(const Duration(minutes: 4));
      final second = await loader.load() as TasteMapLoaded;

      expect(recommendations.calls, 1);
      expect(first.fromCache, isFalse);
      expect(second.fromCache, isTrue);
      expect(second.picks.single.id, 'nitro-coffee');
      expect((second.userLat, second.userLng), (4.65, -74.05));
    });

    test('after the ttl the service is called again', () async {
      await loader.load();
      now = now.add(const Duration(minutes: 6));
      final second = await loader.load() as TasteMapLoaded;

      expect(recommendations.calls, 2);
      expect(second.fromCache, isFalse);
    });

    test('forceRefresh skips the cache', () async {
      await loader.load();
      final refreshed = await loader.load(forceRefresh: true) as TasteMapLoaded;

      expect(recommendations.calls, 2);
      expect(refreshed.fromCache, isFalse);
    });

    test('a failed call is not cached', () async {
      recommendations.error = const ApiException(500);
      await loader.load();
      recommendations.error = null;
      await loader.load();

      expect(recommendations.calls, 2);
    });
  });

  test('the cache key rounds the position to 3 decimals', () {
    expect(
      TasteMapLoader.cacheKey('u1', 4.60184, -74.06612),
      TasteMapLoader.cacheKey('u1', 4.60176, -74.06608),
    );
    expect(
      TasteMapLoader.cacheKey('u1', 4.6018, -74.0661),
      isNot(TasteMapLoader.cacheKey('u1', 4.6030, -74.0661)),
    );
  });
}
