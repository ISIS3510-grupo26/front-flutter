import 'package:campus_bites/models/food_preferences.dart';
import 'package:campus_bites/screens/dietary_preferences_screen.dart';
import 'package:campus_bites/screens/taste_profile_screen.dart';
import 'package:campus_bites/services/profile_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryPrefs extends Fake implements ProfilePrefs {
  DietaryPreferences? dietary;
  TastePreferences? taste;
  bool failSaves = false;

  @override
  Future<DietaryPreferences?> readDietary() async => dietary;

  @override
  Future<void> saveDietary(DietaryPreferences preferences) async {
    if (failSaves) throw Exception('disk full');
    dietary = preferences;
  }

  @override
  Future<TastePreferences?> readTaste() async => taste;

  @override
  Future<void> saveTaste(TastePreferences preferences) async {
    if (failSaves) throw Exception('disk full');
    taste = preferences;
  }
}

/// Opens [screen] from a first page, so saving can pop back to it.
Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save preferences'));
  await tester.pumpAndSettle();
}

void main() {
  group('Dietary Preferences', () {
    late _MemoryPrefs prefs;

    setUp(() => prefs = _MemoryPrefs());

    testWidgets('saves what was picked and closes', (tester) async {
      await _open(tester, DietaryPreferencesScreen(prefs: prefs));

      await _tap(tester, 'Vegan');
      await _tap(tester, 'Meat');
      await _tap(tester, 'Eggs');
      await _save(tester);

      expect(prefs.dietary?.diet, 'Vegan');
      expect(prefs.dietary?.avoid, {'Meat', 'Very spicy food'});
      expect(prefs.dietary?.allergies, {'Eggs'});
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('reopening shows what was saved', (tester) async {
      prefs.dietary = const DietaryPreferences(
        diet: 'Pescatarian',
        avoid: {'Nuts'},
        allergies: {'Peanuts'},
      );

      await _open(tester, DietaryPreferencesScreen(prefs: prefs));
      await _save(tester);

      expect(prefs.dietary?.toJson(), {
        'diet': 'Pescatarian',
        'avoid': ['Nuts'],
        'allergies': ['Peanuts'],
      });
    });

    testWidgets('a failed save says so and stays open', (tester) async {
      prefs.failSaves = true;
      await _open(tester, DietaryPreferencesScreen(prefs: prefs));

      await _save(tester);

      expect(
        find.text("Couldn't save your preferences. Try again."),
        findsOneWidget,
      );
      expect(find.text('Save preferences'), findsOneWidget);
    });
  });

  group('Taste Profile', () {
    late _MemoryPrefs prefs;

    setUp(() => prefs = _MemoryPrefs());

    testWidgets('saves what was picked and closes', (tester) async {
      await _open(tester, TasteProfileScreen(prefs: prefs));

      await _tap(tester, 'Italian');
      await _tap(tester, 'Spicy');
      await _tap(tester, 'Trying something new');
      await _tap(tester, 'Good value');
      await _save(tester);

      expect(prefs.taste?.mainCuisine, 'Italian');
      expect(prefs.taste?.flavors, {'Savory', 'Sweet', 'Spicy'});
      expect(prefs.taste?.mealStyle, 'Trying something new');
      expect(prefs.taste?.interests, {'Something new', 'Good value'});
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('reopening shows what was saved', (tester) async {
      prefs.taste = const TastePreferences(
        mainCuisine: 'Mexican',
        mealStyle: 'Comfort food',
        flavors: {'Spicy'},
        interests: {'Good value'},
      );

      await _open(tester, TasteProfileScreen(prefs: prefs));
      await _save(tester);

      expect(prefs.taste?.toJson(), {
        'mainCuisine': 'Mexican',
        'mealStyle': 'Comfort food',
        'flavors': ['Spicy'],
        'interests': ['Good value'],
      });
    });
  });

  test('preferences read back the same from JSON', () {
    const dietary = DietaryPreferences(
      diet: 'Vegan',
      avoid: {'Meat', 'Dairy'},
      allergies: {},
    );
    const taste = TastePreferences(
      mainCuisine: 'Asian',
      mealStyle: 'Healthy options',
      flavors: {'Mild'},
      interests: {'Something familiar'},
    );

    expect(DietaryPreferences.fromJson(dietary.toJson()).toJson(), dietary.toJson());
    expect(TastePreferences.fromJson(taste.toJson()).toJson(), taste.toJson());
  });
}
