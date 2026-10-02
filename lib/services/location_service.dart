import 'package:geolocator/geolocator.dart';

enum LocationFailure { serviceDisabled, permissionDenied, permissionDeniedForever }

class LocationException implements Exception {
  final LocationFailure reason;

  const LocationException(this.reason);

  @override
  String toString() => 'LocationException($reason)';
}

class LocationService {
  const LocationService();

  /// Requests permission if needed and returns the device's current position.
  /// Throws [LocationException] when location is unavailable.
  Future<Position> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationFailure.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(LocationFailure.permissionDeniedForever);
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(LocationFailure.permissionDenied);
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<bool> openSettings() => Geolocator.openAppSettings();
}
