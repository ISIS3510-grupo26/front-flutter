import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/best_time.dart';
import '../repositories/api_exception.dart';

abstract class BestTimeService {
  /// The best and worst hour of every restaurant, with the reports of the last [days] days.
  Future<BestTimeReport> report({required int days, required int tzOffsetMinutes});
}

/// Service Adapter: adapts `GET /analytics/best-time-to-go` to
/// [BestTimeService]. It turns each call into an HTTP request and the JSON into model objects, so the loader 
/// and the screen never see URLs or status codes.
/// Failures: network errors are thrown as they come (TimeoutException, SocketException, ClientException); any 
/// status other than 200 is an [ApiException].
class BestTimeServiceAdapter implements BestTimeService {
  /// One report alone at an hour is not reliable to call it the best one.
  static const minReports = 2;

  final http.Client _client;
  final String _baseUrl;

  BestTimeServiceAdapter({required http.Client client, String baseUrl = ApiConfig.baseUrl})
      : _client = client,
        _baseUrl = baseUrl;

  @override
  Future<BestTimeReport> report({required int days, required int tzOffsetMinutes}) async {
    final uri = Uri.parse('$_baseUrl/analytics/best-time-to-go').replace(queryParameters: {
      'days': '$days',
      'tzOffsetMinutes': '$tzOffsetMinutes',
      'minReports': '$minReports',
    });
    final response = await _client.get(uri).timeout(apiTimeout);
    expectStatus(response, 200);
    final body = response.bodyBytes;
    return Isolate.run(() => parseBestTimeReport(body));
  }
}

/// Multithreading strategy: Isolate. The answer has every restaurant with up to 24 hours each, plus the campus 
/// hours, so decoding it and building the objects runs in another isolate with `Isolate.run()` and the screen 
/// keeps animating while it loads. It is a top-level function so the isolate only receives the response bytes, 
/// not the adapter with its http client.
BestTimeReport parseBestTimeReport(Uint8List body) =>
    BestTimeReport.fromJson(jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
