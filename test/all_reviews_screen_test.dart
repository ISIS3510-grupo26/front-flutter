import 'dart:io';

import 'package:campus_bites/models/review_page.dart';
import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/screens/all_reviews_screen.dart';
import 'package:campus_bites/services/all_reviews_loader.dart';
import 'package:campus_bites/services/helpful_queue.dart';
import 'package:campus_bites/services/review_interactions.dart';
import 'package:campus_bites/services/reviews_local_store.dart';
import 'package:campus_bites/services/reviews_service.dart';
import 'package:campus_bites/widgets/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _spot = 'poodle-pizza-slices';

ReviewItem _item(int id, {int helpful = 3}) => ReviewItem.fromJson({
      'id': id,
      'authorName': 'student$id',
      'initials': 'S$id',
      'program': 'Student',
      'stars': 4,
      'text': 'Review number $id',
      'dinedAgo': '2 days ago',
      'helpfulCount': helpful,
      'createdAt': null,
    });

/// Answers every query with [answer] and records it.
class _FakeLoader implements AllReviewsLoader {
  final queries = <ReviewQuery>[];
  ReviewsResult Function(ReviewQuery query) answer;
  ReviewsResult Function(ReviewQuery query)? offlineAnswer;

  _FakeLoader(this.answer);

  @override
  Future<ReviewsResult> load(ReviewQuery query, {bool forceRefresh = false}) async {
    queries.add(query);
    return answer(query);
  }

  @override
  ReviewsResult offline(ReviewQuery query) => offlineAnswer!(query);
}

/// 25 reviews, 10 per page.
ReviewsResult _pages(ReviewQuery query) {
  final first = (query.page - 1) * 10 + 1;
  return ReviewsLoaded(
    items: [for (var id = first; id < first + 10 && id <= 25; id++) _item(id)],
    total: 25,
    hasMore: query.page * 10 < 25,
    votes: const {},
  );
}

class _OfflineService implements ReviewsService {
  @override
  Future<ReviewPage> page(ReviewQuery query) => throw const SocketException('offline');

  @override
  Future<Set<int>> myHelpfulVotes(String spotId, String userId) => throw const SocketException('offline');

  @override
  Future<void> setHelpful(String spotId, int reviewId, String userId, {required bool helpful}) =>
      throw const SocketException('offline');
}

void main() {
  late List<TelemetryEvent> sent;
  late ReviewInteractionTracker tracker;

  setUp(() {
    sent = [];
    tracker = ReviewInteractionTracker(
      spotId: _spot,
      visitEventId: 'visit-0123456789',
      currentUserId: () => 'dev-ana',
      send: sent.add,
    );
  });

  List<String> actions() => [for (final e in sent) e.eventId.split('-').last];

  Future<void> open(WidgetTester tester, _FakeLoader loader, {HelpfulQueue? helpful}) async {
    await tester.pumpWidget(MaterialApp(
      home: AllReviewsScreen(
        spotId: _spot,
        spotName: 'Poodle Pizza',
        loader: loader,
        helpful: helpful,
        interactions: tracker,
      ),
    ));
    await tester.pump();
  }

  testWidgets('shows the first page and reorders and filters with the chips', (tester) async {
    final loader = _FakeLoader(_pages);
    await open(tester, loader);

    expect(find.text('Review number 1'), findsOneWidget);
    expect(find.text('25 reviews'), findsOneWidget);

    await tester.tap(find.text('Most helpful'));
    await tester.pump();
    await tester.tap(find.text('5 ★'));
    await tester.pump();
    await tester.tap(find.text('Highest'));
    await tester.pump();

    expect(loader.queries.map((q) => (q.sort, q.stars)), [
      (ReviewSort.newest, null),
      (ReviewSort.helpful, null),
      (ReviewSort.helpful, 5),
      (ReviewSort.highest, 5),
    ]);
    expect(actions(), ['open_all', 'sort', 'filter']); // the second sort is not sent again
  });

  testWidgets('search waits 300 ms after the last key and sends one request', (tester) async {
    final loader = _FakeLoader(_pages);
    await open(tester, loader);

    await tester.enterText(find.byType(TextField), 'p');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'piz');
    await tester.pump(const Duration(milliseconds: 299));
    expect(loader.queries, hasLength(1));

    await tester.pump(const Duration(milliseconds: 1));
    expect(loader.queries.last.q, 'piz');
    expect(loader.queries, hasLength(2));
    expect(actions(), ['open_all', 'search']);
  });

  testWidgets('reaching the end of the list loads the next page', (tester) async {
    final loader = _FakeLoader(_pages);
    await open(tester, loader);

    await tester.scrollUntilVisible(find.text('Review number 15'), 300, scrollable: find.byType(Scrollable).last);
    await tester.pump();

    expect(loader.queries.map((q) => q.page), containsAllInOrder([1, 2]));
    expect(find.text('Review number 15'), findsOneWidget);
  });

  testWidgets('offline with a copy: banner, and the chips work on the copy without a request', (tester) async {
    final savedAt = DateTime(2026, 11, 20, 9, 5);
    final loader = _FakeLoader((q) => ReviewsLoaded(
          items: [_item(1), _item(2)],
          total: 2,
          hasMore: false,
          votes: const {},
          offlineSavedAt: savedAt,
        ))
      ..offlineAnswer = (q) => ReviewsLoaded(
            items: [_item(2)],
            total: 1,
            hasMore: false,
            votes: const {},
            offlineSavedAt: savedAt,
          );
    await open(tester, loader);

    expect(find.text('Offline · reviews from ${hourMinute(savedAt)}'), findsOneWidget);

    await tester.tap(find.text('Lowest'));
    await tester.pump();

    expect(loader.queries, hasLength(1)); // applied on the phone
    expect(find.text('Review number 1'), findsNothing);
    expect(find.text('Review number 2'), findsOneWidget);
  });

  testWidgets('offline without a copy shows its own message', (tester) async {
    await open(tester, _FakeLoader((_) => const ReviewsFailed(ReviewsFailure.network)));

    expect(find.textContaining('no reviews saved on your phone'), findsOneWidget);
    expect(find.byType(OfflineBanner), findsNothing);
  });

  testWidgets('a server error offers Retry, which skips the cache', (tester) async {
    var calls = 0;
    final loader = _FakeLoader((q) => ++calls == 1 ? const ReviewsFailed(ReviewsFailure.server) : _pages(q));
    await open(tester, loader);

    expect(find.text("CampusBites couldn't load the reviews right now."), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.text('Review number 1'), findsOneWidget);
  });

  group('Helpful', () {
    late Directory dir;
    late ReviewsLocalStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('all_reviews_screen_test');
      Hive.init(dir.path);
      store = await ReviewsLocalStore.open();
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    testWidgets('offline, the tap marks the review, adds one to the count and stays pending', (tester) async {
      final helpful = HelpfulQueue(service: _OfflineService(), local: store, currentUserId: () => 'dev-ana');
      await open(tester, _FakeLoader(_pages), helpful: helpful);
      expect(find.text('Helpful · 3'), findsNWidgets(find.byType(ReviewTile).evaluate().length));

      await tester.runAsync(() async {
        await tester.tap(find.text('Helpful · 3').first);
        await Future<void>.delayed(const Duration(milliseconds: 100)); // the Hive write
      });
      await tester.pump();

      expect(find.text('Helpful · 4'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
      expect(store.pendingVotes, {1: true});
      expect(actions(), ['open_all', 'helpful']);
      helpful.dispose();
    });
  });
}
