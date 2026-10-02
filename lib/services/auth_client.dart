import 'package:http/http.dart' as http;

import 'auth_session.dart';

/// Adds the signed-in user's token to every request, and signs the user out
/// when the server rejects it.
class AuthClient extends http.BaseClient {
  final AuthSession _session;
  final http.Client _inner;

  AuthClient(this._session, [http.Client? inner])
      : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = _session.accessToken;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final response = await _inner.send(request);
    if (response.statusCode == 401 && token != null) {
      await _session.expire(token);
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
