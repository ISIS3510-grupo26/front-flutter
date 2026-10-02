import 'dart:async';

import 'package:campus_bites/data/spots_data.dart';
import 'package:campus_bites/screens/saved_places_screen.dart';
import 'package:campus_bites/services/nearby_favorites_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLoader implements NearbyFavoritesLoader {
  final result = Completer<NearbyState>();

  @override
  Future<NearbyState> load() => result.future;

  @override
  Future<bool> openLocationSettings() async => true;
}

void main() {
  testWidgets(
      'reopening the nearby filter while it is still loading shows the result',
      (tester) async {
    final loader = _FakeLoader();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SavedPlacesScreen(
          spots: sampleSpots,
          onToggleSaved: (_) {},
          nearbyLoader: loader,
        ),
      ),
    ));
    final nearbyPill = find.text('Open • ≤15 min');

    await tester.tap(nearbyPill);
    await tester.pump();
    await tester.tap(find.text('All Saved'));
    await tester.pump();
    await tester.tap(nearbyPill);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    loader.result.complete(const NearbyLoaded({'green-bowl-co': 4}));
    await tester.pumpAndSettle();

    expect(find.text('Green Bowl Co.'), findsOneWidget);
    expect(find.text('4 min walk'), findsOneWidget);
    expect(find.text('Nitro Coffee & Brew'), findsNothing);
  });
}
