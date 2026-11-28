import 'package:flutter/foundation.dart';

import '../models/best_time.dart';
import '../repositories/api_exception.dart';
import 'best_time_service.dart';
import 'lru_cache.dart';

/// [network]: no connection and nothing saved on the phone. [server]: the backend answered with an error, or 
/// with data the app couldn't read.
enum BestTimeFailure { network, server }

sealed class BestTimeState {
  const BestTimeState();
}

final class BestTimeLoading extends BestTimeState {
  const BestTimeLoading();
}

final class BestTimeLoaded extends BestTimeState {
  final BestTimeReport report;

  /// Set when there is no connection and this is the copy saved on the phone, when it was saved.
  final DateTime? offlineSavedAt;

  const BestTimeLoaded(this.report, {this.offlineSavedAt});
}

final class BestTimeFailed extends BestTimeState {
  final BestTimeFailure reason;

  const BestTimeFailed(this.reason);
}

/// Where the last report of each window is kept to show it offline. The app uses [WaitTimesStore] (SQLite); 
/// tests pass one in memory.
abstract class BestTimeStorage {
  Future<void> saveBestTimes(BestTimeReport report, {required DateTime savedAt});

  /// The last report saved for a window of [days] days, or null.
  Future<({BestTimeReport report, DateTime savedAt})?> readBestTimes(int days);
}

/// (BQ15) Loads "Best time to go": cache, then backend, then the phone copy.
class BestTimeLoader {
  final BestTimeService _service;
  final BestTimeStorage _storage;
  final DateTime Function() _now;
  final LruCache<int, BestTimeReport> _cache;

  /// Caching strategy: LRU cache keyed by the window (7 or 28 days), with capacity = 2 and ttl = 10 minutes. 
  /// The screen only offers two windows, so both fit and switching between the chips never calls the backend again.
  BestTimeLoader({
    required this._service,
    required this._storage,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        _cache = LruCache(capacity: 2, ttl: const Duration(minutes: 10), now: now ?? DateTime.now);

  /// Multithreading strategy: async/await. Each step waits for the previous one without blocking the UI thread. 
  /// [forceRefresh] (pull to refresh, the connection coming back) skips the cache.
  Future<BestTimeState> load({required int days, bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_cache.get(days) case final cached?) return BestTimeLoaded(cached);
    }
    final now = _now();
    try {
      final report = await _service.report(days: days, tzOffsetMinutes: now.timeZoneOffset.inMinutes);
      _cache.put(days, report);
      _saveForOffline(report, now);
      return BestTimeLoaded(report);
    } catch (e) {
      if (isNetworkError(e)) return _loadSaved(days);
      debugPrint("Couldn't load the best time to go: $e");
      return const BestTimeFailed(BestTimeFailure.server);
    }
  }

  /// Multithreading strategy: Future with handler. Writing to SQLite is not awaited, the screen shows the report 
  /// right away, and if the write fails only the offline copy is lost (.catchError).
  void _saveForOffline(BestTimeReport report, DateTime savedAt) {
    _storage
        .saveBestTimes(report, savedAt: savedAt)
        .catchError((Object e) => debugPrint("Couldn't save the best time to go offline: $e"));
  }

  /// Eventual connectivity: without network, the last copy of that window saved on the phone, with when it was 
  /// saved.
  Future<BestTimeState> _loadSaved(int days) async {
    try {
      if (await _storage.readBestTimes(days) case final saved?) {
        return BestTimeLoaded(saved.report, offlineSavedAt: saved.savedAt);
      }
    } catch (e) {
      debugPrint("Couldn't read the saved best time to go: $e");
    }
    return const BestTimeFailed(BestTimeFailure.network);
  }
}
