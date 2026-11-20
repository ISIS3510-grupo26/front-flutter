import 'package:flutter/foundation.dart';

import '../data/spots_data.dart';
import '../models/spot.dart';
import '../models/telemetry_event.dart';
import '../repositories/api_exception.dart';
import '../repositories/favorites_repository.dart';
import 'favorites_local_store.dart';
import 'telemetry_queue.dart';

/// Whether the saved state on screen is the server's yet.
///
/// [offline]: no network, the screen shows the copy saved on the phone.
/// [failed]: the server answered with an error (or something unreadable);
/// that is not "offline", so the copy is not presented as if it were.
enum FavoritesSync { loading, loaded, offline, failed }

/// Owns the spots shown across the app and their saved state, keeping it in
/// sync with the server for the current user. Without a user, saving is
/// local only.
///
/// With a [FavoritesLocalStore] it is offline-first: the saved state starts
/// from the copy on the phone, a save without network is kept and sent when
/// the connection comes back. Without one, nothing starts out saved: the
/// saved state is only ever what the server says.
class FavoritesController extends ChangeNotifier {
  final FavoritesRepository _repository;
  final TelemetryQueue _telemetry;
  final String? Function() _currentUserId;
  final FavoritesLocalStore? _local;
  final _inFlight = <String>{};
  List<Spot> _spots;
  FavoritesSync _sync = FavoritesSync.loading;
  bool _sendingPending = false;

  FavoritesController({
    required this._repository,
    required this._telemetry,
    required this._currentUserId,
    FavoritesLocalStore? local,
    List<Spot>? spots,
  })  : _local = local,
        _spots = [
          for (final spot in spots ?? sampleSpots)
            spot.copyWith(isSaved: local?.savedIds.contains(spot.id) ?? false),
        ];

  List<Spot> get spots => _spots;

  FavoritesSync get sync => _sync;

  bool get isOffline => _sync == FavoritesSync.offline;

  /// When the copy on the phone came from the server (shown while offline).
  DateTime? get copySavedAt => _local?.syncedAt;

  /// Spots changed offline that the server doesn't have yet.
  Set<String> get pendingIds => _local?.pendingIds ?? const {};

  /// The catalog spot with [id], or null if the app doesn't know it.
  Spot? spotById(String id) {
    for (final spot in _spots) {
      if (spot.id == id) return spot;
    }
    return null;
  }

  /// Replaces local saved state with the server's (plus the changes still
  /// pending or in flight), and the copy on the phone with it.
  ///
  /// Without network and with a local store, [sync] becomes
  /// [FavoritesSync.offline] and the copy stays on screen. Any other failure
  /// is [FavoritesSync.failed] and the error is rethrown.
  Future<void> syncFromServer() async {
    final userId = _currentUserId();
    if (userId == null) return _setSync(FavoritesSync.loaded);
    _setSync(FavoritesSync.loading);
    final Set<String> savedIds;
    try {
      savedIds = await _repository.fetchFavoriteIds(userId);
    } on Exception catch (e) {
      if (_local != null && isNetworkError(e)) return _setSync(FavoritesSync.offline);
      _setSync(FavoritesSync.failed);
      rethrow;
    }
    final pending = {for (final p in _local?.pending ?? <PendingFavorite>[]) p.spotId: p.desired};
    _spots = [
      for (final spot in _spots)
        _inFlight.contains(spot.id)
            ? spot
            : spot.copyWith(isSaved: pending[spot.id] ?? savedIds.contains(spot.id)),
    ];
    await _local?.replaceAll(_spots.where((s) => s.isSaved));
    _setSync(FavoritesSync.loaded);
  }

  /// Flips [spotId]'s saved state right away (screen and phone), then saves
  /// it to the server. Without network the change stays and is queued for
  /// [sendPending]; any other failure rolls it back and is rethrown.
  /// Taps on a spot whose previous change is still in flight are ignored.
  Future<void> toggleSaved(String spotId) async {
    if (!_inFlight.add(spotId)) return;
    final spot = _spots.firstWhere((s) => s.id == spotId);
    final save = !spot.isSaved;
    _setSaved(spotId, save);
    try {
      final userId = _currentUserId();
      if (userId == null) return;
      await _local?.setSaved(spot, save);
      await _send(userId, spotId, save);
      await _local?.dropPending(spotId);
    } on Exception catch (e) {
      if (_local case final local? when isNetworkError(e)) {
        await local.queue(spotId, desired: save); // the heart stays as the student left it
        notifyListeners();
        return;
      }
      _setSaved(spotId, !save);
      await _local?.setSaved(spot, !save);
      rethrow;
    } finally {
      _inFlight.remove(spotId);
    }
  }

  /// Eventual connectivity: sends the changes made offline, one by one with
  /// async/await, and forgets each one only after the server got it.
  /// Stops at the first network error (still offline: the rest wait).
  /// Returns how many were sent.
  Future<int> sendPending() async {
    final userId = _currentUserId();
    final local = _local;
    if (userId == null || local == null || _sendingPending) return 0;
    _sendingPending = true;
    var sent = 0;
    try {
      for (final change in local.pending) {
        if (_inFlight.contains(change.spotId)) continue;
        try {
          await _send(userId, change.spotId, change.desired);
          await local.markSent(change);
          sent++;
        } on Exception catch (e) {
          if (isNetworkError(e)) break;
          // 5xx: the server may recover, so the change waits for next time.
          // Another 4xx won't get better by retrying (e.g. the spot no longer
          // exists): it is dropped and the next sync shows the server's state.
          if (e is ApiException && e.statusCode < 500) await local.markSent(change);
        }
      }
    } finally {
      _sendingPending = false;
      notifyListeners();
    }
    return sent;
  }

  /// PUT or DELETE. Saving twice (409) or unsaving a spot that isn't saved
  /// (404) already leaves the server as the student wants, so they count as
  /// success: a change sent again never fails because the first one arrived.
  Future<void> _send(String userId, String spotId, bool save) async {
    try {
      if (save) {
        await _repository.addFavorite(userId, spotId);
      } else {
        await _repository.removeFavorite(userId, spotId);
      }
    } on ApiException catch (e) {
      if (!(save ? e.statusCode == 409 : e.statusCode == 404)) rethrow;
    }
    if (save) {
      _telemetry.enqueue(TelemetryEvent.favoriteAdded(userId: userId, spotId: spotId));
    }
  }

  void _setSaved(String spotId, bool saved) {
    _spots = [
      for (final spot in _spots)
        spot.id == spotId ? spot.copyWith(isSaved: saved) : spot,
    ];
    notifyListeners();
  }

  void _setSync(FavoritesSync sync) {
    _sync = sync;
    notifyListeners();
  }
}
