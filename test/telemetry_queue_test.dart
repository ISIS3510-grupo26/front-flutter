import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/services/telemetry_queue.dart';
import 'package:campus_bites/services/telemetry_store.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  test('sends the queue as soon as the phone is back online', () async {
    final connectivity = StreamController<List<ConnectivityResult>>();
    final online = TelemetryQueue(
      baseUrl: 'http://api.test/api/v1',
      loadDevice: () async =>
          const DeviceContext(model: 'SM-S906U1', osVersion: '15'),
      flushInterval: const Duration(hours: 1),
      connectivity: connectivity.stream,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', status);
      }),
    )..enqueue(event());

    connectivity.add([ConnectivityResult.none]);
    await pumpEventQueue();
    expect(requests, isEmpty);

    connectivity.add([ConnectivityResult.wifi]);
    await pumpEventQueue();
    expect(requests, hasLength(1));
    expect(online.pending, 0);

    // Switching from wifi to mobile data is not coming back online.
    online.enqueue(event());
    connectivity.add([ConnectivityResult.mobile]);
    await pumpEventQueue();
    expect(requests, hasLength(1));

    online.dispose();
    expect(connectivity.hasListener, isFalse);
  });

  group('saved on disk', () {
    late Directory directory;
    late FileTelemetryStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('telemetry_queue_test');
      store = FileTelemetryStore(() async => directory);
    });

    tearDown(() async {
      // Waits for the removes a flush started without waiting.
      await store.load();
      await directory.delete(recursive: true);
    });

    TelemetryQueue queueOn(TelemetryStore store) {
      final queue = TelemetryQueue(
        baseUrl: 'http://api.test/api/v1',
        loadDevice: () async =>
            const DeviceContext(model: 'SM-S906U1', osVersion: '15'),
        flushInterval: const Duration(hours: 1),
        store: store,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', status);
        }),
      );
      addTearDown(queue.dispose);
      return queue;
    }

    List<String> sentIds(http.Request request) => [
          for (final e in jsonDecode(request.body)['events'] as List)
            (e as Map<String, dynamic>)['eventId'] as String,
        ];

    // The store runs its operations in order, so loading waits for the
    // writes the queue started without waiting.
    Future<List<String>> savedIds() async =>
        [for (final e in await store.load()) e.eventId];

    File file() => File('${directory.path}${Platform.pathSeparator}${FileTelemetryStore.fileName}');

    /// The file a previous run left behind, written in one go.
    Future<void> leftByPreviousRun(List<TelemetryEvent> events) => file()
        .writeAsString(events.map((e) => '${jsonEncode(e.toJson())}\n').join());

    test('an event queued before the app was closed is sent after restart',
        () async {
      final saved = event();
      queueOn(store).enqueue(saved);

      // A new queue on the same file, as after the app is opened again.
      final restarted = queueOn(FileTelemetryStore(() async => directory));
      await restarted.restore();
      expect(restarted.pending, 1);

      await restarted.flush();
      expect(sentIds(requests.single), [saved.eventId]);
      expect(await savedIds(), isEmpty);
    });

    test('a 202 removes the sent events from the file', () async {
      final queue = queueOn(store)
        ..enqueue(event())
        ..enqueue(event());
      expect(await savedIds(), hasLength(2));

      await queue.flush();
      expect(await savedIds(), isEmpty);
    });

    test('a 5xx keeps the event on disk and retries it with the same id',
        () async {
      final saved = event();
      status = 500;
      final queue = queueOn(store)..enqueue(saved);
      await queue.flush();
      expect(await savedIds(), [saved.eventId]);

      status = 202;
      await queue.flush();
      expect([for (final r in requests) sentIds(r)], [
        [saved.eventId],
        [saved.eventId],
      ]);
      expect(await savedIds(), isEmpty);
    });

    test('a 4xx drops the batch from the file too', () async {
      status = 400;
      final queue = queueOn(store)..enqueue(event());
      await queue.flush();

      expect(queue.pending, 0);
      expect(await savedIds(), isEmpty);
    });

    test('the same event is never queued twice', () async {
      final saved = event();
      final queue = queueOn(store)
        ..enqueue(saved)
        ..enqueue(saved);
      await queue.restore();
      await queue.restore();
      expect(queue.pending, 1);
      expect(await savedIds(), [saved.eventId]);

      final restarted = queueOn(FileTelemetryStore(() async => directory));
      await restarted.restore();
      // The BQ14 outbox may forward an event the queue already restored.
      await restarted.enqueueAll([saved]);
      expect(restarted.pending, 1);
    });

    test('a broken line does not stop the others from being restored',
        () async {
      final first = event();
      final second = event();
      await store.append(first);
      await file().writeAsString('not json\n', mode: FileMode.append);
      await store.append(second);

      final queue = queueOn(store);
      await queue.restore();
      await queue.flush();

      expect(sentIds(requests.single), [first.eventId, second.eventId]);
    });

    test('over 500 events, the oldest are dropped from the file too', () async {
      final previous = [for (var i = 0; i < 500; i++) event()];
      await leftByPreviousRun(previous);
      final queue = queueOn(store);
      await queue.restore();

      final current = [for (var i = 0; i < 5; i++) event()];
      for (final e in current) {
        queue.enqueue(e);
      }

      expect(queue.pending, 500);
      expect(await savedIds(), [
        for (final e in [...previous.skip(5), ...current]) e.eventId,
      ]);
    });

    test('restored events go first and count toward the limit', () async {
      final previous = [for (var i = 0; i < 450; i++) event()];
      await leftByPreviousRun(previous);
      final current = [for (var i = 0; i < 100; i++) event()];
      final queue = queueOn(store);
      await queue.enqueueAll(current);

      await queue.restore();

      // The 50 oldest events of the previous run don't fit.
      final kept = [...previous.skip(50), ...current];
      expect(queue.pending, 500);
      expect(await savedIds(), [for (final e in kept) e.eventId]);
      await queue.flush();
      expect(sentIds(requests.single), [for (final e in kept.take(100)) e.eventId]);
    });

    test('a disk that fails never breaks the queue', () async {
      final queue = queueOn(FileTelemetryStore(
        () async => Directory('${directory.path}${Platform.pathSeparator}missing'),
      ));

      queue.enqueue(event());
      await queue.enqueueAll([event()]);
      await queue.restore();
      await queue.flush();

      expect(sentIds(requests.single), hasLength(2));
      expect(queue.pending, 0);
    });
  });
}
