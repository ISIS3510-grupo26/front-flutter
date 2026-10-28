import 'package:latlong2/latlong.dart';

import '../models/nearby_pick.dart';
import 'taste_map_loader.dart';

/// A pin farther than this from the user is treated as a wrong location.
const maxPinDistanceMeters = 5000;

/// False when the pin can't be right: latitude or longitude out of range,
/// exactly 0,0 (a missing value), or more than 5 km from the user. The Taste
/// Map doesn't draw those pins.
bool hasValidCoordinates(NearbyPick pick, double userLat, double userLng) {
  final lat = pick.latitude;
  final lng = pick.longitude;
  if (lat.isNaN || lng.isNaN || lat.abs() > 90 || lng.abs() > 180) return false;
  if (lat == 0 && lng == 0) return false;
  final meters = const Distance()(LatLng(userLat, userLng), LatLng(lat, lng));
  return meters <= maxPinDistanceMeters;
}

/// BQ14: the errorType of the map_display event for one Taste Map load, or
/// null when the map showed every pick where it should (success).
String? mapDisplayErrorType(TasteMapState state) => switch (state) {
      TasteMapFailed() => 'load_failed',
      TasteMapLoaded(usedFallback: true) => 'location_fallback',
      TasteMapLoaded(:final picks, :final userLat, :final userLng)
          when picks.any((p) => !hasValidCoordinates(p, userLat, userLng)) =>
        'invalid_coordinates',
      _ => null,
    };
