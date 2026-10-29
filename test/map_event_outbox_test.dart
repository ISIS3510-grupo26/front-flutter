import 'dart:io';

import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/services/map_event_outbox.dart';
import 'package:campus_bites/services/telemetry_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  late MapEventOutbox outbox;
  late TelemetryQueue queue;

  File file() => File('${directory.path}${Platform.pathSeparator}${MapEventOutbox.fileName}');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('outbox_test');
    outbox = MapEventOutbox(() async => directory);
    queue = TelemetryQueue(
      baseUrl: 'http://api.test/api/v1',
      loadDevice: () async => const DeviceContext(model: 'Pixel 7', osVersion: '14'),
      flushInterval: const Duration(hours: 1),
      client: MockClient((_) async => http.Response('{}', 202)),
    );
  });

  tearDown(() async {
    queue.dispose();
    await directory.delete(recursive: true);
  });

  TelemetryEvent event(String? errorType) => TelemetryEvent.mapDisplay(
        userId: 'u1',
        success: errorType == null,
        errorType: errorType,
        durationMs: 300,
      );

  test('appended events stay in map_events.json', () async {
    await outbox.append(event(null));
    await outbox.append(event('tiles_failed'));

    expect(await file().readAsLines(), hasLength(2));
    expect(queue.pending, 0);
  });

  test('forwarding enqueues every saved event and deletes the file', () async {
    final first = event('load_failed');
    final second = event(null);
    await outbox.append(first);
    await outbox.append(second);

    // A new outbox reads the same file, as after an app restart.
    final forwarded = await MapEventOutbox(() async => directory).forwardTo(queue);

    expect(forwarded, 2);
    expect(queue.pending, 2);
    expect(await file().exists(), isFalse);
    expect(directory.listSync(), isEmpty);
  });

  test('the forwarded events keep their id and fields', () async {
    final original = event('invalid_coordinates');
    await outbox.append(original);

    var sentBody = '';
    final capture = TelemetryQueue(
      baseUrl: 'http://api.test/api/v1',
      loadDevice: () async => const DeviceContext(model: 'Pixel 7', osVersion: '14'),
      flushInterval: const Duration(hours: 1),
      client: MockClient((request) async {
        sentBody = request.body;
        return http.Response('{}', 202);
      }),
    );
    addTearDown(capture.dispose);

    await outbox.forwardTo(capture);
    await capture.flush();

    expect(sentBody, contains('"eventId":"${original.eventId}"'));
    expect(sentBody, contains('"screen":"map_display"'));
    expect(sentBody, contains('"errorType":"invalid_coordinates"'));
  });

  test('nothing saved forwards nothing', () async {
    expect(await outbox.forwardTo(queue), 0);
    expect(queue.pending, 0);
  });

  test('a broken line is skipped', () async {
    await outbox.append(event(null));
    await file().writeAsString('{not json\n', mode: FileMode.append);

    expect(await outbox.forwardTo(queue), 1);
    expect(await file().exists(), isFalse);
  });
}
