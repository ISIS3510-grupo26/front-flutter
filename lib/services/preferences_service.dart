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
  bool _onlyOnPhone = false;

  PreferencesService({
    required this._repository,
    required this._currentUserId,
  });

  UserPreferences? get current => _current;

  
  /// True while [current] is the copy saved on this phone because the backend couldn't be reached. 
  /// The profile shows it with an offline banner.
  bool get onlyOnPhone => _onlyOnPhone;

  /// Offline: the screens keep working with what is saved on the phone, and the feed and the profile tags use it 
  /// until the backend answers again.
  void useCopyFromPhone(UserPreferences preferences) {
    _current = UserPreferences.fromJson({...preferences.toJson(), 'saved': true});
    _onlyOnPhone = true;
    notifyListeners();
  }

  Future<UserPreferences> load() async {
    final userId = _currentUserId();
    if (userId == null) return const UserPreferences();
    final loaded = await _repository.fetchPreferences(userId);
    _current = loaded;
    _onlyOnPhone = false;
    notifyListeners();
    return loaded;
  }

  /// Sends the whole object, so nothing is lost.
  Future<void> save(UserPreferences preferences) async {
    final userId = _currentUserId();
    if (userId == null) throw StateError('No signed-in user');
    _current = await _repository.savePreferences(userId, preferences);
    _onlyOnPhone = false;
    notifyListeners();
  }
}
