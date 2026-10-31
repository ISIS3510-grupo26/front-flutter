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
  final int? httpStatus;
  final String? errorType;
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
        httpStatus = null,
        errorType = null,
        occurredAt = DateTime.now().toUtc();

  /// BQ3: the student opened [spotId] from For You search results. The
  /// backend counts these as the restaurant's searches for that hour.
  TelemetryEvent.search({required String this.spotId, this.userId})
      : eventId = _newEventId(),
        screen = 'search',
        durationMs = 0,
        success = true,
        httpStatus = null,
        errorType = null,
        occurredAt = DateTime.now().toUtc();

  TelemetryEvent.restaurantDetail({
    required String this.spotId,
    required this.durationMs,
    required this.success,
    this.userId,
    this.httpStatus,
    this.errorType,
  })  : eventId = _newEventId(),
        screen = 'restaurant_detail',
        occurredAt = DateTime.now().toUtc();

  /// BQ14: one Taste Map load (or, at most once per load, its map images
  /// failing with [errorType] 'tiles_failed').
  TelemetryEvent.mapDisplay({
    this.userId,
    required this.success,
    this.errorType,
    required this.durationMs,
  })  : eventId = _newEventId(),
        screen = 'map_display',
        spotId = null,
        httpStatus = null,
        occurredAt = DateTime.now().toUtc();

  /// BQ13: one attempt to publish a review.
  TelemetryEvent.reviewSubmit({
    required String attemptId,
    required String this.spotId,
    this.userId,
    required this.success,
    required this.durationMs,
    required DateTime startedAt,
    this.httpStatus,
    this.errorType,
  })  : eventId = attemptId,
        screen = 'review_submit',
        occurredAt = startedAt.toUtc();

  /// Reads back an event written with [toJson] (the BQ14 offline outbox).
  /// Keeps the same eventId, so a resend is never counted twice.
  TelemetryEvent.fromJson(Map<String, dynamic> json)
      : eventId = json['eventId'] as String,
        screen = json['screen'] as String,
        spotId = json['spotId'] as String?,
        userId = json['userId'] as String?,
        durationMs = json['durationMs'] as int,
        success = json['success'] as bool,
        httpStatus = json['httpStatus'] as int?,
        errorType = json['errorType'] as String?,
        occurredAt = DateTime.parse(json['occurredAt'] as String);

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'screen': screen,
        'spotId': spotId,
        'userId': userId,
        'durationMs': durationMs,
        'success': success,
        if (httpStatus != null) 'httpStatus': httpStatus,
        if (errorType != null) 'errorType': errorType,
        'occurredAt': occurredAt.toIso8601String(),
      };

  static final _random = Random.secure();

  /// A new random id (also used for review attempts, BQ13).
  static String newId() => _newEventId();

  static String _newEventId() => [
        for (var i = 0; i < 16; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
}
