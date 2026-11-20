import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../models/spot.dart';
import '../models/spot_comparison.dart';
import '../models/spot_detail.dart';
import '../models/wait_time.dart';
import '../repositories/api_exception.dart';
import 'comparison_history.dart';
import 'local_database.dart';
import 'lru_cache.dart';

/// [network]: no connection and neither page is saved on the phone.
/// [server]: the backend answered with an error or with data the app
/// couldn't read; saved pages are not used then, so a real failure isn't
/// hidden behind old data.
enum CompareFailure { network, server }

sealed class CompareState {
  const CompareState();
}

final class CompareLoading extends CompareState {
  const CompareLoading();
}

final class CompareFailed extends CompareState {
  final CompareFailure reason;

  const CompareFailed(this.reason);
}

final class CompareLoaded extends CompareState {
  final SpotComparison comparison;

  /// Set when at least one page came from the phone because there was no
  /// network: when the oldest of them was saved.
  final DateTime? offlineSavedAt;

  /// Restaurants whose page is not available offline (never opened before).
  final Set<String> missingIds;

  const CompareLoaded({
    required this.comparison,
    this.offlineSavedAt,
    this.missingIds = const {},
  });

  /// True when the screen should reload by itself when the network returns.
  bool get needsNetwork => offlineSavedAt != null || missingIds.isNotEmpty;
}

typedef ComparisonBuilder = Future<SpotComparison> Function(
    ({CompareSideInput first, CompareSideInput second}) input);

/// Multithreading strategy: Isolate. Building the table reads two full pages
/// (with their reviews) and decides every row; it runs off the UI thread so
/// the screen never stutters while it opens.
Future<SpotComparison> buildComparisonInIsolate(
        ({CompareSideInput first, CompareSideInput second}) input) =>
    Isolate.run(() => buildSpotComparison(input));

/// Loads two restaurants and the current wait times and compares them.
///
/// - Multithreading: the two pages and the wait times are three independent
///   requests, so they run at the same time (Future.wait over a record), and
///   the comparison is built in an isolate.
/// - Caching: an LRU cache of pages (capacity 6, 5 minutes) and one of wait
///   times (one entry, 2 minutes). Comparing A with B and then A with C, or
///   going back and forth between Compare and a restaurant, does not ask for
///   the same page again.
/// - Eventual connectivity: without network each page comes from the copy
///   saved on the phone (SQLite `spot_details`) and the waits from the last
///   BQ4 list saved; a page that was never opened is reported as missing.
/// - Local storage: every complete comparison is saved in "Recent
///   comparisons" (SQLite `comparisons`).
class CompareLoader {
  final Future<SpotDetail> Function(String spotId) _fetchSpot;
  final SpotDetailStorage _details;
  final Future<List<LastWaitTime>> Function() _fetchWaits;
  final Future<List<LastWaitTime>?> Function() _savedWaits;
  final Future<void> Function(List<LastWaitTime> waits)? _saveWaits;
  final ComparisonHistoryStorage? _history;
  final ComparisonBuilder _build;
  final LruCache<String, SpotDetail> _pages;
  final LruCache<String, List<LastWaitTime>> _waits;
  final DateTime Function() _now;

  CompareLoader({
    required this._fetchSpot,
    required this._fetchWaits,
    this._details = const SqliteSpotDetailStorage(),
    this._savedWaits = _noSavedWaits,
    this._saveWaits,
    this._history,
    this._build = buildComparisonInIsolate,
    LruCache<String, SpotDetail>? pages,
    LruCache<String, List<LastWaitTime>>? waits,
    DateTime Function()? now,
  })  : _pages = pages ?? LruCache(capacity: 6, ttl: const Duration(minutes: 5)),
        _waits = waits ?? LruCache(capacity: 1, ttl: const Duration(minutes: 2)),
        _now = now ?? DateTime.now;

  static Future<List<LastWaitTime>?> _noSavedWaits() async => null;

  /// [catalog] gives the name and emoji of a side whose page is missing;
  /// [matchScores] the student's compatibility (smart feature), if loaded.
  /// [forceRefresh] skips the memory cache (Retry, reconnection).
  Future<CompareState> load(
    String firstId,
    String secondId, {
    Map<String, int>? matchScores,
    List<Spot> catalog = const [],
    bool forceRefresh = false,
  }) async {
    final (first, second, waits) = await (
      _page(firstId, forceRefresh),
      _page(secondId, forceRefresh),
      _latestWaits(forceRefresh),
    ).wait;

    if (first.serverError || second.serverError) return const CompareFailed(CompareFailure.server);
    if (first.spot == null && second.spot == null) return const CompareFailed(CompareFailure.network);

    CompareSideInput side(String id, _Page page) {
      final fromCatalog = catalog.where((s) => s.id == id).firstOrNull;
      final wait = waits[id];
      return CompareSideInput(
        id: id,
        detail: page.spot?.toJson(),
        match: matchScores?[id],
        waitMinutes: wait != null && wait.isRecent ? wait.minutes : null,
        fallbackName: fromCatalog?.name ?? id,
        fallbackEmoji: fromCatalog?.emoji ?? '🍽️',
      );
    }

    final comparison = await _build((first: side(firstId, first), second: side(secondId, second)));
    final saved = [first.savedAt, second.savedAt].nonNulls.toList()..sort();
    if (comparison.complete) _remember(comparison);
    return CompareLoaded(
      comparison: comparison,
      offlineSavedAt: saved.firstOrNull,
      missingIds: {
        if (first.spot == null) firstId,
        if (second.spot == null) secondId,
      },
    );
  }

  /// Memory, then network (and saved on the phone), then the saved copy if
  /// there is no network.
  Future<_Page> _page(String id, bool forceRefresh) async {
    if (!forceRefresh) {
      if (_pages.get(id) case final cached?) return _Page(spot: cached);
    }
    try {
      final spot = await _fetchSpot(id);
      _pages.put(id, spot);
      // Future with handler: fire-and-forget, the comparison never waits for the disk.
      _details.save(spot).catchError((Object e) => debugPrint("Couldn't save $id offline: $e"));
      return _Page(spot: spot);
    } catch (error) {
      if (!isNetworkError(error)) return const _Page(serverError: true);
      try {
        final saved = await _details.read(id);
        return _Page(spot: saved?.spot, savedAt: saved?.savedAt);
      } catch (e) {
        debugPrint("Couldn't read $id offline: $e");
        return const _Page();
      }
    }
  }

  /// spotId -> last wait. A failure here never fails the comparison: the
  /// "Wait now" row just says there is no recent report.
  Future<Map<String, LastWaitTime>> _latestWaits(bool forceRefresh) async {
    List<LastWaitTime>? waits = forceRefresh ? null : _waits.get('latest');
    if (waits == null) {
      try {
        waits = await _fetchWaits();
        _waits.put('latest', waits);
        _saveWaits?.call(waits).catchError((Object e) => debugPrint("Couldn't save the waits: $e"));
      } catch (error) {
        waits = isNetworkError(error) ? await _savedWaits().catchError((Object _) => null) : null;
      }
    }
    return {for (final w in waits ?? const <LastWaitTime>[]) w.spotId: w};
  }

  void _remember(SpotComparison c) {
    _history
        ?.save(ComparisonEntry(
          firstId: c.firstId,
          secondId: c.secondId,
          firstName: c.firstName,
          secondName: c.secondName,
          firstEmoji: c.firstEmoji,
          secondEmoji: c.secondEmoji,
          comparedAt: _now(),
        ))
        .catchError((Object e) => debugPrint("Couldn't save the comparison: $e"));
  }
}

class _Page {
  final SpotDetail? spot;
  final DateTime? savedAt;
  final bool serverError;

  const _Page({this.spot, this.savedAt, this.serverError = false});
}
