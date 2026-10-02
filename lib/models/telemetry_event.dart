import 'dart:math';

/// One event for `POST /telemetry/page-loads`. Device fields are added when
/// the batch is sent (see TelemetryQueue).
class TelemetryEvent {
  final String eventId;
  final String screen;
  final String? spotId;
  final String? userId;
  final int durationMs;
  final bool success;
  final DateTime occurredAt;

  /// BQ7: [userId] saved [spotId]. The backend rejects the whole batch if a
  /// favorite_added event lacks either, so both are required here.
  TelemetryEvent.favoriteAdded({
    required String this.userId,
    required String this.spotId,
  })  : eventId = _newEventId(),
        screen = 'favorite_added',
        durationMs = 0,
        success = true,
        occurredAt = DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'screen': screen,
        'spotId': spotId,
        'userId': userId,
        'durationMs': durationMs,
        'success': success,
        'occurredAt': occurredAt.toIso8601String(),
      };

  static final _random = Random.secure();

  static String _newEventId() => [
        for (var i = 0; i < 16; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
}
