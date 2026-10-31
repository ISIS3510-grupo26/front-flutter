import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/telemetry_event.dart';
import '../repositories/api_exception.dart';
import 'telemetry_store.dart';

/// Device fields the backend requires on every telemetry event.
class DeviceContext {
  final String model;
  final String osVersion;

  const DeviceContext({required this.model, required this.osVersion});

  static Future<DeviceContext> load() async {
    final info = await DeviceInfoPlugin().androidInfo;
    return DeviceContext(model: info.model, osVersion: info.version.release);
  }

  Map<String, dynamic> toJson() => {
        'deviceModel': model,
        'osName': 'android',
        'osVersion': osVersion,
        'platform': 'flutter',
      };
}

/// Collects telemetry events in memory and sends them in batches in the
/// background. Failed sends are retried on the next flush, with the same
/// eventId, so the backend never counts an event twice.
///
/// With a [TelemetryStore], every queued event is also saved on disk until
/// the backend answers for it, and [restore] puts back what a previous run
/// could not send. Without one (tests), events are lost if the app is killed
/// before they are sent.
///
/// With a connectivity stream, the queue is sent as soon as the phone is back
/// online; the timer stays as a fallback.
class TelemetryQueue {
  static const _maxBatch = 100;
  static const _maxQueued = 500;

  final http.Client _client;
  final String _baseUrl;
  final Future<DeviceContext> Function() _loadDevice;
  final TelemetryStore? _store;
  late final Future<DeviceContext> _device = _loadDevice();
  late final Timer _timer;
  late final StreamSubscription<List<ConnectivityResult>>? _connectivity;

  final _queue = <TelemetryEvent>[];
  bool _flushing = false;
  Future<void>? _restoring;

  /// Unknown until the stream's first value, which counts as coming back
  /// online: that first value also sends what [restore] put back.
  bool _online = false;

  /// [connectivity] is `Connectivity().onConnectivityChanged`; tests pass
  /// their own stream.
  TelemetryQueue({
    required this._client,
    this._baseUrl = ApiConfig.baseUrl,
    this._loadDevice = DeviceContext.load,
    this._store,
    Stream<List<ConnectivityResult>>? connectivity,
    Duration flushInterval = const Duration(seconds: 15),
  }) {
    _timer = Timer.periodic(flushInterval, (_) => flush());
    _connectivity = connectivity?.listen(_onConnectivityChanged);
  }

  /// Multithreading strategy: Stream. Eventual connectivity: what was queued
  /// offline goes out when the connection comes back, without waiting up to
  /// a whole timer interval.
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online && !_online) flush();
    _online = online;
  }

  int get pending => _queue.length;

  /// Queues [event] and saves it without waiting for the disk.
  void enqueue(TelemetryEvent event) => _add(event);

  /// Queues every event in [events] and completes once they are saved on
  /// disk, for callers that delete their own copy afterwards.
  Future<void> enqueueAll(Iterable<TelemetryEvent> events) =>
      Future.wait([for (final event in events) _add(event)]);

  /// Future with handler: the write runs in the background and a disk failure
  /// is only logged, so it never reaches the UI; the event stays queued in
  /// memory and is still sent.
  Future<void> _add(TelemetryEvent event) {
    if (_queue.any((queued) => queued.eventId == event.eventId)) {
      return Future.value();
    }
    _queue.add(event);
    final saved = _store?.append(event).catchError(
          (Object e) => debugPrint("Couldn't save a telemetry event: $e"),
        );
    _trim();
    return saved ?? Future.value();
  }

  /// Puts back, oldest first, the events a previous run saved and could not
  /// send. Events already queued are not added twice. Never throws.
  Future<void> restore() {
    final store = _store;
    if (store == null) return Future.value();
    return _restoring ??= store.load().then((saved) {
      final ids = {for (final event in _queue) event.eventId};
      _queue.insertAll(0, [
        for (final event in saved)
          if (ids.add(event.eventId)) event,
      ]);
      _trim();
    }).catchError(
      (Object e) => debugPrint("Couldn't restore saved telemetry: $e"),
    );
  }

  /// Over the limit, the oldest events are dropped, from the disk too.
  void _trim() {
    final extra = _queue.length - _maxQueued;
    if (extra <= 0) return;
    final dropped = _queue.sublist(0, extra);
    _queue.removeRange(0, extra);
    _forget(dropped);
  }

  void _forget(List<TelemetryEvent> events) {
    _store
        ?.remove(events.map((event) => event.eventId))
        .catchError((Object e) => debugPrint("Couldn't remove sent telemetry: $e"));
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      // Restored events go first, and an event sent meanwhile can't be
      // restored again after it was removed from the disk.
      if (_restoring case final restoring?) await restoring;
      if (_queue.isEmpty) return;

      final batch = _queue.take(_maxBatch).toList();
      final device = (await _device).toJson();
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/telemetry/page-loads'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'events': [
                for (final event in batch) {...event.toJson(), ...device},
              ],
            }),
          )
          .timeout(apiTimeout);

      final status = response.statusCode;
      // Kept in memory and on disk for the next flush.
      if (status >= 500) return;
      // A 4xx means the batch itself is invalid, so resending it can't succeed.
      if (status != 202) {
        debugPrint('Telemetry batch rejected ($status): ${response.body}');
      }
      final sent = batch.toSet();
      _queue.removeWhere(sent.contains);
      _forget(batch);
    } on Exception catch (e) {
      debugPrint('Telemetry flush failed, will retry: $e');
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _timer.cancel();
    _connectivity?.cancel();
  }
}
