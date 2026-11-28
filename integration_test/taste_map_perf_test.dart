// Micro-optimization evidence (Sprint 4). Run in profile mode on a phone or emulator:
//
//   flutter drive --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/taste_map_perf_test.dart
//
// It opens the Taste Map with 18 picks and taps every pin twice while the
// Flutter timeline is recorded. The driver writes the timeline and its summary
// (frame build and raster times) to build/, and the copies kept for the wiki
// are in docs/profiling/.
import 'package:campus_bites/models/nearby_pick.dart';
import 'package:campus_bites/screens/taste_map_screen.dart';
import 'package:campus_bites/services/local_database.dart';
import 'package:campus_bites/services/location_service.dart';
import 'package:campus_bites/services/recommendations_service_adapter.dart';
import 'package:campus_bites/services/taste_map_loader.dart';
import 'package:campus_bites/services/taste_map_prefs.dart';
import 'package:campus_bites/services/telemetry_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

const _campusLat = 4.6018;
const _campusLng = -74.0661;

/// 18 picks in a 3 x 6 grid around the campus center, far enough apart that
/// every pin can be tapped at zoom 17. Each one has a different rating, so
/// the text on its pin ("★ 4.21") finds it.
final picks = [
  for (var row = 0; row < 6; row++)
    for (var col = 0; col < 3; col++)
      NearbyPick(
        id: 'spot-$row-$col',
        name: 'Spot $row-$col',
        emoji: '🍔',
        rating: 4 + (row * 3 + col + 1) / 100,
        latitude: _campusLat - 0.0015 + row * 0.0006,
        longitude: _campusLng + (col - 1) * 0.0013,
        distanceMeters: 100 + row * 20,
        walkMinutes: 2 + row,
      ),
];

class _CampusLocation implements LocationService {
  const _CampusLocation();

  @override
  Future<Position> getCurrentPosition() async => Position(
        latitude: _campusLat,
        longitude: _campusLng,
        timestamp: DateTime(2026),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  @override
  Future<bool> openSettings() async => true;
}

class _FixedPicks implements RecommendationsService {
  @override
  Future<List<NearbyPick>> nearbyPicks({required String userId, required double lat, required double lng}) async =>
      picks;
}

class _MemoryPicks implements TasteMapStorage {
  List<NearbyPick> saved = const [];

  @override
  Future<List<NearbyPick>> readPicks() async => saved;

  @override
  Future<void> savePicks(List<NearbyPick> p) async => saved = p;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Taste Map: tapping every pin', (tester) async {
    final telemetry = TelemetryQueue(
      client: MockClient((_) async => http.Response('{"accepted":0,"duplicates":0}', 202)),
      loadDevice: () async => const DeviceContext(model: 'perf', osVersion: '16'),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TasteMapScreen(
          loader: TasteMapLoader(
            location: const _CampusLocation(),
            recommendations: _FixedPicks(),
            currentUserId: () => 'perf-user',
            storage: _MemoryPicks(),
            prefs: TasteMapPrefs(),
          ),
          telemetry: telemetry,
          currentUserId: () => 'perf-user',
        ),
      ),
    ));
    // Wait for the picks (up to 15 s), then 2 s more for the map tiles, so
    // nothing is loading while the taps are measured.
    final firstPin = find.text('★ ${picks.first.rating}');
    for (var i = 0; i < 150 && firstPin.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(firstPin, findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> tapEveryPin() async {
      for (var round = 0; round < 2; round++) {
        for (final pick in picks) {
          await tester.tap(find.text('★ ${pick.rating}'), warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
    }

    // 1) Frame times, without extra instrumentation.
    await binding.traceAction(tapEveryPin, reportKey: 'taste_map_pin_taps');

    // 2) The same taps with every widget build in the timeline, to count
    //    which widgets rebuild on each tap.
    widgets.debugProfileBuildsEnabled = true;
    await binding.traceAction(tapEveryPin, reportKey: 'taste_map_pin_taps_builds');
    widgets.debugProfileBuildsEnabled = false;

    telemetry.dispose();
  });
}
