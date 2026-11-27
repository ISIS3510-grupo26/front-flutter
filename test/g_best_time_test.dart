import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campus_bites/models/best_time.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/screens/best_time_screen.dart';
import 'package:campus_bites/services/best_time_loader.dart';
import 'package:campus_bites/services/best_time_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// What the backend answers (camelCase, like every endpoint).
Map<String, dynamic> _json({int days = 7, int totalReports = 9}) => {
      'question': 'At what time of the day is the reported waiting time at each restaurant the shortest?',
      'days': days,
      'tzOffsetMinutes': -300,
      'minReports': 2,
      'totalReports': totalReports,
      'byHour': [
        {'hour': 8, 'avgMinutes': 6.5, 'reports': 2},
        {'hour': 12, 'avgMinutes': 21.0, 'reports': 4},
        {'hour': 15, 'avgMinutes': 3.0, 'reports': 2},
        {'hour': 18, 'avgMinutes': 1.0, 'reports': 1},
      ],
      'spots': [
        {
          'spotId': 'nitro-coffee',
          'name': 'Nitro Coffee',
          'emoji': '☕',
          'reports': 5,
          'bestHour': 8,
          'bestHourAvgMinutes': 6.5,
          'worstHour': 12,
          'worstHourAvgMinutes': 18,
          'byHour': [
            {'hour': 8, 'avgMinutes': 6.5, 'reports': 2},
            {'hour': 12, 'avgMinutes': 18, 'reports': 3},
          ],
        },
        {
          'spotId': 'green-bowl-co',
          'name': 'Green Bowl Co.',
          'emoji': '🥗',
          'reports': 4,
          'bestHour': 15,
          'bestHourAvgMinutes': 3.0,
          'worstHour': 15,
          'worstHourAvgMinutes': 3.0,
          'byHour': [
            {'hour': 12, 'avgMinutes': 30.0, 'reports': 1},
            {'hour': 15, 'avgMinutes': 3.0, 'reports': 2},
            {'hour': 18, 'avgMinutes': 1.0, 'reports': 1},
          ],
        },
        {
          'spotId': 'arepa-house',
          'name': 'Arepa House',
          'emoji': '🫓',
          'reports': 0,
          'bestHour': null,
          'bestHourAvgMinutes': null,
          'worstHour': null,
          'worstHourAvgMinutes': null,
          'byHour': [],
        },
      ],
    };

BestTimeReport _report({int days = 7, int totalReports = 9}) =>
    BestTimeReport.fromJson(_json(days: days, totalReports: totalReports));

class _FakeService implements BestTimeService {
  final calls = <int>[];
  Object? error;

  @override
  Future<BestTimeReport> report({required int days, required int tzOffsetMinutes}) async {
    calls.add(days);
    if (error case final e?) throw e;
    return _report(days: days);
  }
}

class _MemoryStorage implements BestTimeStorage {
  final saved = <int, ({BestTimeReport report, DateTime savedAt})>{};

  @override
  Future<void> saveBestTimes(BestTimeReport report, {required DateTime savedAt}) async =>
      saved[report.days] = (report: report, savedAt: savedAt);

  @override
  Future<({BestTimeReport report, DateTime savedAt})?> readBestTimes(int days) async => saved[days];
}

void main() {
  group('BestTimeReport', () {
    test('reads the backend JSON, also whole numbers as averages', () {
      final report = _report();
      expect(report.days, 7);
      expect(report.minReports, 2);
      expect(report.spots, hasLength(3));
      final coffee = report.spots.first;
      expect(coffee.bestHour, 8);
      expect(coffee.worstAvgMinutes, 18.0);
      expect(coffee.at(12)?.reports, 3);
      expect(coffee.at(9), isNull);
      expect(report.spots.last.hasBestHour, isFalse);
    });

    test('the calmest campus hour ignores hours with fewer reports than minReports', () {
      // 18 h has 1 min but only 1 report, so 15 h (3 min, 2 reports) wins.
      expect(_report().calmestHour?.hour, 15);
    });

    test('restaurants with a best hour go first, from the shortest wait; the rest by name', () {
      expect([for (final s in _report().spotsForDecision) s.spotId], ['green-bowl-co', 'nitro-coffee', 'arepa-house']);
    });

    test('the worst hour is not shown when it is the same as the best one', () {
      final spots = _report().spots;
      expect(spots[0].hasWorstHour, isTrue);
      expect(spots[1].hasWorstHour, isFalse);
    });

    test('hourLabel', () {
      expect([hourLabel(0), hourLabel(8), hourLabel(12), hourLabel(15)], ['12 AM', '8 AM', '12 PM', '3 PM']);
    });

    test('parseBestTimeReport reads the response bytes (what the isolate receives)', () {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(_json())));
      expect(parseBestTimeReport(bytes).spots.first.name, 'Nitro Coffee');
    });
  });

  group('BestTimeServiceAdapter', () {
    test('asks for the window, the phone time zone and minReports = 2', () async {
      late Uri asked;
      final adapter = BestTimeServiceAdapter(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response.bytes(utf8.encode(jsonEncode(_json(days: 28))), 200);
        }),
        baseUrl: 'http://test/api/v1',
      );
      final report = await adapter.report(days: 28, tzOffsetMinutes: -300);
      expect(asked.path, '/api/v1/analytics/best-time-to-go');
      expect(asked.queryParameters, {'days': '28', 'tzOffsetMinutes': '-300', 'minReports': '2'});
      expect(report.days, 28);
    });

    test('another status is an ApiException', () async {
      final adapter = BestTimeServiceAdapter(
        client: MockClient((_) async => http.Response('oops', 500)),
        baseUrl: 'http://test/api/v1',
      );
      await expectLater(adapter.report(days: 7, tzOffsetMinutes: -300), throwsA(isA<ApiException>()));
    });
  });

  group('BestTimeLoader', () {
    late _FakeService service;
    late _MemoryStorage storage;
    late DateTime now;
    late BestTimeLoader loader;

    setUp(() {
      service = _FakeService();
      storage = _MemoryStorage();
      now = DateTime(2026, 11, 27, 11);
      loader = BestTimeLoader(service: service, storage: storage, now: () => now);
    });

    test('a second load of the same window comes from the LRU cache', () async {
      await loader.load(days: 7);
      final again = await loader.load(days: 7);
      expect(again, isA<BestTimeLoaded>());
      expect(service.calls, [7]);
    });

    test('each window has its own entry, and both fit', () async {
      await loader.load(days: 7);
      await loader.load(days: 28);
      await loader.load(days: 7);
      await loader.load(days: 28);
      expect(service.calls, [7, 28]);
    });

    test('after 10 minutes, or with forceRefresh, it asks the backend again', () async {
      await loader.load(days: 7);
      await loader.load(days: 7, forceRefresh: true);
      now = now.add(const Duration(minutes: 11));
      await loader.load(days: 7);
      expect(service.calls, [7, 7, 7]);
    });

    test('saves a copy for offline, and without network shows it with when it was saved', () async {
      await loader.load(days: 7);
      await Future<void>.delayed(Duration.zero); // the save is not awaited by load()
      expect(storage.saved[7]?.savedAt, now);

      final offline = BestTimeLoader(service: service..error = const SocketException('no signal'), storage: storage);
      final state = await offline.load(days: 7);
      expect(state, isA<BestTimeLoaded>());
      expect((state as BestTimeLoaded).offlineSavedAt, now);
    });

    test('without network and nothing saved it is a network failure', () async {
      service.error = http.ClientException('no signal');
      final state = await loader.load(days: 28);
      expect(state, isA<BestTimeFailed>());
      expect((state as BestTimeFailed).reason, BestTimeFailure.network);
    });

    test('a server error is not hidden behind the saved copy', () async {
      await storage.saveBestTimes(_report(), savedAt: now);
      service.error = const ApiException(500);
      final state = await loader.load(days: 7);
      expect((state as BestTimeFailed).reason, BestTimeFailure.server);
    });
  });

  group('BestTimeScreen', () {
    Future<_FakeService> open(
      WidgetTester tester, {
      _FakeService? service,
      _MemoryStorage? storage,
      Stream<List<ConnectivityResult>> connection = const Stream.empty(),
      List<String>? opened,
    }) async {
      final s = service ?? _FakeService();
      // A tall phone, so every card is built and the finders see it.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: BestTimeScreen(
          loader: BestTimeLoader(service: s, storage: storage ?? _MemoryStorage()),
          onOpenSpot: (id) => opened?.add(id),
          connectionChanges: connection,
          now: () => DateTime(2026, 11, 27, 12),
        ),
      ));
      await tester.pumpAndSettle();
      return s;
    }

    testWidgets('shows the calmest hour and the best and worst hour of each restaurant', (tester) async {
      await open(tester);
      expect(find.textContaining('Calmest hour on campus: 3 PM'), findsOneWidget);
      expect(find.text('Go at 8 AM · ~7 min'), findsOneWidget);
      expect(find.text('Avoid 12 PM · ~18 min'), findsOneWidget);
      expect(find.text('Go at 3 PM · ~3 min'), findsOneWidget);
      expect(find.text('Usually at this hour (12 PM): ~18 min'), findsOneWidget);
      expect(find.text('Not enough reports yet to know its best hour.'), findsOneWidget);
    });

    testWidgets('tapping a restaurant opens it', (tester) async {
      final opened = <String>[];
      await open(tester, opened: opened);
      await tester.tap(find.text('Nitro Coffee'));
      expect(opened, ['nitro-coffee']);
    });

    testWidgets('the 4 weeks chip loads that window', (tester) async {
      final service = await open(tester);
      await tester.tap(find.text('Last 4 weeks'));
      await tester.pumpAndSettle();
      expect(service.calls, [7, 28]);
      expect(find.textContaining('in the last 28 days'), findsOneWidget);
    });

    testWidgets('offline: the saved copy with a banner, and it reloads when the signal comes back', (tester) async {
      final storage = _MemoryStorage();
      await storage.saveBestTimes(_report(), savedAt: DateTime(2026, 11, 27, 9, 30));
      final connection = StreamController<List<ConnectivityResult>>();
      final service = _FakeService()..error = const SocketException('no signal');
      await open(tester, service: service, storage: storage, connection: connection.stream);
      expect(find.text('Offline · saved at 09:30'), findsOneWidget);

      service.error = null;
      connection.add([ConnectivityResult.wifi]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Offline'), findsNothing);
      expect(service.calls, [7, 7]);
      await connection.close();
    });

    testWidgets('offline with nothing saved says so and has Try again', (tester) async {
      await open(tester, service: _FakeService()..error = const SocketException('no signal'));
      expect(find.textContaining("You're offline and there's no saved copy yet"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a week without reports explains how to get them', (tester) async {
      final service = _EmptyService();
      await tester.pumpWidget(MaterialApp(
        home: BestTimeScreen(
          loader: BestTimeLoader(service: service, storage: _MemoryStorage()),
          onOpenSpot: (_) {},
          connectionChanges: const Stream.empty(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nobody has reported a wait in these days yet'), findsOneWidget);
    });
  });
}

class _EmptyService implements BestTimeService {
  @override
  Future<BestTimeReport> report({required int days, required int tzOffsetMinutes}) async =>
      BestTimeReport(days: days, minReports: 2, totalReports: 0, campusByHour: const [], spots: const []);
}
