import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/best_for_you.dart';
import '../repositories/api_exception.dart';

/// What "Best for you right now" (BQ6) needs from the backend, without
/// knowing it is HTTP.
abstract class BestForYouService {
  /// The restaurants with the shortest wait and the best match with
  /// [profile], best first.
  Future<BestForYouRanking> ranking(BestForYouProfile profile);
}

/// Service Adapter: adapts `GET /recommendations/best-for-you` to
/// [BestForYouService]. It turns the profile into query parameters and the
/// JSON into model objects.
///
/// Failures: network errors are thrown as they come (TimeoutException,
/// SocketException, ClientException); any status other than 200 is an
/// [ApiException].
class BestForYouServiceAdapter implements BestForYouService {
  /// The section shows five places, so the backend sends only those.
  static const _limit = 5;

  /// A wait reported more than two hours ago no longer counts, the same
  /// window as the BQ6 card in the team dashboard.
  static const _freshMinutes = 120;

  final http.Client _client;
  final String _baseUrl;

  BestForYouServiceAdapter({
    required this._client,
    this._baseUrl = ApiConfig.baseUrl,
  });

  /// Five small entries: parsed right here, an isolate would cost more than
  /// the parsing itself (the "By hour" ranking, with every hour, does use one).
  @override
  Future<BestForYouRanking> ranking(BestForYouProfile profile) async {
    final uri = Uri.parse('$_baseUrl/recommendations/best-for-you').replace(
      queryParameters: {
        'freshMinutes': '$_freshMinutes',
        'limit': '$_limit',
        ...profile.queryParameters,
      },
    );
    final response = await _client.get(uri).timeout(apiTimeout);
    expectStatus(response, 200);
    return BestForYouRanking.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }
}
