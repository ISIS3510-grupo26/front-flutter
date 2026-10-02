import 'dart:convert';

import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/favorites_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('saved favorites', () {
    late List<http.Request> requests;
    late http.Response response;

    FavoritesRepository repo() => FavoritesRepository(
          baseUrl: 'http://api.test/api/v1',
          client: MockClient((request) async {
            requests.add(request);
            return response;
          }),
        );

    setUp(() => requests = []);

    test('fetchFavoriteIds reads ids from the spot list', () async {
      response = http.Response(
        jsonEncode([
          {'id': 'green-bowl-co', 'name': 'Green Bowl Co.'},
          {'id': 'nitro-coffee', 'name': 'Nitro Coffee & Brew'},
        ]),
        200,
      );

      final ids = await repo().fetchFavoriteIds('u1');

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/v1/users/u1/favorites');
      expect(ids, {'green-bowl-co', 'nitro-coffee'});
    });

    test('addFavorite PUTs the spot and removeFavorite DELETEs it', () async {
      response = http.Response('', 204);

      await repo().addFavorite('u1', 'green-bowl-co');
      await repo().removeFavorite('u1', 'green-bowl-co');

      expect(
        requests.map((r) => '${r.method} ${r.url.path}'),
        [
          'PUT /api/v1/users/u1/favorites/green-bowl-co',
          'DELETE /api/v1/users/u1/favorites/green-bowl-co',
        ],
      );
    });

    test('addFavorite throws ApiException for an unknown spot', () async {
      response = http.Response('{"detail": "not found"}', 404);

      expect(
        repo().addFavorite('u1', 'nope'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('FavoritesRepository.fetchOpenNearby', () {
    test('calls the nearby endpoint with location and walk limit', () async {
      late Uri requested;
      final repo = FavoritesRepository(
        baseUrl: 'http://api.test/api/v1',
        client: MockClient((request) async {
          requested = request.url;
          return http.Response('[]', 200);
        }),
      );

      await repo.fetchOpenNearby(userId: 'u 1', lat: 4.6, lng: -74.06);

      expect(requested.path, '/api/v1/users/u%201/favorites/nearby');
      expect(requested.queryParameters, {
        'lat': '4.6',
        'lng': '-74.06',
        'maxWalkMinutes': '15',
      });
    });

    test('parses ids and rounds walk minutes up', () async {
      final repo = FavoritesRepository(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => http.Response(
              jsonEncode([
                {'id': 'green-bowl-co', 'walkMinutes': 3.2},
                {'id': 7, 'walkMinutes': 12},
              ]),
              200,
            )),
      );

      final result =
          await repo.fetchOpenNearby(userId: '1', lat: 0, lng: 0);

      expect(result.map((r) => r.id), ['green-bowl-co', '7']);
      expect(result.map((r) => r.walkMinutes), [4, 12]);
    });

    test('throws ApiException on a non-200 response', () async {
      final repo = FavoritesRepository(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => http.Response('nope', 404)),
      );

      expect(
        repo.fetchOpenNearby(userId: '1', lat: 0, lng: 0),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });
}
