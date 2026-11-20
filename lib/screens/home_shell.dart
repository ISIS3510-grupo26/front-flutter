import 'dart:async';
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
import '../services/favorites_local_store.dart';
import '../services/local_database.dart';
import '../services/place_detail_loader.dart';
import '../services/nearby_favorites_loader.dart';
import '../services/popularity_loader.dart';
import '../services/popularity_prefs.dart';
import '../services/popularity_service.dart';
import '../services/recommendations_service_adapter.dart';
import '../services/taste_map_loader.dart';
import '../services/taste_map_prefs.dart';
import '../services/telemetry_queue.dart';
import '../services/telemetry_store.dart';
import '../services/hive_store.dart';
import '../services/match_scores_cache.dart';
import '../services/review_event_outbox.dart';
import '../services/review_submitter.dart';
import '../services/wait_times_store.dart';
import '../repositories/matches_repository.dart';
import '../repositories/wait_times_repository.dart';
import '../services/preferences_service.dart';
import '../services/preferences_sync.dart';
import '../services/reconnect_retry.dart';
import '../services/recommendation_visit_tracker.dart';
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

  /// Hive boxes opened in main(): review drafts, BQ13 events and match scores.
  final HiveStore store;

  /// Hive boxes with the saved places and the saves made offline.
  final FavoritesLocalStore favoritesStore;

  const HomeShell({super.key, required this.session, required this.store, required this.favoritesStore});

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
  // BQ9: recommendations opened and the visits that followed. The events go
  // through the persistent telemetry queue.
  late final _visits = RecommendationVisitTracker(
    send: _telemetry.enqueue,
    currentUserId: () => widget.session.userId,
    onVisited: _greetVisit,
  );
  late final _favorites = FavoritesController(
    repository: _api,
    telemetry: _telemetry,
    currentUserId: () => widget.session.userId,
    local: widget.favoritesStore,
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
  final _waitStore = WaitTimesStore();
  // BQ13 events saved in Hive until the backend gets them,
  // reviews that record every attempt, and the cached compatibility %.
  late final _reviewEvents = ReviewEventOutbox(
    client: _http,
    store: widget.store,
    currentUserId: () => widget.session.userId,
  );
  late final _reviewSubmitter = ReviewSubmitter(
    repository: _spots,
    store: widget.store,
    currentUserId: () => widget.session.userId,
    onAttemptRecorded: _reviewEvents.flush,
  );
  late final _matchCache = MatchScoresCache(repository: _matches, store: widget.store);
  late final StreamSubscription<List<ConnectivityResult>> _connectionChanges;
  late final _preferences = PreferencesService(
    repository: _matches,
    currentUserId: () => widget.session.userId,
  );
  final _preferencesSync = PreferencesSync();
  // Its own client: the weather service is a third party and must never get the token.
  final _weatherHttp = http.Client();
  late final _weatherService = WeatherService(client: _weatherHttp);
  final _shake = ShakeDetector();

  /// Smart feature: compatibility per spot for this student. Null until it
  /// loads (or if it fails); then the feed keeps the catalog percentage.
  MatchScores? _matchScores;
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
    _reviewEvents.flush(); // BQ13 events left from before (crashes found in main, offline attempts)
    _sendSavedWaitReports();
    _connectionChanges = Connectivity().onConnectivityChanged.listen(_onConnectionChanged);
    _visits.startWatching();
  }

  /// When the connection comes back: send the saved BQ13 events, and if the feed is showing saved percentages, 
  /// ask for the new ones.
    void _onConnectionChanged(List<ConnectivityResult> results) {
    if (results.every((r) => r == ConnectivityResult.none)) return;
    _reviewEvents.flush();
    _sendSavedWaitReports();
    _syncPreferences();
    if (_matchScores?.offline ?? false) _loadMatches(force: false);
    if (_favorites.isOffline || _favorites.pendingIds.isNotEmpty) {
      // The network may need a second or two after the radio connects.
      retryAfterReconnect(() async {
        if (!mounted) return true;
        await _syncFavorites();
        return !_favorites.isOffline && _favorites.pendingIds.isEmpty;
      });
    }
  }

  /// Wait times reported offline: they are sent even if the student never
  /// opens that screen again. If it fails they stay saved for the next time.
  void _sendSavedWaitReports() {
    _waitStore
        .flush(_waitTimes)
        .then((sent) {
          if (sent > 0) debugPrint('Sent $sent saved wait time reports');
        })
        .catchError((Object e) => debugPrint("Couldn't send the saved wait times: $e"));
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
      _syncPreferences();
    } on Exception {
      // Offline: the profile and the feed use what was saved on this phone.
      final fromPhone = await _preferencesSync.phoneCopy().catchError((Object e) => null);
      if (fromPhone != null) {
        _preferences.useCopyFromPhone(fromPhone); // notifies -> _loadMatches
      } else {
        _loadMatches(); // nothing saved here either, but the feed can still get its percentages
      }
    }
  }

  /// Sends the preferences saved offline (saving notifies, so the feed recalculates). 
  Future<void> _syncPreferences() async {
    try {
      final sent = await _preferencesSync.syncIfNeeded(_preferences);
      if (!sent && _preferences.onlyOnPhone) await _preferences.load();
    } catch (e) {
      debugPrint("Couldn't sync the preferences: $e"); // they stay pending for the next reconnection
    }
  }

  /// Stale-while-revalidate: the first value is the saved one (instant) and
  /// the second the one from the backend. By default it always asks again,
  /// because it runs after the preferences change or after a new review.
  Future<void> _loadMatches({bool force = true}) async {
    final userId = widget.session.userId;
    if (userId == null) return;
    try {
      await for (final matches in _matchCache.load(userId, force: force)) {
        if (!mounted) return;
        setState(() => _matchScores = matches);
      }
    } on Exception {
      // Nothing saved and no answer: the feed keeps the catalog percentage.
    }
  }

  void _onAppStateChange(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed && !_appInForeground) {
      _loadWeather(); // back in the app: the weather may have changed
      _visits.startWatching(); // the student may have walked to a recommendation meanwhile
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _visits.stopWatching(); // BQ9 never looks at the location with the app in the background
    }
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
    _visits.stopWatching();
    _shake.stop();
    _connectionChanges.cancel();
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

  /// On open, on Retry and when the connection comes back. If they overlap
  /// they share one run (see [FavoritesController.syncAll]).
  /// Without network nothing is shown here: Saved says it is offline.
  Future<void> _syncFavorites() async {
    try {
      await _favorites.syncAll();
    } on Exception {
      _showError("The server couldn't load your saved places.");
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
          reviewSubmitter: _reviewSubmitter,
        ),
      ),
    );
    _loadMatches(); // a new review changes "Something new" and what similar students think
  }

  /// BQ9: the spot was opened from "Best for you right now" or the feed
  /// sorted by match. Saving the candidate never delays opening the page.
  void _openRecommended(String id) {
    if (_favorites.spotById(id) case final spot?) {
      _visits
          .recordOpen(spotId: id, latitude: spot.latitude, longitude: spot.longitude)
          .catchError((Object e) => debugPrint("Couldn't save the BQ9 recommendation: $e"));
    }
    _openSpot(id);
  }

  void _greetVisit(List<String> spotIds) {
    final names = [for (final id in spotIds) _favorites.spotById(id)?.name ?? 'your pick'];
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('You made it to ${names.join(' and ')}. Enjoy your meal! 🍽️')));
  }

  void _openWaitTimes() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WaitTimesScreen(repository: _waitTimes, store: _waitStore, onOpenSpot: _openSpot)),
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
              onOpenRecommended: _openRecommended,
              popularLoader: _popularLoader,
              matchScores: _matchScores?.scores,
              matchesOfflineSince: (_matchScores?.offline ?? false) ? _matchScores!.savedAt : null,
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
              prefetchDetails: (ids) => prefetchPlaceDetails(
                spotIds: ids,
                fetch: _spots.fetchSpot,
                storage: const SqliteSpotDetailStorage(),
              ),
            ),
            SavedPlacesScreen(
              spots: _favorites.spots,
              onToggleSaved: _toggleSaved,
              nearbyLoader: _nearbyLoader,
              onOpenSpot: _openSpot,
              sync: _favorites.sync,
              onRetrySync: _syncFavorites,
              offlineSince: _favorites.copySavedAt,
              pendingIds: _favorites.pendingIds,
            ),
            ProfileScreen(
              onSignOut: widget.session.signOut,
              onChangePassword: widget.session.state is AuthSignedIn
                  ? _openChangePassword
                  : null,
              preferences: _preferences,
              preferencesSync: _preferencesSync,
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
