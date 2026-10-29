import 'package:campus_bites/data/spots_data.dart';
import 'package:campus_bites/models/hourly_ranking.dart';
import 'package:campus_bites/models/weekday_searches.dart';
import 'package:campus_bites/screens/for_you_screen.dart';
import 'package:campus_bites/services/popularity_loader.dart';
import 'package:campus_bites/services/popularity_prefs.dart';
import 'package:campus_bites/services/popularity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyService extends Fake implements PopularityService {
  @override
  Future<HourlyRanking> rankingAt({
    required int hour,
    required int tzOffsetMinutes,
  }) async => HourlyRanking.empty(hour);

  @override
  Future<WeekdaySearches> searchesByWeekday({required int tzOffsetMinutes}) =>
      throw UnimplementedError();
}

class _NoPrefs extends Fake implements PopularityPrefs {
  @override
  Future<void> save(HourlyRanking ranking, {required DateTime savedAt}) async {}
}

void main() {
  test('search matches the name, the cuisine or the place, ignoring case', () {
    final conda = sampleSpots.firstWhere((s) => s.id == 'conda-de-bons');

    expect(conda.matchesSearch('conda'), isTrue);
    expect(conda.matchesSearch('BURGERS'), isTrue);
    expect(conda.matchesSearch('north quad'), isTrue);
    expect(conda.matchesSearch(' fries '), isTrue);
    expect(conda.matchesSearch('pizza'), isFalse);
  });

  group('For You search', () {
    late List<String> opened;
    late List<String> openedFromSearch;

    Future<void> pump(WidgetTester tester) async {
      opened = [];
      openedFromSearch = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ForYouScreen(
              spots: sampleSpots,
              onToggleSaved: (_) {},
              onOpenSpot: opened.add,
              onOpenFromSearch: openedFromSearch.add,
              popularLoader: PopularityLoader(
                service: _EmptyService(),
                prefs: _NoPrefs(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows every match and hides the filters', (tester) async {
      await pump(tester);
      expect(find.text('\$ Budget'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pumpAndSettle();

      expect(find.text('Poodle Pizza Slices'), findsOneWidget);
      expect(find.text('Conda de Bons'), findsNothing);
      expect(find.text('\$ Budget'), findsNothing);
    });

    testWidgets('a spot opened from the results counts as a search', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Poodle Pizza Slices'));

      expect(openedFromSearch, ['poodle-pizza-slices']);
      expect(opened, isEmpty);
    });

    testWidgets(
      'no match says what was searched; clearing brings the feed back',
      (tester) async {
        await pump(tester);
        await tester.enterText(find.byType(TextField), 'sushi');
        await tester.pumpAndSettle();
        expect(find.text('No spots match "sushi".'), findsOneWidget);

        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('\$ Budget'), findsOneWidget);
        expect(find.text('No spots match "sushi".'), findsNothing);
      },
    );
  });
}
