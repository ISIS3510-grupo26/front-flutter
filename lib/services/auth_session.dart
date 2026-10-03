import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/auth_user.dart';
import '../repositories/api_exception.dart';
import '../repositories/auth_repository.dart';
import 'token_store.dart';

sealed class AuthState {
  const AuthState();
}

/// Checking the stored token at launch.
final class AuthRestoring extends AuthState {
  const AuthRestoring();
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

final class AuthSignedIn extends AuthState {
  final AuthUser user;

  const AuthSignedIn(this.user);
}

/// No account: requests act as the made-up DEV_USER_ID, without a token.
/// Only entered by explicitly choosing it from the signed-out screen.
final class AuthDevUser extends AuthState {
  final String userId;

  const AuthDevUser(this.userId);
}

class AuthSession extends ChangeNotifier {
  final AuthRepository _repository;
  final TokenStore _store;
  final String _devUserId;
  AuthState _state = const AuthRestoring();

  AuthSession({
    required this._repository,
    this._store = const TokenStore(),
    this._devUserId = ApiConfig.devUserId,
  });

  AuthState get state => _state;

  String? get userId => switch (_state) {
        AuthSignedIn(:final user) => user.userId,
        AuthDevUser(:final userId) => userId,
        _ => null,
      };

  String? get accessToken => switch (_state) {
        AuthSignedIn(:final user) => user.accessToken,
        _ => null,
      };

  bool get canUseDevUser => _devUserId.isNotEmpty;

  /// Signs back in with the stored token if the server still accepts it.
  /// If the server can't be reached, the stored session is kept; any later
  /// 401 signs the user out (see [expire]).
  Future<void> restore() async {
    AuthUser? stored;
    try {
      stored = await _store.read();
    } on Exception {
      // Unreadable storage (e.g. keys lost after a reinstall): start over.
      await _store.clear();
    }
    if (stored == null) return _set(const AuthSignedOut());
    try {
      await _repository.verify(stored.accessToken);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _store.clear();
        return _set(const AuthSignedOut());
      }
    } on Exception {
      // Offline: keep the stored session.
    }
    _set(AuthSignedIn(stored));
  }

  Future<void> logIn(String email, String password) =>
      _signIn(_repository.logIn(email, password));

  Future<void> signUp(String email, String password) =>
      _signIn(_repository.signUp(email, password));

  Future<void> _signIn(Future<AuthUser> request) async {
    final user = await request;
    await _store.write(user);
    _set(AuthSignedIn(user));
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    final token = accessToken;
    if (token == null) throw StateError('No signed-in account');
    try {
      await _signIn(_repository.changePassword(token, currentPassword, newPassword));
    } on ApiException catch (e) {
      if (e.statusCode == 401) await expire(token);
      rethrow;
    }
  }

  void continueAsDevUser() {
    if (canUseDevUser) _set(AuthDevUser(_devUserId));
  }

  Future<void> signOut() async {
    await _store.clear();
    _set(const AuthSignedOut());
  }

  /// Called when the server rejects [token]. Ignored if the user has since
  /// signed in again with a different token.
  Future<void> expire(String token) async {
    if (accessToken == token) await signOut();
  }

  void _set(AuthState state) {
    _state = state;
    notifyListeners();
  }
}
