import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../models/telemetry_event.dart';

/// Where the TelemetryQueue keeps the events it has not sent yet, so they
/// survive the app being closed.
abstract interface class TelemetryStore {
  /// Every saved event, oldest first.
  Future<List<TelemetryEvent>> load();

  Future<void> append(TelemetryEvent event);

  Future<void> remove(Iterable<String> eventIds);
}

/// Local storage strategy: local file. Eventual connectivity: store and
/// forward.
///
/// Every event the TelemetryQueue has not sent yet is also written to
/// `telemetry_queue.jsonl` in the app documents directory, one JSON event per
/// line (the same format as the BQ14 MapEventOutbox). The queue appends one
/// line per event and removes events once the backend answers, so a file fits:
/// appending is a single short write, while shared_preferences would rewrite
/// the whole list on every event and SQLite would need a schema for a list
/// that only grows at the end and shrinks from the front.
///
/// - [append] adds a line at the end and flushes it to disk.
/// - [remove] writes the remaining events to a `.tmp` file and renames it over
///   the original. The rename is atomic, so closing the app halfway leaves the
///   old file or the new one, never half of it.
/// - [load] skips blank or broken lines and keeps the rest.
///
/// Operations run one at a time, in the order they were called, so a [remove]
/// never rewrites the file while an [append] is writing it. The order is
/// shared by every instance, because after signing out and in again the old
/// and the new queue may touch the same file.
class FileTelemetryStore implements TelemetryStore {
  static const fileName = 'telemetry_queue.jsonl';

  static Future<void> _last = Future.value();

  final Future<Directory> Function() _directory;

  /// [directory] is the app documents directory; tests pass a temporary one.
  FileTelemetryStore([this._directory = getApplicationDocumentsDirectory]);

  Future<File> _file() async => File(join((await _directory()).path, fileName));

  /// Runs [operation] after every operation called before it, even if one of
  /// them failed.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _last.then((_) => operation());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<List<TelemetryEvent>> load() => _serialized(() async {
        final file = await _file();
        if (!await file.exists()) return [];
        return [
          for (final line in await file.readAsLines()) ?_decode(line),
        ];
      });

  @override
  Future<void> append(TelemetryEvent event) => _serialized(() async {
        await (await _file()).writeAsString(
          '${jsonEncode(event.toJson())}\n',
          mode: FileMode.append,
          flush: true,
        );
      });

  /// Broken lines are dropped too: they could never be sent.
  @override
  Future<void> remove(Iterable<String> eventIds) {
    final ids = eventIds.toSet();
    if (ids.isEmpty) return Future.value();
    return _serialized(() async {
      final file = await _file();
      if (!await file.exists()) return;
      final kept = [
        for (final line in await file.readAsLines())
          if (_decode(line) case final event? when !ids.contains(event.eventId))
            line,
      ];
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        kept.map((line) => '$line\n').join(),
        flush: true,
      );
      await tmp.rename(file.path);
    });
  }

  static TelemetryEvent? _decode(String line) {
    if (line.trim().isEmpty) return null;
    try {
      return TelemetryEvent.fromJson(jsonDecode(line) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Skipping a broken telemetry event: $e');
      return null;
    }
  }
}
