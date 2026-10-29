import 'dart:io';

import 'package:campus_bites/models/hourly_ranking.dart';
import 'package:campus_bites/models/weekday_searches.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/services/popularity_loader.dart';
import 'package:campus_bites/services/popularity_prefs.dart';
import 'package:campus_bites/services/popularity_service.dart';
import 'package:flutter_test/flutter_test.dart';

HourlyRanking _ranking(int hour, {String spotId = 'green-bowl-co'}) =>
    HourlyRanking(
      hour: hour,
      totalPageViews: 4,
      totalSearches: 1,
      spots: [
        SpotActivity(
          rank: 1,
          spotId: spotId,
          name: 'Green Bowl Co.',
          emoji: '🥗',
          pageViews: 4,
          searches: 1,
          total: 5,
        ),
      ],
    );

class _FakeService extends Fake implements PopularityService {
  final calls = <({int? hour, int tzOffsetMinutes})>[];
  HourlyRanking Function(int hour) ranking = _ranking;
  Object? error;

  @override
  Future<HourlyRanking> rankingAt({
    required int hour,
    required int tzOffsetMinutes,
  }) async {
    calls.add((hour: hour, tzOffsetMinutes: tzOffsetMinutes));
    if (error case final e?) throw e;
    return ranking(hour);
  }

  @override
  Future<PopularityReport> rankingByHours({
    required int tzOffsetMinutes,
  }) async {
    calls.add((hour: null, tzOffsetMinutes: tzOffsetMinutes));
    if (error case final e?) throw e;
    return PopularityReport(days: 7, hours: [ranking(13)]);
  }

  @override
  Future<WeekdaySearches> searchesByWeekday({
    required int tzOffsetMinutes,
  }) async {
    calls.add((hour: null, tzOffsetMinutes: tzOffsetMinutes));
    return const WeekdaySearches(days: 28, totalSearches: 0, byDay: []);
  }
}

class _MemoryPrefs extends Fake implements PopularityPrefs {
  ({HourlyRanking ranking, DateTime savedAt})? last;

  @override
  Future<void> save(HourlyRanking ranking, {required DateTime savedAt}) async =>
      last = (ranking: ranking, savedAt: savedAt);

  @override
  Future<({HourlyRanking ranking, DateTime savedAt})?> read() async => last;
}

void main() {
  late _FakeService service;
  late _MemoryPrefs prefs;
  late DateTime now;
  late PopularityLoader loader;

  setUp(() {
    service = _FakeService();
    prefs = _MemoryPrefs();
    now = DateTime(2026, 10, 29, 13, 20);
    loader = PopularityLoader(service: service, prefs: prefs, now: () => now);
  });

  test('asks for the hour and time zone of its clock', () async {
    final state = await loader.load() as PopularityLoaded;

    expect(service.calls.single, (
      hour: 13,
      tzOffsetMinutes: now.timeZoneOffset.inMinutes,
    ));
    expect(state.ranking.hour, 13);
    expect(state.offlineSavedAt, isNull);
  });

  test('an hour without activity is the empty state', () async {
    service.ranking = HourlyRanking.empty;

    final state = await loader.load();

    expect((state as PopularityEmpty).hour, 13);
  });

  group('LRU cache', () {
    test('a second load within the ttl does not call the backend', () async {
      await loader.load();
      now = now.add(const Duration(minutes: 4));
      final second = await loader.load() as PopularityLoaded;

      expect(service.calls, hasLength(1));
      expect(second.ranking.hour, 13);
    });

    test('after the ttl it calls the backend again', () async {
      await loader.load();
      now = now.add(const Duration(minutes: 6));
      await loader.load();

      expect(service.calls, hasLength(2));
    });

    test('a new hour is a different entry', () async {
      await loader.load();
      now = DateTime(2026, 10, 29, 14, 1);
      final state = await loader.load() as PopularityLoaded;

      expect(service.calls.map((c) => c.hour), [13, 14]);
      expect(state.ranking.hour, 14);
    });

    test('forceRefresh skips the cache', () async {
      await loader.load();
      await loader.load(forceRefresh: true);

      expect(service.calls, hasLength(2));
    });

    test('a failed call is not cached', () async {
      service.error = const ApiException(500);
      await loader.load();
      service.error = null;
      await loader.load();

      expect(service.calls, hasLength(2));
    });
  });

  group('offline', () {
    test('a successful load is saved with its time', () async {
      await loader.load();
      await pumpEventQueue();

      expect(prefs.last?.ranking.hour, 13);
      expect(prefs.last?.savedAt, now);
    });

    test(
      'without network it shows the saved ranking and when it was saved',
      () async {
        final savedAt = DateTime(2026, 10, 29, 9, 5);
        prefs.last = (
          ranking: _ranking(9, spotId: 'nitro-coffee'),
          savedAt: savedAt,
        );
        service.error = const SocketException('offline');

        final state = await loader.load() as PopularityLoaded;

        expect(state.offlineSavedAt, savedAt);
        expect(state.ranking.hour, 9);
        expect(state.ranking.spots.single.spotId, 'nitro-coffee');
      },
    );

    test('without network and nothing saved it is a network failure', () async {
      service.error = const SocketException('offline');

      final state = await loader.load();

      expect((state as PopularityFailed).reason, PopularityFailure.network);
    });

    test('a saved empty hour counts as nothing saved', () async {
      prefs.last = (
        ranking: const HourlyRanking.empty(9),
        savedAt: DateTime(2026, 10, 29, 9),
      );
      service.error = const SocketException('offline');

      final state = await loader.load();

      expect((state as PopularityFailed).reason, PopularityFailure.network);
    });

    test('an HTTP error never shows the saved ranking', () async {
      prefs.last = (ranking: _ranking(9), savedAt: DateTime(2026, 10, 29, 9));
      service.error = const ApiException(503);

      final state = await loader.load();

      expect((state as PopularityFailed).reason, PopularityFailure.server);
    });
  });

  group('by hour', () {
    test('loads every hour with the clock time zone', () async {
      final state = await loader.loadByHours() as PopularByHourLoaded;

      expect(service.calls.single, (
        hour: null,
        tzOffsetMinutes: now.timeZoneOffset.inMinutes,
      ));
      expect(state.report.hours.single.hour, 13);
    });

    test('tells a network failure from a server one', () async {
      service.error = const SocketException('offline');
      expect(
        (await loader.loadByHours() as PopularByHourFailed).reason,
        PopularityFailure.network,
      );

      service.error = const ApiException(500);
      expect(
        (await loader.loadByHours() as PopularByHourFailed).reason,
        PopularityFailure.server,
      );
    });

    test('currentHour comes from the same clock', () {
      expect(loader.currentHour, 13);
    });

    test('searchesByWeekday uses the clock time zone', () async {
      final searches = await loader.searchesByWeekday();

      expect(
        service.calls.single.tzOffsetMinutes,
        now.timeZoneOffset.inMinutes,
      );
      expect(searches.days, 28);
    });
  });
}
