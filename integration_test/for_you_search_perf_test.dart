// Micro-optimization evidence (Sprint 4). Run in profile mode on a real phone:
//
//   flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart \
//     --target=integration_test/for_you_search_perf_test.dart
//   python docs/profiling/for_you_search/profiling.py collect before 1
//
// It opens For You with 60 spots, each with its match %, while it rains (so the feed is sorted by match and
// then by distance), and edits the search the way a student does: types "burger" letter by letter, moves the 
// cursor three times after every letter (to fix a typo, or what the keyboard does while it suggests words), 
// adds a space at the end and deletes it all.
import 'package:campus_bites/models/hourly_ranking.dart';
import 'package:campus_bites/models/spot.dart';
import 'package:campus_bites/models/weekday_searches.dart';
import 'package:campus_bites/screens/for_you_screen.dart';
import 'package:campus_bites/services/popularity_loader.dart';
import 'package:campus_bites/services/popularity_prefs.dart';
import 'package:campus_bites/services/popularity_service.dart';
import 'package:campus_bites/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _cuisines = ['Burgers', 'Bowls', 'Coffee', 'Pizza', 'Arepas', 'Sushi'];

/// 60 spots instead of the 7 of the catalog: the campus is getting more
/// places, and with more spots the cost of every extra calculation is easier
/// to see. Every run uses the same data.
final spots = [
  for (var i = 0; i < 60; i++)
    Spot(
      id: 'spot-$i',
      emoji: '🍔',
      emojiBackground: const Color(0xFFFFFBEB),
      emojiBorder: const Color(0xFFFEF3C7),
      name: '${_cuisines[i % 6]} House $i',
      subtitle: '${_cuisines[i % 6]} • Building ${i % 10}',
      rating: 3 + (i % 20) / 10,
      price: '\$15.000 COP',
      distance: '${1 + i % 12} min walk',
      walkMinutes: 1 + i % 12,
      isBudget: i.isEven,
      isVegetarian: i % 3 == 0,
      isHighProtein: i % 4 == 0,
      affinityPercent: 50,
      category: SpotCategory.foodTrucks,
      noteLabel: 'Student tip',
      note: 'Quick line before 11.',
      latitude: 4.6018,
      longitude: -74.0661,
    ),
];

/// The match % the backend would send (smart feature), all different.
final matchScores = {for (var i = 0; i < 60; i++) 'spot-$i': 30 + (i * 37) % 70};

class _QuietPopularity extends Fake implements PopularityService {
  @override
  Future<HourlyRanking> rankingAt({required int hour, required int tzOffsetMinutes}) async =>
      HourlyRanking(hour: hour, totalPageViews: 0, totalSearches: 0, spots: const []);

  @override
  Future<WeekdaySearches> searchesByWeekday({required int tzOffsetMinutes}) async =>
      const WeekdaySearches(days: 28, totalSearches: 0, byDay: []);
}

class _NoPrefs extends Fake implements PopularityPrefs {
  @override
  Future<void> save(HourlyRanking ranking, {required DateTime savedAt}) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('For You: editing the search', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ForYouScreen(
          spots: spots,
          onToggleSaved: (_) {},
          onOpenSpot: (_) {},
          popularLoader: PopularityLoader(service: _QuietPopularity(), prefs: _NoPrefs()),
          matchScores: matchScores,
          weather: const WeatherNow(temperatureC: 14, precipitationMm: 1.2, weatherCode: 61),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pump(const Duration(milliseconds: 300));
    final controller = tester.widget<TextField>(field).controller!;

    Future<void> frame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }

    Future<void> editSearch() async {
      const word = 'burger';
      for (var length = 1; length <= word.length; length++) {
        final text = word.substring(0, length);
        await tester.enterText(field, text);
        await frame();
        // Three cursor moves: the text is the same, only the selection changes.
        for (final offset in [0, length ~/ 2, length]) {
          controller.selection = TextSelection.collapsed(offset: offset);
          await frame();
        }
      }
      // A space at the end: the search ignores it.
      await tester.enterText(field, '$word ');
      await frame();
      // Deleting letter by letter until the box is empty again.
      for (var length = word.length; length >= 0; length--) {
        await tester.enterText(field, word.substring(0, length));
        await frame();
      }
    }

    // 1) Frame times, without extra instrumentation.
    await binding.traceAction(editSearch, reportKey: 'for_you_search');

    // 2) The same edits with every widget build in the timeline.
    widgets.debugProfileBuildsEnabled = true;
    await binding.traceAction(editSearch, reportKey: 'for_you_search_builds');
    widgets.debugProfileBuildsEnabled = false;
  });
}
