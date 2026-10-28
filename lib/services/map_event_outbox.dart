import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../models/telemetry_event.dart';
import 'telemetry_queue.dart';

/// Local storage strategy: local file. Eventual connectivity: store and
/// forward.
///
/// While the phone is offline, BQ14 map events are appended to
/// `map_events.json` in the app documents directory (one JSON event per
/// line) instead of the in-memory [TelemetryQueue], which loses events when
/// the app is closed. When the connection comes back, and when the Taste Map
/// opens, every saved event is enqueued in the [TelemetryQueue] and the file
/// is deleted. So BQ14 data survives offline use and app restarts.
class MapEventOutbox {
  static const fileName = 'map_events.json';

  final Future<Directory> Function() _directory;

  /// [directory] is the app documents directory; tests pass a temporary one.
  const MapEventOutbox([this._directory = getApplicationDocumentsDirectory]);

  Future<File> _file() async => File(join((await _directory()).path, fileName));

  /// Adds [event] at the end of the file.
  Future<void> append(TelemetryEvent event) async {
    final file = await _file();
    await file.writeAsString(
      '${jsonEncode(event.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Enqueues every saved event in [queue] and deletes the file. Returns how
  /// many events were forwarded.
  Future<int> forwardTo(TelemetryQueue queue) async {
    final file = await _file();
    if (!await file.exists()) return 0;
    // Renamed first, so an event appended meanwhile starts a new file instead
    // of being deleted with this one.
    final sending = await file.rename('${file.path}.sending');
    var forwarded = 0;
    for (final line in await sending.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        queue.enqueue(TelemetryEvent.fromJson(jsonDecode(line) as Map<String, dynamic>));
        forwarded++;
      } catch (e) {
        debugPrint('Skipping a broken BQ14 event: $e');
      }
    }
    await sending.delete();
    return forwarded;
  }
}
