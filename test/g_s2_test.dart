import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:campus_bites/data/spots_data.dart';
import 'package:campus_bites/models/food_preferences.dart';
import 'package:campus_bites/models/spot.dart';
import 'package:campus_bites/models/user_preferences.dart';
import 'package:campus_bites/models/wait_time.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/matches_repository.dart';
import 'package:campus_bites/repositories/wait_times_repository.dart';
import 'package:campus_bites/screens/change_password_screen.dart';
import 'package:campus_bites/screens/for_you_screen.dart';
import 'package:campus_bites/screens/taste_profile_screen.dart';
import 'package:campus_bites/screens/wait_times_screen.dart';
import 'package:campus_bites/services/auth_session.dart';
import 'package:campus_bites/services/popularity_loader.dart';
import 'package:campus_bites/services/preferences_service.dart';
import 'package:campus_bites/services/profile_prefs.dart';
import 'package:campus_bites/services/shake_detector.dart';
import 'package:campus_bites/services/shake_picker.dart';
import 'package:campus_bites/services/weather_context.dart';
import 'package:campus_bites/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _rain = WeatherNow(temperatureC: 14, precipitationMm: 1.2, weatherCode: 63);
const _clear = WeatherNow(temperatureC: 19, precipitationMm: 0, weatherCode: 1);

Map<String, dynamic> _openMeteo({double temp = 15.3, double rain = 0.0, int code = 3}) => {
      'latitude': 4.6,
      'longitude': -74.06,
      'current': {'time': '2026-10-28T12:00', 'interval': 900, 'temperature_2m': temp, 'precipitation': rain,
          'weather_code': code},
    };

/// "Popular right now" (Camilo) is not what these tests check: it answers empty.
class _FakePopular extends Fake implements PopularityLoader {
  @override
  Future<PopularityState> load({bool forceRefresh = false}) async => const PopularityEmpty(12);
}

class _FakeMatches extends Fake implements MatchesRepository {
  UserPreferences stored = const UserPreferences();
  bool offline = false;

  @override
  Future<UserPreferences> fetchPreferences(String userId) async => stored;

  @override
  Future<UserPreferences> savePreferences(String userId, UserPreferences preferences) async {
    if (offline) throw const ApiException(503);
    return stored = UserPreferences.fromJson({...preferences.toJson(), 'saved': true});
  }
}

/// The phone storage of Taste Profile (Camilo's ProfilePrefs).
class _PhonePrefs extends Fake implements ProfilePrefs {
  TastePreferences? taste;

  @override
  Future<TastePreferences?> readTaste() async => taste;

  @override
  Future<void> saveTaste(TastePreferences preferences) async => taste = preferences;
}

LastWaitTime _wait(String id, String name, {int? minutes, int? ago, bool recent = true, int reports = 1}) =>
    LastWaitTime(
      spotId: id,
      name: name,
      emoji: '🍽️',
      minutes: minutes,
      minutesAgo: ago,
      isRecent: minutes != null && recent,
      recentReports: minutes != null && recent ? reports : 0,
    );

class _FakeWaitTimes extends Fake implements WaitTimesRepository {
  final sent = <WaitReport>[];
  int failuresLeft = 0;

  @override
  Future<List<LastWaitTime>> fetchLatest() async => [
        _wait('conda-de-bons', 'Conda de Bons'),
        _wait('nitro-coffee', 'Nitro Coffee & Brew', minutes: 12, ago: 5, reports: 2),
        _wait('green-bowl-co', 'Green Bowl Co.', minutes: sent.isEmpty ? 25 : sent.last.minutes, ago: 0),
        _wait('el-vagon-street-food', 'El Vagón Street Food', minutes: 5, ago: 300, recent: false),
      ];

  @override
  Future<void> send(WaitReport report) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const ApiException(503);
    }
    sent.add(report);
  }
}

class _FakeSession extends Fake implements AuthSession {
  Object? error;
  final calls = <String>[];

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    calls.add('$currentPassword -> $newPassword');
    if (error case final e?) throw e;
  }
}

/// Controlled accelerometer and clock for the shake tests.
class _FakeSensor {
  final controller = StreamController<AccelerationReading>.broadcast(sync: true);
  DateTime now = DateTime(2026, 10, 28, 12);

  ShakeDetector detector() => ShakeDetector(readings: () => controller.stream, now: () => now);

  void move(double strength, {int afterMs = 0}) {
    now = now.add(Duration(milliseconds: afterMs));
    controller.add((x: strength, y: 0, z: 0));
  }
}

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  // ---------- f. External service: Open-Meteo ----------
  group('WeatherService (external service)', () {
    test('asks Open-Meteo for the campus weather, without the user token', () async {
      late http.Request request;
      final service = WeatherService(
        client: MockClient((r) async {
          request = r;
          return http.Response(jsonEncode(_openMeteo(code: 61, rain: 0.8)), 200);
        }),
      );

      final weather = await service.current();

      expect(request.url.host, 'api.open-meteo.com');
      expect(request.url.queryParameters['current'], 'temperature_2m,precipitation,weather_code');
      expect(request.url.queryParameters['latitude'], '${WeatherService.campusLat}');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(weather!.temperatureC, 15.3);
      expect(weather.isRaining, isTrue);
      expect(weather.label, '15° · Rain');
    });

    test('caches for 10 minutes and keeps the last weather if the service fails', () async {
      var calls = 0;
      var fail = false;
      var now = DateTime(2026, 10, 28, 12);
      final service = WeatherService(
        client: MockClient((_) async {
          calls++;
          if (fail) return http.Response('down', 503);
          return http.Response(jsonEncode(_openMeteo()), 200);
        }),
        now: () => now,
      );

      await service.current();
      await service.current();
      expect(calls, 1); // second time from the cache

      now = now.add(const Duration(minutes: 11));
      fail = true;
      final stale = await service.current();
      expect(calls, 2);
      expect(stale?.temperatureC, 15.3); // service down: last known weather instead of an error
    });

    test('no data and no connection -> null, the app works without weather', () async {
      final service = WeatherService(client: MockClient((_) async => throw http.ClientException('offline')));
      expect(await service.current(), isNull);
    });

    test('rain detection follows the WMO codes', () {
      expect(_rain.isRaining, isTrue);
      expect(_clear.isRaining, isFalse);
      expect(const WeatherNow(temperatureC: 15, precipitationMm: 0, weatherCode: 95).isRaining, isTrue); // storm
      expect(const WeatherNow(temperatureC: 15, precipitationMm: 0.4, weatherCode: 3).isRaining, isTrue); // measured
    });
  });

  // ---------- c. Context aware: the feed adapts to the weather ----------
  group('orderForWeather (context aware)', () {
    final feed = [
      sampleSpots.firstWhere((s) => s.id == 'taqueria-la-esquina'), // 6 min walk
      sampleSpots.firstWhere((s) => s.id == 'nitro-coffee'), // 2 min
      sampleSpots.firstWhere((s) => s.id == 'conda-de-bons'), // 5 min
    ];

    test('with rain the close places go first, keeping the match order inside each group', () {
      expect(orderForWeather(feed, _rain).map((s) => s.id), ['nitro-coffee', 'conda-de-bons', 'taqueria-la-esquina']);
      expect(weatherNote(_rain), contains('raining'));
    });

    test('without rain (or without data) nothing changes', () {
      expect(orderForWeather(feed, _clear), feed);
      expect(orderForWeather(feed, null), feed);
      expect(weatherNote(_clear), isNull);
    });
  });

  // ---------- a. Sensor: accelerometer ----------
  group('ShakeDetector (accelerometer)', () {
    test('two strong movements close together are one shake', () {
      final sensor = _FakeSensor();
      var shakes = 0;
      sensor.detector().start(() => shakes++);

      sensor.move(4); // walking with the phone: ignored
      sensor.move(18, afterMs: 100);
      expect(shakes, 0); // one peak is not a shake
      sensor.move(20, afterMs: 300);
      expect(shakes, 1);

      sensor.move(19, afterMs: 200);
      sensor.move(19, afterMs: 200);
      expect(shakes, 1); // cooldown: the same shake doesn't fire twice
    });

    test('peaks too far apart are not a shake, and stop() turns the sensor off', () {
      final sensor = _FakeSensor();
      var shakes = 0;
      final detector = sensor.detector()..start(() => shakes++);

      sensor.move(18);
      sensor.move(18, afterMs: 1500); // more than the 800 ms window
      expect(shakes, 0);

      detector.stop();
      expect(detector.isListening, isFalse);
      sensor.move(20, afterMs: 100);
      sensor.move(20, afterMs: 100);
      expect(shakes, 0);
    });
  });

  group('pickForShake', () {
    final feed = sampleSpots.take(5).toList();

    test('picks only from the first 3 places of the feed', () {
      for (var seed = 0; seed < 50; seed++) {
        final pick = pickForShake(feed, random: Random(seed));
        expect(feed.take(3), contains(pick));
      }
    });

    test('a place with a higher match comes out more often', () {
      final weighted = [
        feed[0].copyWith(affinityPercent: 90),
        feed[1].copyWith(affinityPercent: 10),
      ];
      final picks = [for (var seed = 0; seed < 400; seed++) pickForShake(weighted, random: Random(seed))!.id];
      expect(picks.where((id) => id == weighted[0].id).length, greaterThan(picks.length * 0.75));
      expect(pickForShake(const <Spot>[]), isNull);
    });
  });

  // ---------- d. Smart feature: backend contract ----------
  group('MatchesRepository', () {
    late http.Request request;
    late http.Response response;

    MatchesRepository repo() => MatchesRepository(
          baseUrl: 'http://api.test/api/v1',
          client: MockClient((r) async {
            request = r;
            return response;
          }),
        );

    test('fetchMatches reads the compatibility of each spot (smart feature)', () async {
      response = http.Response(
        jsonEncode([
          {'spotId': 'taqueria-la-esquina', 'compatibility': 94, 'dietaryConflict': null},
          {'spotId': 'nitro-coffee', 'compatibility': 45, 'dietaryConflict': null},
        ]),
        200,
      );
      expect(await repo().fetchMatches('u1'), {'taqueria-la-esquina': 94, 'nitro-coffee': 45});
      expect(request.url.path, '/api/v1/users/u1/matches');
    });

    test('savePreferences sends the whole object', () async {
      response = http.Response(jsonEncode({...const UserPreferences().toJson(), 'saved': true}), 200);
      await repo().savePreferences('u1', const UserPreferences(mainCuisine: 'Mexican', diet: 'Vegan'));
      expect(request.method, 'PUT');
      expect(jsonDecode(request.body)['mainCuisine'], 'Mexican');
      expect(jsonDecode(request.body)['diet'], 'Vegan');
    });
  });

  test('PreferencesService notifies when the student saves (the feed recalculates)', () async {
    final service = PreferencesService(repository: _FakeMatches(), currentUserId: () => 'u1');
    var notified = 0;
    service.addListener(() => notified++);
    await service.save(const UserPreferences(mainCuisine: 'Italian'));
    expect(service.current?.saved, isTrue);
    expect(notified, 1);
  });

  group('Taste Profile also goes to the backend (smart feature input)', () {
    Future<void> saveScreen(WidgetTester tester, Widget screen) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save preferences'));
      await tester.pumpAndSettle();
    }

    testWidgets('saves on the phone and on the backend', (tester) async {
      final phone = _PhonePrefs();
      final backend = _FakeMatches();
      final service = PreferencesService(repository: backend, currentUserId: () => 'u1');
      await saveScreen(tester, TasteProfileScreen(prefs: phone, preferences: service));

      expect(phone.taste, isNotNull);
      expect(backend.stored.saved, isTrue);
      expect(backend.stored.mainCuisine, phone.taste!.mainCuisine);
      expect(find.text('Taste profile saved. Your matches were updated.'), findsOneWidget);
      expect(find.text('open'), findsOneWidget); // the screen closed
    });

    testWidgets('without connection it stays saved on the phone and says so', (tester) async {
      final phone = _PhonePrefs();
      final backend = _FakeMatches()..offline = true;
      final service = PreferencesService(repository: backend, currentUserId: () => 'u1');
      await saveScreen(tester, TasteProfileScreen(prefs: phone, preferences: service));

      expect(phone.taste, isNotNull);
      expect(backend.stored.saved, isFalse);
      expect(find.textContaining("Saved on this phone, but your matches couldn't be updated"), findsOneWidget);
    });
  });

  // ---------- Screens ----------
  testWidgets('For You: calculated match, weather order and "Usual order"', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ForYouScreen(
          spots: sampleSpots,
          onToggleSaved: (_) {},
          popularLoader: _FakePopular(),
          // Taquería (6 min walk) is the best match; Poodle isn't saved, so its card shows the %.
          matchScores: const {'taqueria-la-esquina': 99, 'poodle-pizza-slices': 97},
          weather: _rain,
        ),
      ),
    ));

    expect(find.text('97%'), findsOneWidget); // calculated, the catalog said 95%
    expect(find.text('🌧️  14° · Rain on campus'), findsOneWidget);
    expect(find.textContaining("It's raining on campus"), findsOneWidget);
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    // Taquería has the best match but is 6 min away: with rain it goes after the close places.
    expect(top('La Esquina Burger Lab'), lessThan(top('Taquería La Esquina')));

    await tester.tap(find.text('Usual order'));
    await tester.pump();
    expect(top('Taquería La Esquina'), lessThan(top('La Esquina Burger Lab')));
    expect(find.textContaining("It's raining on campus"), findsNothing);
  });

  testWidgets('For You: shaking the phone suggests a place', (tester) async {
    final sensor = _FakeSensor();
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ForYouScreen(
          spots: sampleSpots,
          onToggleSaved: (_) {},
          popularLoader: _FakePopular(),
          onOpenSpot: opened.add,
          shakeDetector: sensor.detector(),
          shakeActive: true,
        ),
      ),
    ));
    expect(find.textContaining("Can't decide? Shake your phone"), findsOneWidget);

    sensor.move(20);
    sensor.move(20, afterMs: 250);
    await tester.pumpAndSettle();

    expect(find.text('🎲 How about...'), findsOneWidget);
    await tester.tap(find.text("Let's go"));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
  });

  // ---------- b. Type 2 BQ: BQ4 in Flutter ----------
  group('BQ4 wait times', () {
    test('WaitTimesRepository reads the last wait of each place', () async {
      late http.Request request;
      final repo = WaitTimesRepository(
        baseUrl: 'http://api.test/api/v1',
        client: MockClient((r) async {
          request = r;
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'question': 'What is the last reported waiting time for each restaurant?',
              'freshMinutes': 120,
              'spots': [
                {'spotId': 'nitro-coffee', 'name': 'Nitro Coffee & Brew', 'emoji': '☕', 'minutes': 12,
                    'reportedAt': '2026-10-29T15:00:00Z', 'minutesAgo': 5, 'isRecent': true, 'recentReports': 2},
                {'spotId': 'conda-de-bons', 'name': 'Conda de Bons', 'emoji': '🍔', 'minutes': null,
                    'reportedAt': null, 'minutesAgo': null, 'isRecent': false, 'recentReports': 0},
              ],
            })),
            200,
          );
        }),
      );

      final waits = await repo.fetchLatest();

      expect(request.url.path, '/api/v1/spots/wait-times/latest');
      expect(request.url.queryParameters['freshMinutes'], '120');
      expect(waits.first.detail, 'reported 5 min ago · 2 reports in the last 2 h');
      expect(waits.last.hasReport, isFalse);
    });

    test('a report keeps its id and time, so a retry is not a new report', () async {
      final bodies = <Map<String, dynamic>>[];
      final repo = WaitTimesRepository(
        baseUrl: 'http://api.test/api/v1',
        client: MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          expect(r.url.path, '/api/v1/spots/nitro-coffee/wait-times');
          return http.Response('{}', 201);
        }),
      );
      final report = WaitReport(spotId: 'nitro-coffee', minutes: 15);

      await repo.send(report);
      await repo.send(report);

      expect(bodies[0]['platform'], 'flutter');
      expect(bodies[0]['minutes'], 15);
      expect(bodies[0]['reportId'], bodies[1]['reportId']);
      expect(bodies[0]['reportedAt'], bodies[1]['reportedAt']);
    });

    test('order for deciding: recent from shortest, then old, then no reports', () {
      final sorted = sortForDecision([
        _wait('a', 'No report'),
        _wait('b', 'Old', minutes: 2, ago: 300, recent: false),
        _wait('c', 'Long line', minutes: 30, ago: 3),
        _wait('d', 'Short line', minutes: 8, ago: 10),
      ]);
      expect(sorted.map((w) => w.name), ['Short line', 'Long line', 'Old', 'No report']);
      expect(sorted[2].detail, 'old report (5 h ago)');
    });

    testWidgets('the screen shows the shortest wait and reporting updates it', (tester) async {
      final repo = _FakeWaitTimes();
      await tester.pumpWidget(MaterialApp(home: WaitTimesScreen(repository: repo, onOpenSpot: (_) {})));
      await tester.pumpAndSettle();

      expect(find.text('Shortest wait right now: 🍽️ Nitro Coffee & Brew, ~12 min.'), findsOneWidget);
      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(top('Nitro Coffee & Brew'), lessThan(top('Green Bowl Co.'))); // 12 min before 25 min
      expect(top('El Vagón Street Food'), greaterThan(top('Green Bowl Co.'))); // old report after recent ones

      await tester.tap(find.byTooltip('Report the wait here').at(1)); // Green Bowl's row
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 min'));
      await tester.pumpAndSettle();

      expect(repo.sent.single.spotId, 'green-bowl-co');
      expect(find.text('Shortest wait right now: 🍽️ Green Bowl Co., ~5 min.'), findsOneWidget);
    });

    testWidgets('if sending fails, Retry sends the same report', (tester) async {
      final repo = _FakeWaitTimes()..failuresLeft = 1;
      await tester.pumpWidget(MaterialApp(home: WaitTimesScreen(repository: repo, onOpenSpot: (_) {})));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Report the wait here').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('No line'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't send your report."), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      expect(repo.sent.single.minutes, 0);
    });
  });

  // ---------- e. Authentication: change password from the app ----------
  group('Change password screen', () {
    Future<void> openScreen(WidgetTester tester, _FakeSession session) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChangePasswordScreen(session: session)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, String current, String next, String confirm) async {
      await tester.enterText(find.byType(TextField).at(0), current);
      await tester.enterText(find.byType(TextField).at(1), next);
      await tester.enterText(find.byType(TextField).at(2), confirm);
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
    }

    testWidgets('checks the fields before calling the server', (tester) async {
      final session = _FakeSession();
      await openScreen(tester, session);
      await fill(tester, 'segura123', 'nueva12345', 'otra12345');
      expect(find.text("The new passwords don't match."), findsOneWidget);
      expect(session.calls, isEmpty);
    });

    testWidgets('a wrong current password shows the error and keeps the screen', (tester) async {
      final session = _FakeSession()..error = const ApiException(400);
      await openScreen(tester, session);
      await fill(tester, 'incorrecta', 'nueva12345', 'nueva12345');
      expect(find.text('Your current password is incorrect.'), findsOneWidget);
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
    });

    testWidgets('success sends both passwords and closes the screen', (tester) async {
      final session = _FakeSession();
      await openScreen(tester, session);
      await fill(tester, 'segura123', 'nueva12345', 'nueva12345');
      expect(session.calls, ['segura123 -> nueva12345']);
      expect(find.byType(ChangePasswordScreen), findsNothing);
    });
  });
}
