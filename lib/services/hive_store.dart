import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/telemetry_event.dart';

/// A review the student started writing and hasn't published.
class ReviewDraft {
  final int stars;
  final String text;
  final DateTime savedAt;

  const ReviewDraft({required this.stars, required this.text, required this.savedAt});

  bool get isEmpty => stars == 0 && text.trim().isEmpty;

  Map<String, dynamic> toMap() => {
        'stars': stars,
        'text': text,
        'savedAt': savedAt.toUtc().toIso8601String(),
      };

  factory ReviewDraft.fromMap(Map<dynamic, dynamic> map) => ReviewDraft(
        stars: map['stars'] as int,
        text: map['text'] as String,
        savedAt: DateTime.parse(map['savedAt'] as String),
      );
}

/// An attempt to publish a review that started and hasn't finished yet.
/// If one is still saved when the app opens, the app closed while sending.
class ReviewAttempt {
  final String attemptId;
  final String spotId;
  final String? userId;
  final DateTime startedAt;

  const ReviewAttempt({
    required this.attemptId,
    required this.spotId,
    required this.userId,
    required this.startedAt,
  });

  Map<String, dynamic> toMap() => {
        'spotId': spotId,
        'userId': userId,
        'startedAt': startedAt.toUtc().toIso8601String(),
      };

  factory ReviewAttempt.fromMap(String attemptId, Map<dynamic, dynamic> map) => ReviewAttempt(
        attemptId: attemptId,
        spotId: map['spotId'] as String,
        userId: map['userId'] as String?,
        startedAt: DateTime.parse(map['startedAt'] as String),
      );
}

/// The compatibility % of every spot and when it came from the backend.
class SavedMatchScores {
  final Map<String, int> scores;
  final DateTime savedAt;

  const SavedMatchScores({required this.scores, required this.savedAt});
}

/// Local storage strategy: Hive, a key-value (NoSQL) database.
///
/// Everything saved here is a small document looked up by one key: the draft
/// of a spot, an attempt by its id, a BQ13 event by its id, the match scores
/// of a user. There are no relations or queries, so tables (SQLite) would only
/// add a schema to maintain. Each kind of document has its own box (a file).
/// After a box is opened its content stays in memory, so reads like
/// [draft] are synchronous: the review screen shows the draft right away.
class HiveStore {
  static const draftsBox = 'review_drafts';
  static const attemptsBox = 'review_attempts';
  static const eventsBox = 'review_events';
  static const matchesBox = 'match_scores';

  /// Old BQ13 events are dropped after this, so the box can't grow forever
  /// if the phone stays offline.
  static const maxEvents = 200;

  final Box<Map> _drafts;
  final Box<Map> _attempts;
  final Box<Map> _events;
  final Box<Map> _matches;

  HiveStore._(this._drafts, this._attempts, this._events, this._matches);

  /// Opens the four boxes at the same time with Future.wait (they are
  /// independent files, so there's no reason to open them one by one).
  /// [directory] is the app documents directory; tests pass a temporary one.
  static Future<HiveStore> open({String? directory}) async {
    Hive.init(directory ?? (await getApplicationDocumentsDirectory()).path);
    final boxes = await Future.wait([
      Hive.openBox<Map>(draftsBox),
      Hive.openBox<Map>(attemptsBox),
      Hive.openBox<Map>(eventsBox),
      Hive.openBox<Map>(matchesBox),
    ]);
    return HiveStore._(boxes[0], boxes[1], boxes[2], boxes[3]);
  }

  // ---------- Drafts ----------

  ReviewDraft? draft(String spotId) {
    final map = _drafts.get(spotId);
    return map == null ? null : ReviewDraft.fromMap(map);
  }

  bool hasDraft(String spotId) => _drafts.containsKey(spotId);

  /// An empty draft (no stars, no text) is deleted instead of saved.
  Future<void> saveDraft(String spotId, ReviewDraft draft) =>
      draft.isEmpty ? _drafts.delete(spotId) : _drafts.put(spotId, draft.toMap());

  Future<void> deleteDraft(String spotId) => _drafts.delete(spotId);

  // ---------- BQ13: attempts and their events ----------

  Future<void> startAttempt(ReviewAttempt attempt) => _attempts.put(attempt.attemptId, attempt.toMap());

  List<ReviewAttempt> get openAttempts => [
        for (final key in _attempts.keys)
          ReviewAttempt.fromMap(key as String, _attempts.get(key)!),
      ];

  /// Saves the result of an attempt and only then forgets the attempt. In this order, if the app dies in 
  /// between, [recoverCrashedAttempts] sees the event already saved and doesn't report a crash on top of it.
  Future<void> finishAttempt(TelemetryEvent outcome) async {
    await _saveEvent(outcome);
    await _attempts.delete(outcome.eventId);
  }

  /// Called once when the app starts, before anything can be sending: every attempt still saved is one the 
  /// app never finished, so it becomes a 'crash' event. Returns how many crashes were found.
  Future<int> recoverCrashedAttempts() async {
    var crashes = 0;
    for (final attempt in openAttempts) {
      if (!_events.containsKey(attempt.attemptId)) {
        await _saveEvent(TelemetryEvent.reviewSubmit(
          attemptId: attempt.attemptId,
          spotId: attempt.spotId,
          userId: attempt.userId,
          success: false,
          durationMs: 0,
          startedAt: attempt.startedAt,
          errorType: 'crash',
        ));
        crashes++;
      }
      await _attempts.delete(attempt.attemptId);
    }
    return crashes;
  }

  /// BQ13 events waiting to be sent that the backend will accept with the  current session, the ones of 
  /// [userId] and the ones without a user. Events of another account wait until that account signs in again.
  List<TelemetryEvent> pendingEvents({required String? userId, int limit = 100}) => _events.values
      .map((map) => TelemetryEvent.fromJson(Map<String, dynamic>.from(map)))
      .where((event) => event.userId == null || event.userId == userId)
      .take(limit)
      .toList();

  int get pendingEventCount => _events.length;

  Future<void> removeEvents(Iterable<String> eventIds) => _events.deleteAll(eventIds);

  Future<void> _saveEvent(TelemetryEvent event) async {
    await _events.put(event.eventId, event.toJson());
    if (_events.length <= maxEvents) return;
    final oldestFirst = _events.values
        .map((map) => TelemetryEvent.fromJson(Map<String, dynamic>.from(map)))
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    await _events.deleteAll(oldestFirst.take(_events.length - maxEvents).map((e) => e.eventId));
  }

  // ---------- Match scores (caching) ----------

  SavedMatchScores? matchScores(String userId) {
    final map = _matches.get(userId);
    if (map == null) return null;
    return SavedMatchScores(
      scores: (map['scores'] as Map).map((spot, score) => MapEntry(spot as String, score as int)),
      savedAt: DateTime.parse(map['savedAt'] as String),
    );
  }

  Future<void> saveMatchScores(String userId, SavedMatchScores saved) => _matches.put(userId, {
        'scores': saved.scores,
        'savedAt': saved.savedAt.toUtc().toIso8601String(),
      });
}
