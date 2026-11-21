import '../models/telemetry_event.dart';

/// BQ8: the review actions of one visit to a restaurant page. Each action is
/// sent the first time it happens in the visit; later ones are ignored here,
/// and their eventId would be the same anyway.
///
/// The visit is the restaurant_detail event of the page ([visitEventId]), so
/// opening "All reviews" twice from the same page counts one open_all.
class ReviewInteractionTracker {
  final String spotId;
  final String visitEventId;
  final String? Function() _currentUserId;
  final void Function(TelemetryEvent event) _send;
  final _sent = <ReviewAction>{};

  ReviewInteractionTracker({
    required this.spotId,
    required this.visitEventId,
    required this._currentUserId,
    required this._send,
  });

  void record(ReviewAction action) {
    if (!_sent.add(action)) return;
    _send(TelemetryEvent.reviewInteraction(
      spotId: spotId,
      visitEventId: visitEventId,
      action: action,
      userId: _currentUserId(),
    ));
  }
}
