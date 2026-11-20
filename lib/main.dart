import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'repositories/auth_repository.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_session.dart';
import 'services/favorites_local_store.dart';
import 'services/hive_store.dart';
import 'services/restaurant_photos.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureImageMemoryCache(PaintingBinding.instance.imageCache);
  final store = await HiveStore.open();
  // (BQ13): runs once per launch, before anything can be sending a review, so every attempt still saved 
  //means the app closed mid-send.
  await store.recoverCrashedAttempts();
  // Hive is already initialized by HiveStore.open: this only opens two more boxes.
  final favoritesStore = await FavoritesLocalStore.open();
  final session = AuthSession(repository: AuthRepository(client: http.Client()))
    ..restore();
  clearFavoritesOnSignOut(session, favoritesStore);
  runApp(CampusBitesApp(session: session, store: store, favoritesStore: favoritesStore));
}

/// The saved places and pending saves belong to the user: when a session ends
/// (Sign out, or the server rejecting the token) both boxes are emptied, so the
/// next account never sees them or sends them as its own.
void clearFavoritesOnSignOut(AuthSession session, FavoritesLocalStore favoritesStore) {
  var hadUser = false;
  session.addListener(() {
    final hasUser = session.state is AuthSignedIn || session.state is AuthDevUser;
    if (hadUser && session.state is AuthSignedOut) favoritesStore.clear();
    hadUser = hasUser;
  });
}

class CampusBitesApp extends StatelessWidget {
  final AuthSession session;
  final HiveStore store;
  final FavoritesLocalStore favoritesStore;

  const CampusBitesApp({super.key, required this.session, required this.store, required this.favoritesStore});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusBites',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) => switch (session.state) {
          AuthRestoring() => const Scaffold(
              backgroundColor: AppColors.cream,
              body: Center(
                child: CircularProgressIndicator(color: AppColors.tomato),
              ),
            ),
          AuthSignedOut() => LoginScreen(
              session: session,
              connectivity: Connectivity().onConnectivityChanged,
            ),
          // Keyed by user so switching accounts starts from a fresh state.
          AuthSignedIn() || AuthDevUser() =>
            HomeShell(
              key: ValueKey(session.userId),
              session: session,
              store: store,
              favoritesStore: favoritesStore,
            ),
        },
      ),
    );
  }
}
