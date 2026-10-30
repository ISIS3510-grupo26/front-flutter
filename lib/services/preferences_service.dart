import 'package:flutter/foundation.dart';

import '../models/user_preferences.dart';
import '../repositories/matches_repository.dart';

/// Keeps the student's preferences in memory and saves them to the backend.
/// Taste Profile and Dietary Preferences each edit their own part, and the
/// feed listens to it so the match percentages are recalculated after a save.
class PreferencesService extends ChangeNotifier {
  final MatchesRepository _repository;
  final String? Function() _currentUserId;
  UserPreferences? _current;

  PreferencesService({
    required this._repository,
    required this._currentUserId,
  });

  UserPreferences? get current => _current;

  Future<UserPreferences> load() async {
    final userId = _currentUserId();
    if (userId == null) return const UserPreferences();
    final loaded = await _repository.fetchPreferences(userId);
    _current = loaded;
    notifyListeners();
    return loaded;
  }

  /// Sends the whole object, so nothing is lost.
  Future<void> save(UserPreferences preferences) async {
    final userId = _currentUserId();
    if (userId == null) throw StateError('No signed-in user');
    _current = await _repository.savePreferences(userId, preferences);
    notifyListeners();
  }
}
