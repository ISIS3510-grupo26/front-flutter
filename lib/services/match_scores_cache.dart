import '../repositories/api_exception.dart';
import '../repositories/matches_repository.dart';
import 'hive_store.dart';

/// The compatibility % of every spot as the For You feed shows it.
class MatchScores {
  final Map<String, int> scores;
  final DateTime savedAt;

  /// True when the network failed and these are the ones saved on the phone.
  final bool offline;

  const MatchScores({required this.scores, required this.savedAt, this.offline = false});
}

/// Caching strategy: stale-while-revalidate, in two levels (memory and Hive).
///
/// [load] first gives the scores it already has, so the feed shows them at once, and then asks the backend and 
/// gives the new ones. If the saved ones are younger than [freshFor] it doesn't ask at all. If the network 
/// fails, the saved ones come back marked [MatchScores.offline].
class MatchScoresCache {
  /// Scores only change when the student edits their profile or someone
  /// reviews, so 2 minutes saves requests when going back and forth.
  static const freshFor = Duration(minutes: 2);

  final MatchesRepository _repository;
  final HiveStore _store;
  final DateTime Function() _now;

  final _memory = <String, MatchScores>{};

  /// Requests in progress by user. If the feed asks twice at the same time
  /// (preferences loaded + back from a place), both wait on one request.
  final _inFlight = <String, Future<Map<String, int>>>{};

    MatchScoresCache({
    required this._repository,
    required this._store,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// [force] skips the "still fresh" check (after editing preferences or writing a review the scores change, so they must be asked again).
  Stream<MatchScores> load(String userId, {bool force = false}) async* {
    final cached = _memory[userId] ?? _fromDisk(userId);
    if (cached != null) {
      _memory[userId] = cached;
      yield cached;
      if (!force && _now().difference(cached.savedAt) < freshFor) return;
    }
    try {
      final fresh = MatchScores(scores: await _fetch(userId), savedAt: _now());
      _memory[userId] = fresh;
      await _store.saveMatchScores(userId, SavedMatchScores(scores: fresh.scores, savedAt: fresh.savedAt));
      yield fresh;
    } catch (e) {
      // Only a missing connection falls back to the saved copy; a server error is a real problem and is not hidden.
      if (cached == null || !isNetworkError(e)) rethrow;
      yield MatchScores(scores: cached.scores, savedAt: cached.savedAt, offline: true);
    }
  }

  MatchScores? _fromDisk(String userId) {
    final saved = _store.matchScores(userId);
    return saved == null ? null : MatchScores(scores: saved.scores, savedAt: saved.savedAt);
  }

  Future<Map<String, int>> _fetch(String userId) =>
      _inFlight[userId] ??= _repository.fetchMatches(userId).whenComplete(() => _inFlight.remove(userId));
}
