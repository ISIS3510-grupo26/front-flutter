import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/spot_detail.dart';
import 'api_exception.dart';

class SpotsRepository {
  final http.Client _client;
  final String _baseUrl;

  SpotsRepository({required this._client, this._baseUrl = ApiConfig.baseUrl});

  Uri _spotUri(String spotId, [String path = '']) =>
      Uri.parse('$_baseUrl/spots/${Uri.encodeComponent(spotId)}$path');

  /// 404 si no existe.
  Future<SpotDetail> fetchSpot(String spotId) async {
    final response = await _client.get(_spotUri(spotId)).timeout(apiTimeout);
    expectStatus(response, 200);
    return SpotDetail.fromJson(decodeJson(response) as Map<String, dynamic>);
  }

  /// Necesita un usuario registrado (el token es añadido por AuthClient). Muestra 401 si no hay sesión, 409 si el usuario ya ha
  /// evaluado este restaurante, 422 si [stars] no está entre 1 y 5.
  Future<ReviewResult> postReview(String spotId, int stars, String text) async {
    final response = await _client
        .post(
          _spotUri(spotId, '/reviews'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'stars': stars, 'text': text}),
        )
        .timeout(apiTimeout);
    expectStatus(response, 201);
    return ReviewResult.fromJson(decodeJson(response) as Map<String, dynamic>);
  }
}
