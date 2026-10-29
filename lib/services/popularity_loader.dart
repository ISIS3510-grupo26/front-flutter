import 'package:flutter/foundation.dart';

import '../models/hourly_ranking.dart';
import '../repositories/api_exception.dart';
import 'lru_cache.dart';
import 'popularity_prefs.dart';
import 'popularity_service.dart';

/// [network]: no connection and nothing saved on the phone. [server]: the
/// backend answered with an error, or with data the app couldn't read.
enum PopularityFailure { network, server }

sealed class PopularityState {
  const PopularityState();
}

final class PopularityLoading extends PopularityState {
  const PopularityLoading();
}

/// Nobody was active at [hour], so there is nothing to show.
final class PopularityEmpty extends PopularityState {
  final int hour;

  const PopularityEmpty(this.hour);
}

final class PopularityLoaded extends PopularityState {
  final HourlyRanking ranking;

  /// Set when the network failed and this is the ranking saved on the phone
  /// at that time; null when it is fresh. Its hour may be earlier than now.
  final DateTime? offlineSavedAt;

  const PopularityLoaded(this.ranking, {this.offlineSavedAt});
}

final class PopularityFailed extends PopularityState {
  final PopularityFailure reason;

  const PopularityFailed(this.reason);
}

/// Loads the "Popular right now" ranking for the phone's current hour.
///
/// The loader owns the clock: one reading decides both which hour to ask for
/// and how old cached entries are, so the request and the cache always agree
/// on what "now" is. Tests inject a fake [now].
class PopularityLoader {
  final PopularityService _service;
  final PopularityPrefs _prefs;
  final DateTime Function() _now;
  final LruCache<int, HourlyRanking> _cache;

  /// Caching strategy: LRU cache keyed by hour, with capacity = 24 and
  /// ttl = 5 minutes. There are only 24 possible hours, so every hour fits
  /// and nothing useful is ever evicted. Within an hour the ranking only
  /// changes as new views and searches trickle in, so reopening For You in
  /// the next few minutes reuses it without calling the backend.
  PopularityLoader({
    required this._service,
    required this._prefs,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        _cache = LruCache(
          capacity: 24,
          ttl: const Duration(minutes: 5),
          now: now ?? DateTime.now,
        );

  /// Multithreading strategy: async/await. The network call and its parsing
  /// (which runs in an isolate) are awaited without blocking the UI thread.
  Future<PopularityState> load() async {
    final now = _now();
    final hour = now.hour;
    if (_cache.get(hour) case final cached?) return _stateFor(cached);

    try {
      final ranking = await _service.rankingAt(
        hour: hour,
        tzOffsetMinutes: now.timeZoneOffset.inMinutes,
      );
      _cache.put(hour, ranking);
      _saveForOffline(ranking, now);
      return _stateFor(ranking);
    } catch (e) {
      if (isNetworkError(e)) return _loadSaved();
      debugPrint("Couldn't load Popular right now: $e");
      return const PopularityFailed(PopularityFailure.server);
    }
  }

  static PopularityState _stateFor(HourlyRanking ranking, {DateTime? offlineSavedAt}) =>
      ranking.isEmpty
          ? PopularityEmpty(ranking.hour)
          : PopularityLoaded(ranking, offlineSavedAt: offlineSavedAt);

  /// Multithreading strategy: Future with handler. Saving for offline use is
  /// fire-and-forget with .catchError(): For You shows the ranking right away
  /// and never waits for the disk. If the write fails, only the offline copy
  /// is lost.
  void _saveForOffline(HourlyRanking ranking, DateTime savedAt) {
    _prefs
        .save(ranking, savedAt: savedAt)
        .catchError((Object e) => debugPrint("Couldn't save Popular right now offline: $e"));
  }

  /// Eventual connectivity: without network, the last ranking saved on the
  /// phone, with when it was saved. Only with nothing saved is it a network
  /// failure.
  Future<PopularityState> _loadSaved() async {
    try {
      if (await _prefs.read() case final last?) {
        return _stateFor(last.ranking, offlineSavedAt: last.savedAt);
      }
    } catch (e) {
      debugPrint("Couldn't read the offline Popular right now: $e");
    }
    return const PopularityFailed(PopularityFailure.network);
  }
}
