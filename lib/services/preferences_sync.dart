import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_preferences.dart';
import 'preferences_service.dart';
import 'profile_prefs.dart';

/// Eventual connectivity for Taste Profile and Dietary Preferences.
/// Both screens always save on the phone first (ProfilePrefs).
class PreferencesSync {
  static const _pendingKey = 'preferences.pendingSync';

  final SharedPreferencesAsync _prefs;
  final ProfilePrefs _phone;

  /// The sync in progress, so opening the app and getting the signal back at the same moment sends the preferences once.
  Future<bool>? _syncing;

  PreferencesSync({SharedPreferencesAsync? prefs, ProfilePrefs? phone})
      : _prefs = prefs ?? SharedPreferencesAsync(),
        _phone = phone ?? ProfilePrefs();

  Future<void> markPending() => _prefs.setBool(_pendingKey, true);

  Future<bool> hasPending() async => await _prefs.getBool(_pendingKey) ?? false;

  /// Both screens as they are saved on this phone, in the shape the backend uses.
  Future<UserPreferences?> phoneCopy({UserPreferences base = const UserPreferences()}) async {
    final taste = await _phone.readTaste();
    final dietary = await _phone.readDietary();
    if (taste == null && dietary == null) return null;
    return base.copyWith(
      mainCuisine: taste?.mainCuisine,
      mealStyle: taste?.mealStyle,
      flavors: taste?.flavors.toList(),
      interests: taste?.interests.toList(),
      diet: dietary?.diet,
      avoid: dietary?.avoid.toList(),
      allergies: dietary?.allergies.toList(),
    );
  }

  /// Sends the phone copy if something is pending. Returns true if it sent. If it fails the flag stays, so the 
  /// next reconnection tries again.
  Future<bool> syncIfNeeded(PreferencesService service) =>
      _syncing ??= _sync(service).whenComplete(() => _syncing = null);

  Future<bool> _sync(PreferencesService service) async {
    if (!await hasPending()) return false;
    // The backend copy is the base, so a part that was never saved on this phone keeps what the backend had.
    final fromPhone = await phoneCopy(base: await service.load());
    if (fromPhone != null) await service.save(fromPhone);
    await _prefs.setBool(_pendingKey, false);
    return true;
  }
}
