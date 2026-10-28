import 'package:flutter/foundation.dart';

import '../models/spot_detail.dart';
import 'local_database.dart';

/// Eventual connectivity for the Place Detail: network, else the copy saved
/// on the phone, else error.
///
/// - Network works: returns the fresh [SpotDetail] and saves it in SQLite
///   (fire-and-forget, the page never waits for the disk).
/// - Network fails but the spot was opened before: returns the saved copy
///   and when it was saved ([offlineSavedAt]).
/// - Network fails and nothing is saved: [spot] is null.
///
/// [networkError] is always the network failure, if any, so the screen can
/// still report it to telemetry (BQ2) while it shows the saved copy.
Future<({SpotDetail? spot, DateTime? offlineSavedAt, Object? networkError})>
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
    return (spot: spot, offlineSavedAt: null, networkError: null);
  } catch (networkError) {
    try {
      if (await storage.read(spotId) case final saved?) {
        return (spot: saved.spot, offlineSavedAt: saved.savedAt, networkError: networkError);
      }
    } catch (e) {
      debugPrint("Couldn't read $spotId offline: $e");
    }
    return (spot: null, offlineSavedAt: null, networkError: networkError);
  }
}
