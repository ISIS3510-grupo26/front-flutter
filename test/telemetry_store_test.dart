import 'dart:io';

import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/services/telemetry_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late FileTelemetryStore store;

  File file() => File('${directory.path}${Platform.pathSeparator}${FileTelemetryStore.fileName}');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('telemetry_store_test');
    store = FileTelemetryStore(() async => directory);
  });

  tearDown(() => directory.delete(recursive: true));

  TelemetryEvent event() =>
      TelemetryEvent.favoriteAdded(userId: 'u1', spotId: 'green-bowl-co');

  test('nothing saved loads nothing', () async {
    expect(await store.load(), isEmpty);
  });

  test('appended events load back in order with their id and fields', () async {
    final first = event();
    final second = TelemetryEvent.mapDisplay(
      userId: 'u1',
      success: false,
      errorType: 'tiles_failed',
      durationMs: 300,
    );
    await store.append(first);
    await store.append(second);

    // A new store reads the same file, as after an app restart.
    final loaded = await FileTelemetryStore(() async => directory).load();

    expect([for (final e in loaded) e.toJson()], [first.toJson(), second.toJson()]);
    expect(await file().readAsLines(), hasLength(2));
  });

  test('remove rewrites the file without those events', () async {
    final events = [event(), event(), event()];
    for (final e in events) {
      await store.append(e);
    }

    await store.remove([events[0].eventId, events[2].eventId]);

    expect([for (final e in await store.load()) e.eventId], [events[1].eventId]);
    expect(await file().readAsLines(), hasLength(1));
    expect(directory.listSync(), hasLength(1), reason: 'no .tmp file left behind');
  });

  test('a broken line does not stop the others from loading', () async {
    final first = event();
    final second = event();
    await store.append(first);
    await file().writeAsString('{"eventId": "cut in hal\n\n', mode: FileMode.append);
    await store.append(second);

    expect([for (final e in await store.load()) e.eventId], [first.eventId, second.eventId]);
  });

  test('operations run in the order they were called', () async {
    final events = [for (var i = 0; i < 20; i++) event()];

    // Not awaited one by one: the removes must not rewrite the file while
    // later appends are writing it.
    await Future.wait([
      for (final e in events) store.append(e),
      store.remove([events[0].eventId]),
      store.remove([events[19].eventId]),
    ]);

    expect(
      [for (final e in await store.load()) e.eventId],
      [for (final e in events.sublist(1, 19)) e.eventId],
    );
  });

  test('a failed write throws and the next operations still run', () async {
    final missing = FileTelemetryStore(
      () async => Directory('${directory.path}${Platform.pathSeparator}missing'),
    );

    await expectLater(missing.append(event()), throwsA(isA<FileSystemException>()));
    await store.append(event());
    expect(await store.load(), hasLength(1));
  });
}
