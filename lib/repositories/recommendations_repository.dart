import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/nearby_pick.dart';
import 'api_exception.dart';

class RecommendationsRepository {
  final http.Client _client;
  final String _baseUrl;

  RecommendationsRepository({
    required this._client,
    this._baseUrl = ApiConfig.baseUrl,
  });

  /// Nearby spots the user hasn't reviewed yet, already sorted by the backend
  /// by rating desc then walking minutes asc.
  Future<List<NearbyPick>> fetchNearbyPicks({
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
