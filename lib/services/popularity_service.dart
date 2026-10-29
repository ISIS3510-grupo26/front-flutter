import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/hourly_ranking.dart';
import '../models/weekday_searches.dart';
import '../repositories/api_exception.dart';

/// What "Popular right now" needs from the backend, without knowing it is HTTP.
///
/// [hour] and [tzOffsetMinutes] are the phone's local hour and time zone; the
/// backend uses them to tell which campus hour or day that is. The caller
/// decides what "now" is, so one clock reading drives both the request and its
/// cache.
abstract class PopularityService {
  /// The ranking for [hour]; empty when nobody was active at that hour.
  Future<HourlyRanking> rankingAt({
    required int hour,
    required int tzOffsetMinutes,
  });

  /// The ranking of every hour with activity.
  Future<PopularityReport> rankingByHours({required int tzOffsetMinutes});

  /// Restaurant selections from search results per day of the week.
  Future<WeekdaySearches> searchesByWeekday({required int tzOffsetMinutes});
}

/// Service Adapter: adapts the `/analytics` popularity endpoints to
/// [PopularityService]. It translates each call into an HTTP request and the
/// JSON into model objects.
///
/// Failures: network errors are thrown as they come (TimeoutException,
/// SocketException, ClientException); any status other than 200 is an
/// [ApiException].
class PopularityServiceAdapter implements PopularityService {
  final http.Client _client;
  final String _baseUrl;

  PopularityServiceAdapter({
    required this._client,
    this._baseUrl = ApiConfig.baseUrl,
  });

  @override
  Future<HourlyRanking> rankingAt({
    required int hour,
    required int tzOffsetMinutes,
  }) async {
    final body = await _get('spot-views-by-hour', {
      'hour': '$hour',
      'tzOffsetMinutes': '$tzOffsetMinutes',
    });
    final report = await Isolate.run(() => parsePopularityReport(body));
    return report.rankingFor(hour);
  }

  @override
  Future<PopularityReport> rankingByHours({
    required int tzOffsetMinutes,
  }) async {
    final body = await _get('spot-views-by-hour', {
      'tzOffsetMinutes': '$tzOffsetMinutes',
    });
    return Isolate.run(() => parsePopularityReport(body));
  }

  /// Seven small entries: parsed right here, an isolate would cost more than
  /// the parsing itself.
  @override
  Future<WeekdaySearches> searchesByWeekday({
    required int tzOffsetMinutes,
  }) async {
    final body = await _get('searches-by-weekday', {
      'tzOffsetMinutes': '$tzOffsetMinutes',
    });
    return WeekdaySearches.fromJson(
      jsonDecode(utf8.decode(body)) as Map<String, dynamic>,
    );
  }

  Future<Uint8List> _get(String endpoint, Map<String, String> query) async {
    final uri = Uri.parse('$_baseUrl/analytics/$endpoint')
        .replace(queryParameters: query);
    final response = await _client.get(uri).timeout(apiTimeout);
    expectStatus(response, 200);
    return response.bodyBytes;
  }
}

/// Multithreading strategy: Isolate. [PopularityServiceAdapter] runs this
/// with `Isolate.run()`, so decoding the JSON of every hour and its spots
/// happens off the UI thread. It is a top-level function so the isolate only
/// receives the response bytes.
PopularityReport parsePopularityReport(Uint8List body) =>
    PopularityReport.fromJson(
      jsonDecode(utf8.decode(body)) as Map<String, dynamic>,
    );
