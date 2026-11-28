import 'dart:convert';
import 'dart:io';

import 'package:campus_bites/models/spot_detail.dart';
import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/repositories/favorites_repository.dart';
import 'package:campus_bites/repositories/spots_repository.dart';
import 'package:campus_bites/screens/place_detail_screen.dart';
import 'package:campus_bites/services/favorites_controller.dart';
import 'package:campus_bites/services/hive_store.dart';
import 'package:campus_bites/services/local_database.dart';
import 'package:campus_bites/services/review_interactions.dart';
import 'package:campus_bites/services/review_submitter.dart';
import 'package:campus_bites/services/telemetry_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _spotId = 'nitro-coffee';

Map<String, dynamic> _page(int reviews) => {
      'id': _spotId,
      'emoji': '☕',
      'emojiBackground': '#FFFBEB',
      'name': 'Nitro Coffee & Brew',
      'subtitle': 'Café & Bakery',
      'rating': 4.6,
      'totalReviews': reviews,
      'price': r'$$',
      'distance': '120 m',
      'walkMinutes': 2,
      'isVegetarian': true,
      'affinityPercent': 87,
      'note': 'Cold brew on tap.',
      'uniCardPerk': null,
      'reviews': [
        for (var i = 1; i <= reviews; i++)
          {'authorName': 'Student $i', 'initials': 'S$i', 'stars': 4, 'text': 'Review $i', 'dinedAgo': '1 day ago'},
      ],
    };

class _NoSavedDetails implements SpotDetailStorage {
  @override
  Future<void> save(SpotDetail spot) async {}

  @override
  Future<({SpotDetail spot, DateTime savedAt})?> read(String id) async => null;
}

/// Keeps the events the page enqueues instead of sending them.
class _RecordingTelemetry extends TelemetryQueue {
  final events = <TelemetryEvent>[];

  _RecordingTelemetry()
      : super(
          client: MockClient((_) async => http.Response('', 202)),
          loadDevice: () async => const DeviceContext(model: 'test', osVersion: '16'),
        );

  @override
  void enqueue(TelemetryEvent event) => events.add(event);
}

void main() {
  late Directory dir;
  late HiveStore store;

  setUp(() async {
    // The page listens to connectivity_plus; tests have no plugin behind it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    dir = await Directory.systemTemp.createTemp('place_detail_reviews_test');
    store = await HiveStore.open(directory: dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<({_RecordingTelemetry telemetry, List<ReviewInteractionTracker?> opened})> open(
    WidgetTester tester, {
    required int reviews,
  }) async {
    final client = MockClient((_) async => http.Response(jsonEncode(_page(reviews)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    final telemetry = _RecordingTelemetry();

    final spots = SpotsRepository(client: client, baseUrl: 'http://test');
    final favorites = FavoritesController(
      repository: FavoritesRepository(client: client, baseUrl: 'http://test'),
      telemetry: telemetry,
      currentUserId: () => null,
    );
    addTearDown(favorites.dispose);
    final opened = <ReviewInteractionTracker?>[];
    await tester.pumpWidget(MaterialApp(
      home: PlaceDetailScreen(
        spotId: _spotId,
        repository: spots,
        telemetry: telemetry,
        currentUserId: () => null,
        canReview: false,
        favorites: favorites,
        onToggleSaved: (_) {},
        reviewSubmitter: ReviewSubmitter(repository: spots, store: store, currentUserId: () => null),
        storage: _NoSavedDetails(),
        onOpenAllReviews: (_, interactions) => opened.add(interactions),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return (telemetry: telemetry, opened: opened);
  }

  testWidgets('the page shows the first 5 reviews and a button to see all of them', (tester) async {
    final page = await open(tester, reviews: 200);

    final button = find.text('See all reviews (200)');
    await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Review 5'), findsOneWidget);
    expect(find.text('Review 6'), findsNothing);

    await tester.tap(button);
    await tester.pump();

    // All reviews gets the tracker of this visit, so its open_all (BQ8) is
    // tied to the restaurant_detail event of the page.
    final visit = page.telemetry.events.singleWhere((e) => e.screen == 'restaurant_detail');
    expect(page.opened.single?.visitEventId, visit.eventId);
    page.telemetry.dispose();
  });

  testWidgets('with 5 reviews or fewer there is no button', (tester) async {
    final page = await open(tester, reviews: 3);

    await tester.scrollUntilVisible(find.text('Review 3'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('See all reviews'), findsNothing);
    page.telemetry.dispose();
  });
}
