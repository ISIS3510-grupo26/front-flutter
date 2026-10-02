import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'repositories/auth_repository.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_session.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final session = AuthSession(repository: AuthRepository(client: http.Client()))
    ..restore();
  runApp(CampusBitesApp(session: session));
}

class CampusBitesApp extends StatelessWidget {
  final AuthSession session;

  const CampusBitesApp({super.key, required this.session});

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
            HomeShell(key: ValueKey(session.userId), session: session),
        },
      ),
    );
  }
}
