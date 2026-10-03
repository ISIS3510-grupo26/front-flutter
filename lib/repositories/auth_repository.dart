  import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_user.dart';
import 'api_exception.dart';

class AuthRepository {
  final http.Client _client;
  final String _baseUrl;

  AuthRepository({required this._client, this._baseUrl = ApiConfig.baseUrl});

  /// Throws [ApiException] 409 if the email is taken, 422 if the email or
  /// password is malformed.
  Future<AuthUser> signUp(String email, String password) =>
      _authenticate('signup', 201, email, password);

  /// Throws [ApiException] 401 for a wrong email or password.
  Future<AuthUser> logIn(String email, String password) =>
      _authenticate('login', 200, email, password);

  /// Completes if [accessToken] is still valid; throws [ApiException] 401 if not.
  Future<void> verify(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/auth/me'),
      headers: {'Authorization': 'Bearer $accessToken'},
    ).timeout(apiTimeout);
    expectStatus(response, 200);
  }

  Future<AuthUser> changePassword(
    String accessToken,
    String currentPassword,
    String newPassword,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/auth/change-password'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'currentPassword': currentPassword,
            'newPassword': newPassword,
          }),
        )
        .timeout(apiTimeout);
    expectStatus(response, 200);
    return AuthUser.fromJson(decodeJson(response) as Map<String, dynamic>);
  }
  
  Future<AuthUser> _authenticate(
    String endpoint,
    int expectedStatus,
    String email,
    String password,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/auth/$endpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(apiTimeout);
    expectStatus(response, expectedStatus);
    return AuthUser.fromJson(decodeJson(response) as Map<String, dynamic>);
  }
}
