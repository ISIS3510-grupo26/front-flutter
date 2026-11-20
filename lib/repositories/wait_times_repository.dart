import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/wait_time.dart';
import 'api_exception.dart';

/// BQ4
class WaitTimesRepository {
  /// A report older than this is shown as old (same default as the backend).
  static const freshMinutes = 120;

  final http.Client _client;
  final String _baseUrl;

  WaitTimesRepository({required this._client, this._baseUrl = ApiConfig.baseUrl});

  Future<List<LastWaitTime>> fetchLatest() async {
    final uri = Uri.parse('$_baseUrl/spots/wait-times/latest')
        .replace(queryParameters: {'freshMinutes': '$freshMinutes'});
    final response = await _client.get(uri).timeout(apiTimeout);
    expectStatus(response, 200);
    final body = response.bodyBytes;
    return Isolate.run(() => parseLatestWaitTimes(body));
  }

  /// Sending the same [report] twice is safe, the backend ignores a report id
  /// it already has (it answers 201 with duplicate = true).
  Future<void> send(WaitReport report) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/spots/${Uri.encodeComponent(report.spotId)}/wait-times'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(report.toJson()),
        )
        .timeout(apiTimeout);
    expectStatus(response, 201);
  }
}


/// Multithreading strategy: Isolate. [WaitTimesRepository.fetchLatest] runs this with `Isolate.run()`, so 
/// decoding the JSON and building the list of every restaurant happen off the UI thread and the screen never 
/// stutters while it loads. It is a top-level function so the isolate only receives the response bytes, not 
/// the repository.
List<LastWaitTime> parseLatestWaitTimes(Uint8List body) {
  final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
  return [
    for (final item in json['spots'] as List<dynamic>) LastWaitTime.fromJson(item as Map<String, dynamic>),
  ];
}
