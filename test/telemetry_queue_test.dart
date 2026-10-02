import 'dart:convert';

import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/services/telemetry_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;
  late int status;
  late TelemetryQueue queue;

  setUp(() {
    requests = [];
    status = 202;
    queue = TelemetryQueue(
      baseUrl: 'http://api.test/api/v1',
      loadDevice: () async =>
          const DeviceContext(model: 'SM-S906U1', osVersion: '15'),
      flushInterval: const Duration(hours: 1),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', status);
      }),
    );
  });

  tearDown(() => queue.dispose());

  TelemetryEvent event() =>
      TelemetryEvent.favoriteAdded(userId: 'u1', spotId: 'green-bowl-co');

  test('sends queued events with device fields in one batch', () async {
    queue
      ..enqueue(event())
      ..enqueue(event());
    await queue.flush();

    expect(requests.single.url.path, '/api/v1/telemetry/page-loads');
    final events = (jsonDecode(requests.single.body)['events'] as List)
        .cast<Map<String, dynamic>>();
    expect(events, hasLength(2));
    expect(events.first, {
      'eventId': isA<String>(),
      'screen': 'favorite_added',
      'spotId': 'green-bowl-co',
      'userId': 'u1',
      'durationMs': 0,
      'success': true,
      'occurredAt': endsWith('Z'),
      'deviceModel': 'SM-S906U1',
      'osName': 'android',
      'osVersion': '15',
      'platform': 'flutter',
    });
    expect(events.first['eventId'], isNot(events.last['eventId']));
    expect(queue.pending, 0);
  });

  test('keeps events for retry when the server fails', () async {
    status = 503;
    queue.enqueue(event());
    await queue.flush();
    expect(queue.pending, 1);

    status = 202;
    await queue.flush();
    expect(requests, hasLength(2));
    expect(queue.pending, 0);
  });

  test('drops a batch the server rejects as invalid', () async {
    status = 422;
    queue.enqueue(event());
    await queue.flush();
    expect(queue.pending, 0);
  });

  test('does nothing when the queue is empty', () async {
    await queue.flush();
    expect(requests, isEmpty);
  });
}
