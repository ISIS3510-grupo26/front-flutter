import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/user_preferences.dart';
import 'api_exception.dart';

/// The student's preferences and the compatibility of each spot.
class MatchesRepository {
  final http.Client _client;
  final String _baseUrl;

  MatchesRepository({required this._client, this._baseUrl = ApiConfig.baseUrl});

  Uri _userUri(String userId, String path) => Uri.parse('$_baseUrl/users/${Uri.encodeComponent(userId)}$path');

  Future<UserPreferences> fetchPreferences(String userId) async {
    final response = await _client.get(_userUri(userId, '/preferences')).timeout(apiTimeout);
    expectStatus(response, 200);
    return UserPreferences.fromJson(decodeJson(response) as Map<String, dynamic>);
  }

  Future<UserPreferences> savePreferences(String userId, UserPreferences preferences) async {
    final response = await _client
        .put(
          _userUri(userId, '/preferences'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(preferences.toJson()),
        )
        .timeout(apiTimeout);
    expectStatus(response, 200);
    return UserPreferences.fromJson(decodeJson(response) as Map<String, dynamic>);
  }

  /// Compatibility 0-100 of every spot for [userId], keyed by spot id.
  Future<Map<String, int>> fetchMatches(String userId) async {
    final response = await _client.get(_userUri(userId, '/matches')).timeout(apiTimeout);
    expectStatus(response, 200);
    return {
      for (final item in decodeJson(response) as List<dynamic>)
        (item as Map<String, dynamic>)['spotId'] as String: item['compatibility'] as int,
    };
  }
}