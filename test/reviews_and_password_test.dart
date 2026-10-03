import 'dart:convert';

import 'package:campus_bites/models/auth_user.dart';
import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/auth_repository.dart';
import 'package:campus_bites/repositories/spots_repository.dart';
import 'package:campus_bites/services/auth_session.dart';
import 'package:campus_bites/services/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _maria = AuthUser(userId: 'u-maria', email: 'maria@uniandes.edu.co', accessToken: 'tok-old');

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
  Object? changeError;

  @override
  Future<void> verify(String accessToken) async {}

  @override
  Future<AuthUser> changePassword(String accessToken, String currentPassword, String newPassword) async {
    if (changeError case final e?) throw e;
    return AuthUser(userId: _maria.userId, email: _maria.email, accessToken: 'tok-new');
  }
}

Map<String, dynamic> _spotJson() => {
      'id': 'nitro-coffee',
      'emoji': '☕',
      'emojiBackground': '#FFFBEB',
      'emojiBorder': '#FEF3C7',
      'name': 'Nitro Coffee & Brew',
      'subtitle': 'Coffee • Library',
      'rating': 4.6,
      'price': '\$5.000 - \$9.000 COP',
      'distance': '2 min walk',
      'walkMinutes': 2,
      'isBudget': true,
      'isVegetarian': true,
      'isHighProtein': false,
      'affinityPercent': 90,
      'category': 'STUDY_SPOTS',
      'noteLabel': 'Recommended',
      'note': 'Quiet place to study.',
      'uniCardPerk': null,
      'totalReviews': 52,
      'menu': [],
      'reviews': [
        {
          'authorName': 'maria',
          'initials': 'MA',
          'program': 'Student',
          'stars': 5,
          'text': 'Buen cafe',
          'dinedAgo': 'Dined today',
          'helpfulCount': 0,
        },
      ],
    };

void main() {
  group('SpotsRepository', () {
    late http.Request request;
    late http.Response response;

    SpotsRepository repo() => SpotsRepository(
          baseUrl: 'http://api.test/api/v1',
          client: MockClient((r) async {
            request = r;
            return response;
          }),
        );

    test('fetchSpot parses the restaurant page', () async {
         response = http.Response.bytes(utf8.encode(jsonEncode(_spotJson())), 200);

      final spot = await repo().fetchSpot('nitro-coffee');

      expect(request.url.path, '/api/v1/spots/nitro-coffee');
      expect(spot.name, 'Nitro Coffee & Brew');
      expect(spot.emojiBackground.toARGB32(), 0xFFFFFBEB);
      expect(spot.uniCardPerk, isNull);
      expect(spot.reviews.single.stars, 5);
    });

    test('postReview sends stars and text and reads the new average', () async {
      response = http.Response(
        jsonEncode({'spotId': 'nitro-coffee', 'stars': 4, 'text': 'Rico', 'rating': 4.6, 'totalReviews': 53}),
        201,
      );

      final result = await repo().postReview('nitro-coffee', 4, 'Rico');

      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/spots/nitro-coffee/reviews');
      expect(jsonDecode(request.body), {'stars': 4, 'text': 'Rico'});
      expect(result.totalReviews, 53);
    });

    test('a second review of the same spot throws ApiException 409', () {
      response = http.Response('{"detail": "already reviewed"}', 409);
      expect(
        repo().postReview('nitro-coffee', 4, ''),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
    });
  });

  group('change password', () {
    test('AuthRepository posts both passwords with the current token', () async {
      late http.Request request;
      final repo = AuthRepository(
        baseUrl: 'http://api.test/api/v1',
        client: MockClient((r) async {
          request = r;
          return http.Response(
            jsonEncode({'userId': 'u-maria', 'email': 'maria@uniandes.edu.co', 'accessToken': 'tok-new'}),
            200,
          );
        }),
      );

      final user = await repo.changePassword('tok-old', 'segura123', 'nueva12345');

      expect(request.url.path, '/api/v1/auth/change-password');
      expect(request.headers['Authorization'], 'Bearer tok-old');
      expect(jsonDecode(request.body), {'currentPassword': 'segura123', 'newPassword': 'nueva12345'});
      expect(user.accessToken, 'tok-new');
    });

    test('AuthSession keeps the user signed in with the new token', () async {
      final store = _MemoryStore(_maria);
      final session = AuthSession(repository: _FakeAuthRepository(), store: store);
      await session.restore();

      await session.changePassword('segura123', 'nueva12345');

      expect(session.state, isA<AuthSignedIn>());
      expect(session.accessToken, 'tok-new');
      expect(store.user?.accessToken, 'tok-new');
    });

    test('a wrong current password does not sign the user out', () async {
      final repo = _FakeAuthRepository()..changeError = const ApiException(400);
      final session = AuthSession(repository: repo, store: _MemoryStore(_maria));
      await session.restore();

      await expectLater(session.changePassword('incorrecta', 'nueva12345'), throwsA(isA<ApiException>()));

      expect(session.accessToken, 'tok-old');
    });
  });

  test('restaurantDetail event carries the error only when the load failed', () {
    final ok = TelemetryEvent.restaurantDetail(spotId: 'nitro-coffee', durationMs: 800, success: true, httpStatus: 200)
        .toJson();
    final failed = TelemetryEvent.restaurantDetail(
      spotId: 'nitro-coffee',
      durationMs: 10000,
      success: false,
      errorType: 'TIMEOUT',
    ).toJson();

    expect(ok['screen'], 'restaurant_detail');
    expect(ok['httpStatus'], 200);
    expect(ok.containsKey('errorType'), isFalse);
    expect(failed['success'], isFalse);
    expect(failed['errorType'], 'TIMEOUT');
  });
}
