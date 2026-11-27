import 'package:campus_bites/data/spots_data.dart';
import 'package:campus_bites/models/hourly_ranking.dart';
import 'package:campus_bites/models/spot.dart';
import 'package:campus_bites/screens/for_you_screen.dart';
import 'package:campus_bites/services/popularity_loader.dart';
import 'package:campus_bites/services/popularity_prefs.dart';
import 'package:campus_bites/services/popularity_service.dart';
import 'package:campus_bites/widgets/spot_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyService extends Fake implements PopularityService {
  @override
  Future<HourlyRanking> rankingAt({required int hour, required int tzOffsetMinutes}) async =>
      HourlyRanking.empty(hour);
}

class _NoPrefs extends Fake implements PopularityPrefs {
  @override
  Future<void> save(HourlyRanking ranking, {required DateTime savedAt}) async {}
}

/// Micro-optimization of For You: the feed and its cards are only calculated again when something they depend on changes.
void main() {
  final loader = PopularityLoader(service: _EmptyService(), prefs: _NoPrefs());
  void noop(String _) {}

  Widget screen(List<Spot> spots, {Map<String, int>? scores}) => MaterialApp(
        home: Scaffold(
          body: ForYouScreen(spots: spots, onToggleSaved: noop, popularLoader: loader, matchScores: scores),
        ),
      );

  SpotCard firstCard(WidgetTester tester) => tester.widget<SpotCard>(find.byType(SpotCard).first);

  testWidgets('moving the cursor or adding a space keeps the same feed and the same cards', (tester) async {
    await tester.pumpWidget(screen(sampleSpots));
    await tester.enterText(find.byType(TextField), 'bowl');
    await tester.pump();
    final before = firstCard(tester);

    final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    expect(firstCard(tester), same(before));

    await tester.enterText(find.byType(TextField), 'bowl  ');
    await tester.pump();
    expect(firstCard(tester), same(before));
  });

  testWidgets('a new letter calculates the feed again', (tester) async {
    await tester.pumpWidget(screen(sampleSpots));
    await tester.enterText(find.byType(TextField), 'b');
    await tester.pump();
    final before = firstCard(tester);
    await tester.enterText(find.byType(TextField), 'bo');
    await tester.pump();
    expect(firstCard(tester), isNot(same(before)));
  });

  testWidgets('only spaces still show the clear button', (tester) async {
    await tester.pumpWidget(screen(sampleSpots));
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);
  });

  testWidgets('a new list of spots (a heart changed) updates the cards', (tester) async {
    final spots = [for (final s in sampleSpots) s.copyWith(isSaved: false)];
    await tester.pumpWidget(screen(spots));
    final first = firstCard(tester).spot;
    expect(first.isSaved, isFalse);

    // HomeShell gives a new list when a heart changes, never the same one edited.
    await tester.pumpWidget(screen([
      for (final s in spots) s.id == first.id ? s.copyWith(isSaved: true) : s,
    ]));
    expect(firstCard(tester).spot.isSaved, isTrue);
  });

  testWidgets('new match scores sort the feed again', (tester) async {
    // Two spots that pass the default filter ("In a rush"), so both are in the feed.
    final quick = [for (final s in sampleSpots) if (s.walkMinutes < 10) s.id];
    final a = quick.first, b = quick.last;
    await tester.pumpWidget(screen(sampleSpots, scores: {a: 99, b: 10}));
    await tester.pump();
    expect(firstCard(tester).spot.id, a);

    await tester.pumpWidget(screen(sampleSpots, scores: {a: 10, b: 99}));
    await tester.pump();
    expect(firstCard(tester).spot.id, b);
  });

  testWidgets('changing a filter calculates the feed again', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen(sampleSpots));
    await tester.pump();
    expect(find.byType(SpotCard), findsNWidgets(sampleSpots.where((s) => s.walkMinutes < 10).length));
    // "In a rush" is on by default; adding Budget leaves only the cheap ones.
    await tester.tap(find.text(FeedFilterType.budget.label));
    await tester.pump();
    expect(
      find.byType(SpotCard),
      findsNWidgets(sampleSpots.where((s) => s.walkMinutes < 10 && s.isBudget).length),
    );
  });
}
