import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/nearby_favorite.dart';
import 'api_exception.dart';

class FavoritesRepository {
  final http.Client _client;
  final String _baseUrl;

  FavoritesRepository({required this._client, this._baseUrl = ApiConfig.baseUrl});

  Uri _favoritesUri(String userId, [String path = '']) =>
      Uri.parse('$_baseUrl/users/${Uri.encodeComponent(userId)}/favorites$path');

  Uri _spotUri(String userId, String spotId) =>
      _favoritesUri(userId, '/${Uri.encodeComponent(spotId)}');

  /// Ids of the spots [userId] has saved on the server.
  Future<Set<String>> fetchFavoriteIds(String userId) async {
    final response = await _client.get(_favoritesUri(userId)).timeout(apiTimeout);
    expectStatus(response, 200);
    return {
      for (final spot in decodeJson(response) as List<dynamic>)
        (spot as Map<String, dynamic>)['id'] as String,
    };
  }

  Future<void> addFavorite(String userId, String spotId) async {
    final response =
        await _client.put(_spotUri(userId, spotId)).timeout(apiTimeout);
    expectStatus(response, 204);
  }

  Future<void> removeFavorite(String userId, String spotId) async {
    final response =
        await _client.delete(_spotUri(userId, spotId)).timeout(apiTimeout);
    expectStatus(response, 204);
  }

  /// The user's saved spots that are open now and within [maxWalkMinutes]
  /// of ([lat], [lng]), as computed by the backend.
  Future<List<NearbyFavorite>> fetchOpenNearby({
    required String userId,
    required double lat,
    required double lng,
    int maxWalkMinutes = 15,
  }) async {
    final uri = _favoritesUri(userId, '/nearby').replace(queryParameters: {
      'lat': '$lat',
      'lng': '$lng',
      'maxWalkMinutes': '$maxWalkMinutes',
    });
    final response = await _client.get(uri).timeout(apiTimeout);
    expectStatus(response, 200);
    return [
      for (final item in decodeJson(response) as List<dynamic>)
        NearbyFavorite.fromJson(item as Map<String, dynamic>),
    ];
  }
}
