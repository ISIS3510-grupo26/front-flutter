import 'package:campus_bites/models/hourly_ranking.dart';
import 'package:campus_bites/services/popularity_loader.dart';
import 'package:campus_bites/widgets/popular_now_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ranking = HourlyRanking(
  hour: 13,
  totalPageViews: 13,
  totalSearches: 2,
  spots: [
    SpotActivity(
      rank: 1,
      spotId: 'la-esquina-burger-lab',
      name: 'La Esquina Burger Lab & Craft Shakes Original Recipe Since 1998',
      emoji: '🍔',
      pageViews: 12,
      searches: 1,
      total: 13,
    ),
    SpotActivity(
      rank: 2,
      spotId: 'nitro-coffee',
      name: 'Nitro Coffee',
      emoji: '☕',
      pageViews: 1,
      searches: 1,
      total: 2,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  PopularityState state, {
  Size size = const Size(320, 640),
  double textScale = 1,
  ValueChanged<String>? onOpenSpot,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: ListView(
            children: [
              PopularNowSection(
                state: state,
                onRetry: () {},
                onSeeAll: () {},
                onOpenSpot: onOpenSpot,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows each spot with its activity and reason, and opens it', (
    tester,
  ) async {
    String? opened;
    await _pump(
      tester,
      const PopularityLoaded(_ranking),
      onOpenSpot: (id) => opened = id,
    );

    expect(find.text('12 views · 1 search'), findsOneWidget);
    expect(find.text('Popular now'), findsNWidgets(2));
    expect(find.textContaining('13:00–14:00'), findsOneWidget);

    await tester.tap(find.text('Nitro Coffee'));
    expect(opened, 'nitro-coffee');
  });

  testWidgets('long names and big text do not overflow, upright or rotated', (
    tester,
  ) async {
    await _pump(tester, const PopularityLoaded(_ranking), textScale: 2);
    expect(tester.takeException(), isNull);

    await _pump(
      tester,
      const PopularityLoaded(_ranking),
      size: const Size(640, 320),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved data says when it was saved', (tester) async {
    await _pump(
      tester,
      PopularityLoaded(_ranking, offlineSavedAt: DateTime(2026, 10, 29, 9, 5)),
    );

    expect(find.text('Offline · data from 09:05'), findsOneWidget);
  });

  testWidgets('an empty hour still links to the other hours', (tester) async {
    await _pump(tester, const PopularityEmpty(13));

    expect(find.text('No activity yet this hour.'), findsOneWidget);
    expect(find.textContaining('13:00–14:00'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('See all needs a connection', (tester) async {
    await _pump(tester, const PopularityLoaded(_ranking));
    expect(find.text('See all'), findsOneWidget);

    await _pump(
      tester,
      PopularityLoaded(_ranking, offlineSavedAt: DateTime(2026, 10, 29, 9, 5)),
    );
    expect(find.text('See all'), findsNothing);

    await _pump(tester, const PopularityFailed(PopularityFailure.network));
    expect(find.text('See all'), findsNothing);
  });

  testWidgets('each failure has its own message', (tester) async {
    await _pump(tester, const PopularityFailed(PopularityFailure.network));
    expect(
      find.textContaining("Offline · popular spots show up"),
      findsOneWidget,
    );

    await _pump(tester, const PopularityFailed(PopularityFailure.server));
    expect(
      find.text("Couldn't load what's popular right now."),
      findsOneWidget,
    );
  });
}
