import 'package:flutter/foundation.dart';

import '../models/spot_detail.dart';
import '../repositories/api_exception.dart';
import 'local_database.dart';

/// Eventual connectivity for the Place Detail: network, else the copy saved
/// on the phone, else error.
///
/// - Network works: returns the fresh [SpotDetail] and saves it in SQLite
///   (fire-and-forget, the page never waits for the disk).
/// - No network but the spot was opened before: returns the saved copy and
///   when it was saved ([offlineSavedAt]).
/// - No network and nothing saved, or the backend answered with an error:
///   [spot] is null. An HTTP error never shows the saved copy, so a real
///   failure isn't hidden behind stale data.
///
/// [error] is the failure as thrown, if any, so the screen can still report
/// its exact type to telemetry (BQ2) while it shows the saved copy.
Future<({SpotDetail? spot, DateTime? offlineSavedAt, Object? error})>
    loadPlaceDetail({
  required String spotId,
  required Future<SpotDetail> Function(String spotId) fetch,
  required SpotDetailStorage storage,
}) async {
  try {
    final spot = await fetch(spotId);
    // Future with handler: fire-and-forget write with .catchError().
    storage
        .save(spot)
        .catchError((Object e) => debugPrint("Couldn't save $spotId offline: $e"));
    return (spot: spot, offlineSavedAt: null, error: null);
  } catch (error) {
    final saved = isNetworkError(error) ? await _readSaved(spotId, storage) : null;
    return (spot: saved?.spot, offlineSavedAt: saved?.savedAt, error: error);
  }
}

/// The copy saved on the phone, or null if there is none or it can't be read.
Future<({SpotDetail spot, DateTime savedAt})?> _readSaved(
  String spotId,
  SpotDetailStorage storage,
) async {
  try {
    return await storage.read(spotId);
  } catch (e) {
    debugPrint("Couldn't read $spotId offline: $e");
    return null;
  }
}
