import 'package:campus_bites/models/food_preferences.dart';
import 'package:campus_bites/models/user_preferences.dart';
import 'package:campus_bites/repositories/matches_repository.dart';
import 'package:campus_bites/screens/change_password_screen.dart';
import 'package:campus_bites/screens/dietary_preferences_screen.dart';
import 'package:campus_bites/screens/profile_screen.dart';
import 'package:campus_bites/services/auth_session.dart';
import 'package:campus_bites/services/preferences_service.dart';
import 'package:campus_bites/services/preferences_sync.dart';
import 'package:campus_bites/services/profile_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The backend; with [noSignal] every request fails like a phone without network.
class _Backend extends Fake implements MatchesRepository {
  UserPreferences stored = const UserPreferences();
  bool noSignal = false;

  @override
  Future<UserPreferences> fetchPreferences(String userId) async {
    if (noSignal) throw http.ClientException('no connection');
    return stored;
  }

  @override
  Future<UserPreferences> savePreferences(String userId, UserPreferences preferences) async {
    if (noSignal) throw http.ClientException('no connection');
    return stored = UserPreferences.fromJson({...preferences.toJson(), 'saved': true});
  }
}

class _Phone extends Fake implements ProfilePrefs {
  DietaryPreferences? dietary;
  TastePreferences? taste;

  @override
  Future<DietaryPreferences?> readDietary() async => dietary;

  @override
  Future<void> saveDietary(DietaryPreferences preferences) async => dietary = preferences;

  @override
  Future<TastePreferences?> readTaste() async => taste;

  @override
  Future<void> saveTaste(TastePreferences preferences) async => taste = preferences;
}

/// SharedPreferences in memory.
class _KeyValue extends Fake implements SharedPreferencesAsync {
  final values = <String, bool>{};

  @override
  Future<bool?> getBool(String key) async => values[key];

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
}

class _Session extends Fake implements AuthSession {
  Object? error;
  final calls = <String>[];

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    calls.add('$currentPassword -> $newPassword');
    if (error case final e?) throw e;
  }
}

/// Opens [screen] from a first page, like the app does.
Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('Dietary preferences offline', () {
    testWidgets('says it is offline, saves on the phone and leaves it pending for the backend', (tester) async {
      final phone = _Phone();
      final keyValue = _KeyValue();
      final service = PreferencesService(repository: _Backend()..noSignal = true, currentUserId: () => 'u1');
      await _open(
        tester,
        DietaryPreferencesScreen(
          prefs: phone,
          preferences: service,
          sync: PreferencesSync(prefs: keyValue, phone: phone),
          isOffline: () async => true,
        ),
      );
      expect(find.text('Offline · your changes stay saved on this phone'), findsOneWidget);

      await tester.ensureVisible(find.text('Vegan'));
      await tester.tap(find.text('Vegan'));
      await tester.pump();
      await tester.tap(find.text('Save preferences'));
      await tester.pumpAndSettle();

      expect(phone.dietary?.diet, 'Vegan');
      expect(find.textContaining("You're offline. Saved on this phone"), findsOneWidget);
      // The profile and the feed already use it, marked as the phone copy.
      expect(service.current?.diet, 'Vegan');
      expect(service.onlyOnPhone, isTrue);
      expect(keyValue.values['preferences.pendingSync'], isTrue);
    });

    testWidgets('online there is no banner', (tester) async {
      await _open(tester, DietaryPreferencesScreen(prefs: _Phone(), isOffline: () async => false));
      expect(find.textContaining('Offline'), findsNothing);
    });
  });

  group('PreferencesSync', () {
    test('sends the phone copy when the connection comes back, only if something is pending', () async {
      final backend = _Backend()
        ..stored = UserPreferences.fromJson({'mainCuisine': 'Italian', 'diet': 'Vegan', 'saved': true});
      final service = PreferencesService(repository: backend, currentUserId: () => 'u1');
      final phone = _Phone()
        ..taste = const TastePreferences(
          mainCuisine: 'Mexican',
          mealStyle: 'Comfort food',
          flavors: {'Spicy'},
          interests: <String>{},
        );
      final keyValue = _KeyValue();
      final sync = PreferencesSync(prefs: keyValue, phone: phone);

      expect(await sync.syncIfNeeded(service), isFalse); // nothing pending: no request

      await sync.markPending();
      backend.noSignal = true;
      await expectLater(sync.syncIfNeeded(service), throwsA(isA<http.ClientException>()));
      expect(await sync.hasPending(), isTrue); // still offline: it stays pending

      backend.noSignal = false;
      expect(await sync.syncIfNeeded(service), isTrue);
      expect(backend.stored.mainCuisine, 'Mexican');
      expect(backend.stored.diet, 'Vegan'); // never saved on this phone: keeps the backend's
      expect(await sync.hasPending(), isFalse);
      expect(service.onlyOnPhone, isFalse);
    });
  });

  testWidgets('Profile shows the phone copy with an offline banner', (tester) async {
    final service = PreferencesService(repository: _Backend(), currentUserId: () => 'u1')
      ..useCopyFromPhone(const UserPreferences(mainCuisine: 'Mexican', mealStyle: 'Comfort food'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProfileScreen(onSignOut: () {}, preferences: service))));
    await tester.pumpAndSettle();

    expect(find.text('Offline · profile saved on this phone'), findsOneWidget);
    expect(find.text('Mexican'), findsOneWidget);
  });

  group('Change password offline', () {
    testWidgets('explains why it needs internet and waits for the connection', (tester) async {
      final session = _Session();
      var offline = true;
      await _open(tester, ChangePasswordScreen(session: session, isOffline: () async => offline));

      expect(find.text("Offline · you can't change your password now"), findsOneWidget);
      await tester.tap(find.text('Check connection again'));
      await tester.pumpAndSettle();
      expect(session.calls, isEmpty);

      offline = false;
      await tester.tap(find.text('Check connection again'));
      await tester.pumpAndSettle();
      expect(find.text('Update password'), findsOneWidget);
      expect(find.textContaining('Offline'), findsNothing);
    });

    testWidgets('losing the signal while sending says the password was not changed', (tester) async {
      final session = _Session()..error = http.ClientException('no connection');
      var offline = false;
      await _open(tester, ChangePasswordScreen(session: session, isOffline: () async => offline));

      offline = true;
      await tester.enterText(find.byType(TextField).at(0), 'segura123');
      await tester.enterText(find.byType(TextField).at(1), 'nueva12345');
      await tester.enterText(find.byType(TextField).at(2), 'nueva12345');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(find.text("You're offline. Your password wasn't changed, try again when you're back online."),
          findsOneWidget);
      expect(find.text("Offline · you can't change your password now"), findsOneWidget);
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
    });
  });
}
