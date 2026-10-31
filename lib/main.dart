import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'repositories/auth_repository.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_session.dart';
import 'services/hive_store.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await HiveStore.open();
  // (BQ13): runs once per launch, before anything can be sending a review, so every attempt still saved 
  //means the app closed mid-send.
  await store.recoverCrashedAttempts();
  final session = AuthSession(repository: AuthRepository(client: http.Client()))
    ..restore();
  runApp(CampusBitesApp(session: session, store: store));
}

class CampusBitesApp extends StatelessWidget {
  final AuthSession session;
  final HiveStore store;

  const CampusBitesApp({super.key, required this.session, required this.store});

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
          AuthSignedOut() => LoginScreen(session: session),
          // Keyed by user so switching accounts starts from a fresh state.
          AuthSignedIn() || AuthDevUser() =>
            HomeShell(key: ValueKey(session.userId), session: session, store: store),
        },
      ),
    );
  }
}
