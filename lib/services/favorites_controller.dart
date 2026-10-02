import 'package:flutter/foundation.dart';

import '../data/spots_data.dart';
import '../models/spot.dart';
import '../models/telemetry_event.dart';
import '../repositories/favorites_repository.dart';
import 'telemetry_queue.dart';

/// Owns the spots shown across the app and their saved state, keeping it in
/// sync with the server for the current user. Without a user, saving is
/// local only.
class FavoritesController extends ChangeNotifier {
  final FavoritesRepository _repository;
  final TelemetryQueue _telemetry;
  final String? Function() _currentUserId;
  final _pending = <String>{};
  List<Spot> _spots;

  FavoritesController({
    required this._repository,
    required this._telemetry,
    required this._currentUserId,
    List<Spot>? spots,
  }) : _spots = spots ?? List.of(sampleSpots);

  List<Spot> get spots => _spots;

  /// Replaces local saved state with the server's. Spots with a save or
  /// unsave still in flight keep their local state.
  Future<void> syncFromServer() async {
    final userId = _currentUserId();
    if (userId == null) return;
    final savedIds = await _repository.fetchFavoriteIds(userId);
    _spots = [
      for (final spot in _spots)
        _pending.contains(spot.id)
            ? spot
            : spot.copyWith(isSaved: savedIds.contains(spot.id)),
    ];
    notifyListeners();
  }

  /// Flips [spotId]'s saved state right away, then saves it to the server.
  /// If that fails the change is rolled back and the error is rethrown.
  /// Taps on a spot whose previous change is still in flight are ignored.
  Future<void> toggleSaved(String spotId) async {
    if (!_pending.add(spotId)) return;
    final save = !_spots.firstWhere((s) => s.id == spotId).isSaved;
    _setSaved(spotId, save);
    try {
      final userId = _currentUserId();
      if (userId == null) return;
      if (save) {
        await _repository.addFavorite(userId, spotId);
        _telemetry.enqueue(
          TelemetryEvent.favoriteAdded(userId: userId, spotId: spotId),
        );
      } else {
        await _repository.removeFavorite(userId, spotId);
      }
    } on Exception {
      _setSaved(spotId, !save);
      rethrow;
    } finally {
      _pending.remove(spotId);
    }
  }

  void _setSaved(String spotId, bool saved) {
    _spots = [
      for (final spot in _spots)
        spot.id == spotId ? spot.copyWith(isSaved: saved) : spot,
    ];
    notifyListeners();
  }
}
