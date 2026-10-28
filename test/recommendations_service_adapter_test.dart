import 'dart:convert';

import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/services/recommendations_service_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request request;
  late http.Response response;

  RecommendationsService adapter() => RecommendationsServiceAdapter(
        baseUrl: 'http://api.test/api/v1',
        client: MockClient((r) async {
          request = r;
          return response;
        }),
      );

  test('calls the nearby recommendations endpoint with the position', () async {
    response = http.Response.bytes(utf8.encode('[]'), 200);

    await adapter().nearbyPicks(userId: 'u 1', lat: 4.6018, lng: -74.0661);

    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/users/u%201/recommendations/nearby');
    expect(request.url.queryParameters, {'lat': '4.6018', 'lng': '-74.0661'});
  });

  test('turns the JSON into NearbyPick objects', () async {
    final body = jsonEncode([
      {
        'id': 'nitro-coffee',
        'name': 'Nitro Coffee & Brew',
        'emoji': '☕',
        'rating': 4.6,
        'latitude': 4.6019,
        'longitude': -74.0658,
        'distanceMeters': 42.4,
        'walkMinutes': 0.5,
      },
    ]);
    response = http.Response.bytes(utf8.encode(body), 200);

    final picks = await adapter().nearbyPicks(userId: 'u1', lat: 4.6, lng: -74.06);

    final pick = picks.single;
    expect(pick.id, 'nitro-coffee');
    expect(pick.emoji, '☕');
    expect(pick.rating, 4.6);
    expect((pick.latitude, pick.longitude), (4.6019, -74.0658));
    expect(pick.distanceMeters, 42);
    expect(pick.walkMinutes, 1);
  });

  test('throws ApiException when the backend fails', () {
    response = http.Response('{"detail": "boom"}', 500);

    expect(
      adapter().nearbyPicks(userId: 'u1', lat: 4.6, lng: -74.06),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
    );
  });
}
