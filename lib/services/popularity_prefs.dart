import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/hourly_ranking.dart';

/// Local storage strategy: preferences (shared_preferences).
///
/// The last "Popular right now" ranking and when it was loaded, so For You
/// can still show it without network ("data from HH:MM"). It is one small
/// JSON value, so preferences are enough. Ranking and time are written as a
/// single entry, so they can never disagree.
class PopularityPrefs {
  static const _lastRankingKey = 'popularNow.lastRanking';

  final SharedPreferencesAsync _prefs;

  PopularityPrefs([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  Future<void> save(HourlyRanking ranking, {required DateTime savedAt}) =>
      _prefs.setString(
        _lastRankingKey,
        jsonEncode({
          'savedAt': savedAt.toUtc().toIso8601String(),
          'ranking': ranking.toJson(),
        }),
      );

  Future<({HourlyRanking ranking, DateTime savedAt})?> read() async {
    final raw = await _prefs.getString(_lastRankingKey);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return (
      ranking: HourlyRanking.fromJson(json['ranking'] as Map<String, dynamic>),
      savedAt: DateTime.parse(json['savedAt'] as String).toLocal(),
    );
  }
}
