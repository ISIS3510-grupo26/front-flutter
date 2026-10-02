import 'dart:convert';
import 'dart:io';

import 'package:campus_bites/models/auth_user.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/auth_repository.dart';
import 'package:campus_bites/services/auth_client.dart';
import 'package:campus_bites/services/auth_session.dart';
import 'package:campus_bites/services/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _ana = AuthUser(userId: 'uuid-ana', email: 'ana@uniandes.edu.co', accessToken: 'tok-ana');

class _MemoryStore extends Fake implements TokenStore {
  AuthUser? user;

  _MemoryStore([this.user]);

  @override
  Future<AuthUser?> read() async => user;

  @override
  Future<void> write(AuthUser user) async => this.user = user;

  @override
  Future<void> clear() async => user = null;
}

class _FakeAuthRepository extends Fake implements AuthRepository {
  Object? verifyError;

  @override
  Future<void> verify(String accessToken) async {
    if (verifyError case final e?) throw e;
  }

  @override
  Future<AuthUser> logIn(String email, String password) async => _ana;
}

AuthSession _session(_MemoryStore store, {_FakeAuthRepository? repo, String dev = ''}) =>
    AuthSession(repository: repo ?? _FakeAuthRepository(), store: store, devUserId: dev);

void main() {
  group('AuthSession.restore', () {
    test('signs in with a stored token the server accepts', () async {
      final session = _session(_MemoryStore(_ana));
      await session.restore();
      expect(session.state, isA<AuthSignedIn>());
      expect(session.userId, 'uuid-ana');
      expect(session.accessToken, 'tok-ana');
    });

    test('clears a stored token the server rejects', () async {
      final store = _MemoryStore(_ana);
      final session = _session(store,
          repo: _FakeAuthRepository()..verifyError = const ApiException(401));
      await session.restore();
      expect(session.state, isA<AuthSignedOut>());
      expect(store.user, isNull);
    });

    test('keeps the stored session when the server is unreachable', () async {
      final session = _session(_MemoryStore(_ana),
          repo: _FakeAuthRepository()
            ..verifyError = const SocketException('offline'));
      await session.restore();
      expect(session.userId, 'uuid-ana');
    });

    test('never enters the dev user on its own', () async {
      final session = _session(_MemoryStore(), dev: 'dev-camilo');
      await session.restore();
      expect(session.state, isA<AuthSignedOut>());
      expect(session.userId, isNull);

      session.continueAsDevUser();
      expect(session.userId, 'dev-camilo');
      expect(session.accessToken, isNull);
    });
  });

  test('logIn stores the user and signOut clears it', () async {
    final store = _MemoryStore();
    final session = _session(store);
    await session.logIn('ana@uniandes.edu.co', 'password1');
    expect(store.user?.userId, 'uuid-ana');

    await session.signOut();
    expect(session.state, isA<AuthSignedOut>());
    expect(session.accessToken, isNull);
    expect(store.user, isNull);
  });

  test('signing out never falls through to the dev user', () async {
    final session = _session(_MemoryStore(_ana), dev: 'dev-camilo');
    await session.restore();
    await session.signOut();
    expect(session.userId, isNull);

    await session.restore();
    expect(session.state, isA<AuthSignedOut>());
  });

  group('AuthClient', () {
    late List<http.BaseRequest> sent;
    late int status;

    AuthClient client(AuthSession session) => AuthClient(
          session,
          MockClient((request) async {
            sent.add(request);
            return http.Response('', status);
          }),
        );

    setUp(() {
      sent = [];
      status = 200;
    });

    test('sends the token when signed in', () async {
      final session = _session(_MemoryStore(_ana));
      await session.restore();
      await client(session).get(Uri.parse('http://api.test/x'));
      expect(sent.single.headers['Authorization'], 'Bearer tok-ana');
    });

    test('sends no token for the dev user', () async {
      final session = _session(_MemoryStore(), dev: 'dev-camilo');
      await session.restore();
      session.continueAsDevUser();
      await client(session).get(Uri.parse('http://api.test/x'));
      expect(sent.single.headers.containsKey('Authorization'), isFalse);
    });

    test('a 401 signs the user out', () async {
      final session = _session(_MemoryStore(_ana));
      await session.restore();
      status = 401;
      await client(session).get(Uri.parse('http://api.test/x'));
      expect(session.state, isA<AuthSignedOut>());
    });
  });

  group('AuthRepository', () {
    late http.Request request;
    late http.Response response;

    AuthRepository repo() => AuthRepository(
          baseUrl: 'http://api.test/api/v1',
          client: MockClient((r) async {
            request = r;
            return response;
          }),
        );

    test('signUp posts credentials and parses the session', () async {
      response = http.Response(
        jsonEncode({
          'userId': 'uuid-ana',
          'email': 'ana@uniandes.edu.co',
          'accessToken': 'tok-ana',
          'tokenType': 'bearer',
          'expiresIn': 604800,
        }),
        201,
      );

      final user = await repo().signUp('ana@uniandes.edu.co', 'password1');

      expect(request.url.path, '/api/v1/auth/signup');
      expect(jsonDecode(request.body),
          {'email': 'ana@uniandes.edu.co', 'password': 'password1'});
      expect(user.userId, 'uuid-ana');
      expect(user.accessToken, 'tok-ana');
    });

    test('a taken email throws ApiException 409', () {
      response = http.Response('{"detail": "taken"}', 409);
      expect(
        repo().signUp('ana@uniandes.edu.co', 'password1'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
    });

    test('verify sends the token to /auth/me', () async {
      response = http.Response('{}', 200);
      await repo().verify('tok-ana');
      expect(request.url.path, '/api/v1/auth/me');
      expect(request.headers['Authorization'], 'Bearer tok-ana');
    });
  });
}
