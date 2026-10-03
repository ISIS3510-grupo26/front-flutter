import 'package:flutter/material.dart';

import '../repositories/favorites_repository.dart';
import '../repositories/recommendations_repository.dart';
import '../repositories/spots_repository.dart';
import '../services/auth_client.dart';
import '../services/auth_session.dart';
import '../services/favorites_controller.dart';
import '../services/nearby_favorites_loader.dart';
import '../services/taste_map_loader.dart';
import '../services/telemetry_queue.dart';
import '../theme/app_colors.dart';
import '../widgets/campus_bottom_nav_bar.dart';
import 'change_password_screen.dart';
import 'for_you_screen.dart';
import 'place_detail_screen.dart';
import 'saved_places_screen.dart';
import 'taste_map_screen.dart';
import 'profile_screen.dart';

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
  late final _telemetry = TelemetryQueue(client: _http);
  late final _favorites = FavoritesController(
    repository: _api,
    telemetry: _telemetry,
    currentUserId: () => widget.session.userId,
  );
  late final _nearbyLoader = NearbyFavoritesLoader(
    favorites: _api,
    currentUserId: () => widget.session.userId,
  );
  late final _recommendations = RecommendationsRepository(client: _http);
  late final _tasteMapLoader = TasteMapLoader(
    recommendations: _recommendations,
    currentUserId: () => widget.session.userId,
  );

  @override
  void initState() {
    super.initState();
    _syncFavorites();
  }

  @override
  void dispose() {
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

  void _openSpot(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDetailScreen(
          spotId: id,
          repository: _spots,
          telemetry: _telemetry,
          currentUserId: () => widget.session.userId,
          canReview: widget.session.state is AuthSignedIn,
        ),
      ),
    );
  }

  void _openChangePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChangePasswordScreen(session: widget.session)),
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
        listenable: _favorites,
        builder: (context, _) => IndexedStack(
          index: _index,
          children: [
            ForYouScreen(
              spots: _favorites.spots,
              onToggleSaved: _toggleSaved,
              onOpenSpot: _openSpot,
            ),
            TasteMapScreen(loader: _tasteMapLoader, onOpenSpot: _openSpot),
            SavedPlacesScreen(
              spots: _favorites.spots,
              onToggleSaved: _toggleSaved,
              nearbyLoader: _nearbyLoader,
              onOpenSpot: _openSpot,
            ),
            ProfileScreen(
              onSignOut: widget.session.signOut,
              onChangePassword:
                  widget.session.state is AuthSignedIn ? _openChangePassword : null,
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
