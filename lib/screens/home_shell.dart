import 'package:flutter/material.dart';

import '../repositories/favorites_repository.dart';
import '../services/auth_client.dart';
import '../services/auth_session.dart';
import '../services/favorites_controller.dart';
import '../services/nearby_favorites_loader.dart';
import '../services/telemetry_queue.dart';
import '../theme/app_colors.dart';
import '../widgets/campus_bottom_nav_bar.dart';
import 'for_you_screen.dart';
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
            ForYouScreen(spots: _favorites.spots, onToggleSaved: _toggleSaved),
            const TasteMapScreen(),
            SavedPlacesScreen(
              spots: _favorites.spots,
              onToggleSaved: _toggleSaved,
              nearbyLoader: _nearbyLoader,
            ),
            ProfileScreen(onSignOut: widget.session.signOut),
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
