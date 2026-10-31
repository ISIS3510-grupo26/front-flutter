import 'package:flutter/foundation.dart';

import '../models/best_for_you.dart';
import '../repositories/api_exception.dart';
import 'best_for_you_service.dart';
import 'local_database.dart';
import 'lru_cache.dart';

/// [network]: no connection and nothing saved on the phone. [server]: the
/// backend answered with an error, or with data the app couldn't read.
enum BestForYouFailure { network, server }

sealed class BestForYouState {
  const BestForYouState();
}

final class BestForYouLoading extends BestForYouState {
  const BestForYouLoading();
}

final class BestForYouLoaded extends BestForYouState {
  final BestForYouRanking ranking;

  /// Set when the network failed and this is the ranking saved on the phone
  /// at that time; null when it is fresh.
  final DateTime? offlineSavedAt;

  const BestForYouLoaded(this.ranking, {this.offlineSavedAt});
}

final class BestForYouFailed extends BestForYouState {
  final BestForYouFailure reason;

  const BestForYouFailed(this.reason);
}

/// Loads "Best for you right now" (BQ6) for the student's taste profile.
class BestForYouLoader {
  final BestForYouService _service;
  final BestForYouStorage _storage;
  final DateTime Function() _now;
  final LruCache<BestForYouProfile, BestForYouRanking> _cache;

  /// Caching strategy: LRU cache keyed by taste profile, with capacity = 4
  /// and ttl = 2 minutes. The ranking depends on the profile, so the profile
  /// is the key. A student changes it a few times in a session at most (for
  /// example trying Vegan and going back), so four entries let them return
  /// to a recent profile without calling the backend, and the least recently
  /// used one is evicted. The ttl is short because the order depends on wait
  /// times students report minute by minute (BQ4): after two minutes a new
  /// report may have changed it.
  BestForYouLoader({
    required this._service,
    required this._storage,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _cache = LruCache(
         capacity: 4,
         ttl: const Duration(minutes: 2),
         now: now ?? DateTime.now,
       );

  /// Multithreading strategy: async/await. The steps read in order without
  /// blocking the UI thread: cache, network, then the copy saved on the
  /// phone. [forceRefresh] (pull to refresh, the connection coming back)
  /// skips the cache.
  Future<BestForYouState> load(
    BestForYouProfile profile, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      if (_cache.get(profile) case final cached?) return BestForYouLoaded(cached);
    }

    try {
      final ranking = await _service.ranking(profile);
      _cache.put(profile, ranking);
      _saveForOffline(ranking);
      return BestForYouLoaded(ranking);
    } catch (e) {
      if (isNetworkError(e)) return _loadSaved();
      debugPrint("Couldn't load Best for you right now: $e");
      return const BestForYouFailed(BestForYouFailure.server);
    }
  }

  /// Multithreading strategy: Future with handler. The SQLite write is
  /// fire-and-forget with .then() and .catchError(): For You shows the
  /// ranking right away and never waits for the disk. If the write fails,
  /// only the offline copy is lost.
  void _saveForOffline(BestForYouRanking ranking) {
    _storage
        .save(ranking, savedAt: _now())
        .then((_) => debugPrint('Best for you saved for offline use'))
        .catchError(
          (Object e) => debugPrint("Couldn't save Best for you offline: $e"),
        );
  }

  /// Eventual connectivity: without network, the last ranking saved on the
  /// phone, with when it was saved. With nothing saved, it is a network
  /// failure. A server error never gets here: the student isn't offline, and
  /// old data would hide the real problem.
  Future<BestForYouState> _loadSaved() async {
    try {
      if (await _storage.read() case final saved?) {
        return BestForYouLoaded(saved.ranking, offlineSavedAt: saved.savedAt);
      }
    } catch (e) {
      debugPrint("Couldn't read the offline Best for you: $e");
    }
    return const BestForYouFailed(BestForYouFailure.network);
  }
}
