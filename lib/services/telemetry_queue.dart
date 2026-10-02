import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/telemetry_event.dart';
import '../repositories/api_exception.dart';

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
/// background. Failed sends are retried on the next flush; events are lost
/// if the app is killed before they are sent.
class TelemetryQueue {
  static const _maxBatch = 100;
  static const _maxQueued = 500;

  final http.Client _client;
  final String _baseUrl;
  final Future<DeviceContext> Function() _loadDevice;
  late final Future<DeviceContext> _device = _loadDevice();
  late final Timer _timer;

  final _queue = <TelemetryEvent>[];
  bool _flushing = false;

  TelemetryQueue({
    required this._client,
    this._baseUrl = ApiConfig.baseUrl,
    this._loadDevice = DeviceContext.load,
    Duration flushInterval = const Duration(seconds: 15),
  }) {
    _timer = Timer.periodic(flushInterval, (_) => flush());
  }

  int get pending => _queue.length;

  void enqueue(TelemetryEvent event) {
    _queue.add(event);
    if (_queue.length > _maxQueued) _queue.removeAt(0);
  }

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
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
      if (status >= 500) return;
      // A 4xx means the batch itself is invalid, so resending it can't succeed.
      if (status != 202) {
        debugPrint('Telemetry batch rejected ($status): ${response.body}');
      }
      final sent = batch.toSet();
      _queue.removeWhere(sent.contains);
    } on Exception catch (e) {
      debugPrint('Telemetry flush failed, will retry: $e');
    } finally {
      _flushing = false;
    }
  }

  void dispose() => _timer.cancel();
}
