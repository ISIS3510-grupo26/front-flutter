import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/nearby_pick.dart';
import '../repositories/api_exception.dart';

/// What the Taste Map needs from the backend, without knowing it is HTTP.
abstract class RecommendationsService {
  /// Nearby spots the user hasn't reviewed yet, sorted by rating desc then
  /// walking minutes asc.
  Future<List<NearbyPick>> nearbyPicks({
    required String userId,
    required double lat,
    required double lng,
  });
}

/// Service Adapter: adapts `GET /users/{id}/recommendations/nearby` to
/// [RecommendationsService]. It translates the call into an HTTP request and
/// the JSON response into [NearbyPick] objects, so the Taste Map only talks
/// to the interface.
class RecommendationsServiceAdapter implements RecommendationsService {
  final http.Client _client;
  final String _baseUrl;

  RecommendationsServiceAdapter({
    required this._client,
    this._baseUrl = ApiConfig.baseUrl,
  });

  @override
  Future<List<NearbyPick>> nearbyPicks({
    required String userId,
    required double lat,
    required double lng,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/users/${Uri.encodeComponent(userId)}/recommendations/nearby',
    ).replace(queryParameters: {'lat': '$lat', 'lng': '$lng'});
    final response = await _client.get(uri).timeout(apiTimeout);
    expectStatus(response, 200);
    return [
      for (final item in decodeJson(response) as List<dynamic>)
        NearbyPick.fromJson(item as Map<String, dynamic>),
    ];
  }
}
