import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/best_for_you.dart';
import '../models/telemetry_event.dart';
import '../repositories/favorites_repository.dart';
import '../repositories/spots_repository.dart';
import '../services/auth_client.dart';
import '../services/auth_session.dart';
import '../services/best_for_you_loader.dart';
import '../services/best_for_you_service.dart';
import '../services/favorites_controller.dart';
import '../services/local_database.dart';
import '../services/nearby_favorites_loader.dart';
import '../services/popularity_loader.dart';
import '../services/popularity_prefs.dart';
import '../services/popularity_service.dart';
import '../services/recommendations_service_adapter.dart';
import '../services/taste_map_loader.dart';
import '../services/taste_map_prefs.dart';
import '../services/telemetry_queue.dart';
import '../services/telemetry_store.dart';
import '../repositories/matches_repository.dart';
import '../repositories/wait_times_repository.dart';
import '../services/preferences_service.dart';
import '../services/shake_detector.dart';
import '../services/weather_service.dart';
import '../theme/app_colors.dart';
import '../widgets/campus_bottom_nav_bar.dart';
import 'change_password_screen.dart';
import 'for_you_screen.dart';
import 'place_detail_screen.dart';
import 'saved_places_screen.dart';
import 'taste_map_screen.dart';
import 'profile_screen.dart';
import 'wait_times_screen.dart';

/// Hosts the four main tabs and wires up the app's services for the current
/// user. The For You feed and Saved Places both render
/// [FavoritesController.spots], so toggling the heart on a card in either
/// screen updates the same saved state.
class HomeShell extends StatefulWidget {
  final AuthSession session;

  const HomeShell({super.key, required this.session});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final _http = AuthClient(widget.session);
  late final _api = FavoritesRepository(client: _http);
  late final _spots = SpotsRepository(client: _http);
  late final _telemetry = TelemetryQueue(
    client: _http,
    store: FileTelemetryStore(),
    connectivity: Connectivity().onConnectivityChanged,
  );
  late final _favorites = FavoritesController(
    repository: _api,
    telemetry: _telemetry,
    currentUserId: () => widget.session.userId,
  );
  late final _nearbyLoader = NearbyFavoritesLoader(
    favorites: _api,
    currentUserId: () => widget.session.userId,
  );
  late final _recommendations = RecommendationsServiceAdapter(client: _http);
  late final _tasteMapLoader = TasteMapLoader(
    recommendations: _recommendations,
    currentUserId: () => widget.session.userId,
    storage: const SqliteTasteMapStorage(),
    prefs: TasteMapPrefs(),
  );
  late final _popularLoader = PopularityLoader(
    service: PopularityServiceAdapter(client: _http),
    prefs: PopularityPrefs(),
  );
  late final _bestForYouLoader = BestForYouLoader(
    service: BestForYouServiceAdapter(client: _http),
    storage: const SqliteBestForYouStorage(),
  );
  late final _matches = MatchesRepository(client: _http);
  late final _waitTimes = WaitTimesRepository(client: _http);
  late final _preferences = PreferencesService(
    repository: _matches,
    currentUserId: () => widget.session.userId,
  );
  // Its own client: the weather service is a third party and must never get the token.
  final _weatherHttp = http.Client();
  late final _weatherService = WeatherService(client: _weatherHttp);
  final _shake = ShakeDetector();

  /// Smart feature: compatibility per spot for this student. Null until it
  /// loads (or if it fails); then the feed keeps the catalog percentage.
  Map<String, int>? _matchScores;
  WeatherNow? _weather;

  /// The accelerometer is only on while the app is in the foreground.
  bool _appInForeground = true;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _restoreTelemetry();
    _syncFavorites();
    _lifecycle =AppLifecycleListener(onStateChange: _onAppStateChange);
    // Every time the preferences load or change, the percentages are recalculated.
    _preferences.addListener(_loadMatches);
    _loadPreferences();
    _loadWeather();
  }

  /// Future with handler: the events the last session couldn't send are read
  /// from disk without blocking the first frame, then sent right away.
  void _restoreTelemetry() {
    _telemetry
        .restore()
        .then((_) => _telemetry.flush())
        .catchError((Object e) => debugPrint("Couldn't resend saved telemetry: $e"));
  }

  Future<void> _loadPreferences() async {
    try {
      await _preferences.load(); // notifies -> _loadMatches
    } on Exception {
      _loadMatches(); // the profile tags stay empty, but the feed can still get its percentages
    }
  }

  Future<void> _loadMatches() async {
    final userId = widget.session.userId;
    if (userId == null) return;
    try {
      final scores = await _matches.fetchMatches(userId);
      if (mounted) setState(() => _matchScores = scores);
    } on Exception {
      // Without a connection the feed shows the catalog percentage.
    }
  }

  void _onAppStateChange(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed && !_appInForeground) _loadWeather(); // back in the app: the weather may have changed
    setState(() => _appInForeground = resumed);
  }

  Future<void> _loadWeather() async {
    final weather = await _weatherService.current();
    if (mounted) setState(() => _weather = weather);
  }

  String get _displayName => switch (widget.session.state) {
        AuthSignedIn(:final user) => user.email.split('@').first,
        AuthDevUser(:final userId) => userId,
        _ => 'Student',
      };

  @override
  void dispose() {
    _shake.stop();
    _lifecycle.dispose();
    _weatherHttp.close();
    _preferences
      ..removeListener(_loadMatches)
      ..dispose();
    _favorites.dispose();
    _telemetry.dispose();
    _http.close();
    super.dispose();
  }

  Future<void> _syncFavorites() async {
    try {
      await _favorites.syncFromServer();
    } on Exception {
      _showError("Couldn't load your saved places.");
    }
  }

  Future<void> _toggleSaved(String id) async {
    try {
      await _favorites.toggleSaved(id);
    } on Exception {
      _showError("Couldn't update your saved places. Try again.");
    }
  }

  Future<void> _openSpot(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDetailScreen(
          spotId: id,
          repository: _spots,
          telemetry: _telemetry,
          currentUserId: () => widget.session.userId,
          canReview: widget.session.state is AuthSignedIn,
          favorites: _favorites,
          onToggleSaved: _toggleSaved,
        ),
      ),
    );
    _loadMatches(); // a new review changes "Something new" and what similar students think
  }

  void _openWaitTimes() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WaitTimesScreen(repository: _waitTimes, onOpenSpot: _openSpot)),
    );
  }

  /// BQ3 counts a spot opened from search results as a search, then the
  /// detail reports its page view as usual.
  void _openFromSearch(String id) {
    _telemetry.enqueue(
      TelemetryEvent.search(spotId: id, userId: widget.session.userId),
    );
    _openSpot(id);
  }

  void _openChangePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangePasswordScreen(session: widget.session),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: ListenableBuilder(
        // Preferences too: saving Taste Profile changes what BQ6 asks for.
        listenable: Listenable.merge([_favorites, _preferences]),
        builder: (context, _) => IndexedStack(
          index: _index,
          children: [
            ForYouScreen(
              spots: _favorites.spots,
              onToggleSaved: _toggleSaved,
              onOpenSpot: _openSpot,
              onOpenFromSearch: _openFromSearch,
              popularLoader: _popularLoader,
              matchScores: _matchScores,
              weather: _weather,
              shakeDetector: _shake,
              shakeActive: _index == 0 && _appInForeground,
              onOpenWaitTimes: _openWaitTimes,
              bestForYouLoader: _bestForYouLoader,
              bestForYouProfile: BestForYouProfile.from(_preferences.current),
              connectivity: Connectivity().onConnectivityChanged,
            ),
            TasteMapScreen(
              loader: _tasteMapLoader,
              telemetry: _telemetry,
              currentUserId: () => widget.session.userId,
              onOpenSpot: _openSpot,
            ),
            SavedPlacesScreen(
              spots: _favorites.spots,
              onToggleSaved: _toggleSaved,
              nearbyLoader: _nearbyLoader,
              onOpenSpot: _openSpot,
              sync: _favorites.sync,
              onRetrySync: _syncFavorites,
            ),
            ProfileScreen(
              onSignOut: widget.session.signOut,
              onChangePassword: widget.session.state is AuthSignedIn
                  ? _openChangePassword
                  : null,
              preferences: _preferences,
              displayName: _displayName,
            ),
          ],
        ),
      ),
      bottomNavigationBar: CampusBottomNavBar(
        currentIndex: _index,
        onTap: (index) => setState(() => _index = index),
      ),
    );
  }
}
