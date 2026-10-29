import 'package:campus_bites/models/nearby_pick.dart';
import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/services/map_display_event.dart';
import 'package:campus_bites/services/taste_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';

const _userLat = 4.6018;
const _userLng = -74.0661;

NearbyPick _pick(double lat, double lng) => NearbyPick(
      id: 'p',
      name: 'Pick',
      emoji: '🍔',
      rating: 4.5,
      latitude: lat,
      longitude: lng,
      distanceMeters: 100,
      walkMinutes: 2,
    );

TasteMapLoaded _loaded(List<NearbyPick> picks, {bool usedFallback = false}) => TasteMapLoaded(
      picks: picks,
      userLat: _userLat,
      userLng: _userLng,
      usedFallback: usedFallback,
    );

void main() {
  final nearby = _pick(4.6025, -74.0650);

  test('a load that failed is load_failed', () {
    expect(mapDisplayErrorType(const TasteMapFailed(TasteMapFailure.network)), 'load_failed');
  });

  test('picks measured from campus because location was off are location_fallback', () {
    expect(mapDisplayErrorType(_loaded([nearby], usedFallback: true)), 'location_fallback');
  });

  test('every pin where it should be is a success', () {
    expect(mapDisplayErrorType(_loaded([nearby])), isNull);
    expect(mapDisplayErrorType(_loaded(const [])), isNull);
  });

  group('invalid_coordinates', () {
    for (final (name, pick) in [
      ('latitude out of range', _pick(91, -74.06)),
      ('longitude out of range', _pick(4.6, -181)),
      ('0,0', _pick(0, 0)),
      ('more than 5 km away (Medellín)', _pick(6.2442, -75.5812)),
    ]) {
      test(name, () {
        expect(hasValidCoordinates(pick, _userLat, _userLng), isFalse);
        expect(mapDisplayErrorType(_loaded([nearby, pick])), 'invalid_coordinates');
      });
    }

    test('a pin 4 km away is still valid', () {
      final northOfCampus = _pick(_userLat + 0.036, _userLng); // ~4 km
      expect(hasValidCoordinates(northOfCampus, _userLat, _userLng), isTrue);
    });
  });

  test('the event uses screen map_display and survives toJson/fromJson', () {
    final event = TelemetryEvent.mapDisplay(
      userId: 'u1',
      success: false,
      errorType: 'tiles_failed',
      durationMs: 420,
    );
    final copy = TelemetryEvent.fromJson(event.toJson());

    expect(event.screen, 'map_display');
    expect(event.spotId, isNull);
    expect(copy.toJson(), event.toJson());
  });
}
