import 'package:shared_preferences/shared_preferences.dart';

/// Local storage strategy: preferences (shared_preferences).
///
/// Small key-value metadata about the last successful Taste Map load: when
/// it happened and where the student was. The picks themselves live in
/// SQLite (local_database.dart); this tells the offline map where to center
/// and the banner what time to show.
class TasteMapPrefs {
  static const _lastSyncAtKey = 'tasteMap.lastSyncAt';
  static const _lastLatKey = 'tasteMap.lastLat';
  static const _lastLngKey = 'tasteMap.lastLng';

  final SharedPreferencesAsync _prefs;

  TasteMapPrefs([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  Future<void> save({
    required DateTime syncedAt,
    required double lat,
    required double lng,
  }) async {
    await _prefs.setString(_lastSyncAtKey, syncedAt.toUtc().toIso8601String());
    await _prefs.setDouble(_lastLatKey, lat);
    await _prefs.setDouble(_lastLngKey, lng);
  }

  Future<({DateTime syncedAt, double lat, double lng})?> read() async {
    final syncedAt = await _prefs.getString(_lastSyncAtKey);
    final lat = await _prefs.getDouble(_lastLatKey);
    final lng = await _prefs.getDouble(_lastLngKey);
    if (syncedAt == null || lat == null || lng == null) return null;
    return (syncedAt: DateTime.parse(syncedAt).toLocal(), lat: lat, lng: lng);
  }
}
