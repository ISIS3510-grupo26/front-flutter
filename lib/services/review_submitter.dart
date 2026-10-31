import '../models/spot_detail.dart';
import '../models/telemetry_event.dart';
import '../repositories/api_exception.dart';
import '../repositories/spots_repository.dart';
import 'hive_store.dart';

/// Publishes reviews and records every attempt for BQ13 ("how do crashes
/// while submitting a review affect the reviews that get published?").
class ReviewSubmitter {
  final SpotsRepository _repository;
  final HiveStore store;
  final String? Function() _currentUserId;

  /// Called after each attempt is recorded, to try to send its event now.
  final void Function() _onAttemptRecorded;

  ReviewSubmitter({
    required this._repository,
    required this.store,
    required this._currentUserId,
    void Function()? onAttemptRecorded,
  }) : _onAttemptRecorded = onAttemptRecorded ?? _nothing;

  static void _nothing() {}

  /// Throws the same errors as [SpotsRepository.postReview]; the screen decides what to tell the student.
  Future<ReviewResult> submit(String spotId, int stars, String text) async {
    final attempt = ReviewAttempt(
      attemptId: TelemetryEvent.newId(),
      spotId: spotId,
      userId: _currentUserId(),
      startedAt: DateTime.now().toUtc(),
    );
    // It has to be on disk before sending: if the app dies during the request this is the only trace left.
    await store.startAttempt(attempt);
    final watch = Stopwatch()..start();
    try {
      final result = await _repository.postReview(spotId, stars, text);
      await _finish(attempt, watch, success: true, httpStatus: 201);
      await store.deleteDraft(spotId);
      return result;
    } on ApiException catch (e) {
      await _finish(
        attempt,
        watch,
        success: false,
        httpStatus: e.statusCode,
        errorType: e.statusCode >= 500 ? 'server_error' : 'rejected',
      );
      // 409: the review already exists (for example, the server saved it just before a crash), so the draft isn't needed anymore.
      if (e.statusCode == 409) await store.deleteDraft(spotId);
      rethrow;
    } catch (e) {
      await _finish(attempt, watch, success: false, errorType: isNetworkError(e) ? 'network' : 'app_error');
      rethrow;
    }
  }

  Future<void> _finish(
    ReviewAttempt attempt,
    Stopwatch watch, {
    required bool success,
    int? httpStatus,
    String? errorType,
  }) async {
    await store.finishAttempt(TelemetryEvent.reviewSubmit(
      attemptId: attempt.attemptId,
      spotId: attempt.spotId,
      userId: attempt.userId,
      success: success,
      durationMs: watch.elapsedMilliseconds,
      startedAt: attempt.startedAt,
      httpStatus: httpStatus,
      errorType: errorType,
    ));
    _onAttemptRecorded();
  }
}
