import 'dart:async';
import 'dart:io';

import 'package:campus_bites/models/auth_user.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/auth_repository.dart';
import 'package:campus_bites/screens/login_screen.dart';
import 'package:campus_bites/services/auth_session.dart';
import 'package:campus_bites/services/token_store.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore extends Fake implements TokenStore {
  @override
  Future<void> write(AuthUser user) async {}
}

/// Each logIn waits on [reply] until the test completes it. The completer is
/// made inside the test's fake-async zone, so `pump` delivers its result.
class _FakeAuthRepository extends Fake implements AuthRepository {
  int calls = 0;
  late Completer<AuthUser> reply;

  @override
  Future<AuthUser> logIn(String email, String password) {
    calls++;
    reply = Completer();
    return reply.future;
  }
}

void main() {
  late _FakeAuthRepository repo;
  late StreamController<List<ConnectivityResult>> connectivity;

  Future<void> showLogin(WidgetTester tester) async {
    repo = _FakeAuthRepository();
    connectivity = StreamController();
    addTearDown(connectivity.close);
    final session = AuthSession(repository: repo, store: _MemoryStore(), devUserId: '');
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(session: session, connectivity: connectivity.stream),
    ));
    await tester.enterText(find.byType(TextField).at(0), 'ana@uniandes.edu.co');
    await tester.enterText(find.byType(TextField).at(1), 'campus123');
  }

  Future<void> signInFailing(WidgetTester tester, Object error) async {
    await tester.tap(find.byType(FilledButton));
    repo.reply.completeError(error);
    await tester.pump();
  }

  testWidgets('offline, two quick taps send one request and show one message', (tester) async {
    await showLogin(tester);

    // Both taps land before the next frame, while the button is still enabled.
    await tester.tap(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repo.reply.completeError(const SocketException('offline'));
    await tester.pump();

    expect(repo.calls, 1);
    expect(find.text(LoginScreen.offlineMessage), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('without a connection it says the phone is offline', (tester) async {
    await showLogin(tester);
    await signInFailing(tester, TimeoutException('no answer'));

    expect(find.text(LoginScreen.offlineMessage), findsOneWidget);
    expect(find.text(LoginScreen.serverMessage), findsNothing);
  });

  testWidgets('a 500 says CampusBites is having trouble', (tester) async {
    await showLogin(tester);
    await signInFailing(tester, const ApiException(500));

    expect(find.text(LoginScreen.serverMessage), findsOneWidget);
    expect(find.text(LoginScreen.offlineMessage), findsNothing);
  });

  testWidgets('wrong credentials say so', (tester) async {
    await showLogin(tester);
    await signInFailing(tester, const ApiException(401));

    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });

  testWidgets('the offline error goes away when the connection comes back', (tester) async {
    await showLogin(tester);
    await signInFailing(tester, const SocketException('offline'));

    connectivity.add([ConnectivityResult.none]);
    await tester.pump();
    expect(find.text(LoginScreen.offlineMessage), findsOneWidget);

    connectivity.add([ConnectivityResult.wifi]);
    await tester.pump();
    expect(find.text(LoginScreen.offlineMessage), findsNothing);
  });

  testWidgets('coming back online keeps an error that is not about the connection', (tester) async {
    await showLogin(tester);
    await signInFailing(tester, const ApiException(401));

    connectivity.add([ConnectivityResult.mobile]);
    await tester.pump();

    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });
}
