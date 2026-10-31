import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../repositories/api_exception.dart';
import 'hive_store.dart';
import 'telemetry_queue.dart';

/// Eventual connectivity: store and forward for the BQ13 events.
///
/// The events stay in Hive until the backend answers 202, and only then are
/// they deleted, so a crash (exactly the moment the app closes) loses nothing.
/// [flush] is called when the app opens, after each attempt and when the connection comes back.
class ReviewEventOutbox {
  final http.Client _client;
  final HiveStore _store;
  final String? Function() _currentUserId;
  final String _baseUrl;
  final Future<DeviceContext> Function() _loadDevice;
  late final Future<DeviceContext> _device = _loadDevice();

  /// The send in progress. Several calls can arrive together (app opens and
  /// the connection comes back at the same time); they all get this same
  /// Future instead of sending the same events twice.
  Future<int>? _running;

  ReviewEventOutbox({
    required this._client,
    required this._store,
    required this._currentUserId,
    this._baseUrl = ApiConfig.baseUrl,
    this._loadDevice = DeviceContext.load,
  });

  /// Sends the pending events of the current user. Returns how many left
  /// the phone (0 if there was nothing or the network failed).
  Future<int> flush() => _running ??= _send().whenComplete(() => _running = null);

  Future<int> _send() async {
    final batch = _store.pendingEvents(userId: _currentUserId());
    if (batch.isEmpty) return 0;
    try {
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
      if (response.statusCode >= 500) return 0; // server down: they stay saved for the next try
      // 4xx: the batch itself is wrong, sending it again won't fix it.
      if (response.statusCode != 202) {
        debugPrint('BQ13 events rejected (${response.statusCode}): ${response.body}');
      }
      await _store.removeEvents(batch.map((event) => event.eventId));
      return batch.length;
    } on Exception catch (e) {
      if (!isNetworkError(e)) debugPrint('BQ13 events not sent: $e');
      return 0;
    }
  }
}
