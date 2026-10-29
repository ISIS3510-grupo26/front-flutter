import 'dart:convert';

import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/services/popularity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _report(List<Map<String, Object>> hours) =>
    jsonEncode({'days': 7, 'tzOffsetMinutes': -300, 'hours': hours});

const _hour13 = {
  'hour': 13,
  'totalPageViews': 4,
  'totalSearches': 1,
  'spots': [
    {
      'rank': 1,
      'spotId': 'green-bowl-co',
      'name': 'Green Bowl Co.',
      'emoji': '🥗',
      'pageViews': 4,
      'searches': 1,
      'total': 5,
    },
  ],
};

void main() {
  late http.Request request;
  late http.Response Function() respond;

  PopularityService adapter() => PopularityServiceAdapter(
    baseUrl: 'http://api.test/api/v1',
    client: MockClient((r) async {
      request = r;
      return respond();
    }),
  );

  group('rankingAt', () {
    test('asks for the hour and time zone it is given', () async {
      respond = () => http.Response.bytes(utf8.encode(_report([_hour13])), 200);

      await adapter().rankingAt(hour: 13, tzOffsetMinutes: -300);

      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/analytics/spot-views-by-hour');
      expect(request.url.queryParameters, {
        'hour': '13',
        'tzOffsetMinutes': '-300',
      });
    });

    test('returns that hour ranking', () async {
      respond = () => http.Response.bytes(utf8.encode(_report([_hour13])), 200);

      final ranking = await adapter().rankingAt(
        hour: 13,
        tzOffsetMinutes: -300,
      );

      expect(ranking.hour, 13);
      expect(ranking.spots.single.spotId, 'green-bowl-co');
      expect(ranking.spots.single.total, 5);
    });

    test(
      'an hour without activity is an empty ranking, not an error',
      () async {
        respond = () => http.Response.bytes(utf8.encode(_report([])), 200);

        final ranking = await adapter().rankingAt(
          hour: 4,
          tzOffsetMinutes: -300,
        );

        expect(ranking.hour, 4);
        expect(ranking.isEmpty, isTrue);
      },
    );

    test('a network failure is thrown as a network error', () {
      respond = () => throw http.ClientException('Connection refused');

      expect(
        adapter().rankingAt(hour: 13, tzOffsetMinutes: -300),
        throwsA(predicate<Object>(isNetworkError, 'a network error')),
      );
    });

    test('an HTTP error is an ApiException, not a network error', () {
      respond = () => http.Response('{"detail": "boom"}', 500);

      expect(
        adapter().rankingAt(hour: 13, tzOffsetMinutes: -300),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having(isNetworkError, 'isNetworkError', isFalse),
        ),
      );
    });
  });

  test('rankingByHours asks for every hour', () async {
    respond = () => http.Response.bytes(utf8.encode(_report([_hour13])), 200);

    final report = await adapter().rankingByHours(tzOffsetMinutes: 60);

    expect(request.url.path, '/api/v1/analytics/spot-views-by-hour');
    expect(request.url.queryParameters, {'tzOffsetMinutes': '60'});
    expect(report.days, 7);
    expect(report.hours.single.hour, 13);
  });

  test('searchesByWeekday reads the count of every day', () async {
    respond = () => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'days': 28,
          'tzOffsetMinutes': -300,
          'totalSearches': 5,
          'byDay': [
            {'dayOfWeek': 0, 'dayName': 'Monday', 'searches': 3},
            {'dayOfWeek': 1, 'dayName': 'Tuesday', 'searches': 2},
          ],
        }),
      ),
      200,
    );

    final searches = await adapter().searchesByWeekday(tzOffsetMinutes: -300);

    expect(request.url.path, '/api/v1/analytics/searches-by-weekday');
    expect(request.url.queryParameters, {'tzOffsetMinutes': '-300'});
    expect((searches.days, searches.totalSearches), (28, 5));
    expect(searches.byDay.map((d) => d.dayName), ['Monday', 'Tuesday']);
    expect(searches.byDay.first.searches, 3);
  });
}
