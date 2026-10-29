import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/food_preferences.dart';

/// Local storage strategy: preferences (shared_preferences).
///
/// The student's Dietary Preferences and Taste Profile, saved on the phone
/// like the Kotlin app does with DataStore: they are a few small choices,
/// work offline and never leave the phone. Each screen is one JSON entry, so
/// saving a screen is a single write.
class ProfilePrefs {
  static const _dietaryKey = 'profile.dietary';
  static const _tasteKey = 'profile.taste';

  final SharedPreferencesAsync _prefs;

  ProfilePrefs([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  /// Null until the student saves the screen once.
  Future<DietaryPreferences?> readDietary() async {
    final raw = await _prefs.getString(_dietaryKey);
    return raw == null
        ? null
        : DietaryPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveDietary(DietaryPreferences preferences) =>
      _prefs.setString(_dietaryKey, jsonEncode(preferences.toJson()));

  /// Null until the student saves the screen once.
  Future<TastePreferences?> readTaste() async {
    final raw = await _prefs.getString(_tasteKey);
    return raw == null
        ? null
        : TastePreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveTaste(TastePreferences preferences) =>
      _prefs.setString(_tasteKey, jsonEncode(preferences.toJson()));
}
