import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_user.dart';

/// Keeps the signed-in user in the platform's encrypted storage.
class TokenStore {
  static const _userIdKey = 'auth.userId';
  static const _emailKey = 'auth.email';
  static const _tokenKey = 'auth.accessToken';

  final FlutterSecureStorage _storage;

  const TokenStore([this._storage = const FlutterSecureStorage()]);

  Future<AuthUser?> read() async {
    final values = await _storage.readAll();
    final userId = values[_userIdKey];
    final email = values[_emailKey];
    final token = values[_tokenKey];
    if (userId == null || email == null || token == null) return null;
    return AuthUser(userId: userId, email: email, accessToken: token);
  }

  Future<void> write(AuthUser user) async {
    await _storage.write(key: _userIdKey, value: user.userId);
    await _storage.write(key: _emailKey, value: user.email);
    await _storage.write(key: _tokenKey, value: user.accessToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _tokenKey);
  }
}
