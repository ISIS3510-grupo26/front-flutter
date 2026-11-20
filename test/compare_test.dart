import 'dart:async';
import 'dart:io';

import 'package:campus_bites/models/spot_comparison.dart';
import 'package:campus_bites/models/spot_detail.dart';
import 'package:campus_bites/models/wait_time.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/screens/compare_screen.dart';
import 'package:campus_bites/services/compare_loader.dart';
import 'package:campus_bites/services/comparison_history.dart';
import 'package:campus_bites/services/local_database.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SpotDetail detail(
  String id, {
  String name = 'Place',
  double rating = 4.5,
  String price = '\$12.000 COP',
  int walk = 5,
  bool veggie = false,
  int affinity = 70,
  String subtitle = 'Burgers • Plaza',
}) =>
    SpotDetail(
      id: id,
      emoji: '🍔',
      emojiBackground: const Color(0xFFFFFBEB),
      name: name,
      subtitle: subtitle,
      rating: rating,
      totalReviews: 10,
      price: price,
      distance: '$walk min walk',
      walkMinutes: walk,
      isVegetarian: veggie,
      affinityPercent: affinity,
      note: '',
      uniCardPerk: null,
      reviews: const [],
    );

final conda = detail('conda', name: 'Conda de Bons', rating: 5, price: '\$18.500 COP', walk: 5, affinity: 88);
final bowl = detail('bowl',
    name: 'Green Bowl Co.', rating: 4, price: '\$15.000 COP', walk: 3, veggie: true, affinity: 75,
    subtitle: 'Healthy Bowls • Central Library 1F');

LastWaitTime wait(String id, int? minutes, {bool recent = true}) => LastWaitTime(
      spotId: id,
      name: id,
      emoji: '🍔',
      minutes: minutes,
      minutesAgo: 5,
      isRecent: recent,
      recentReports: 1,
    );

class _MemoryDetails implements SpotDetailStorage {
  final saved = <String, ({SpotDetail spot, DateTime savedAt})>{};

  @override
  Future<({SpotDetail spot, DateTime savedAt})?> read(String id) async => saved[id];

  @override
  Future<void> save(SpotDetail spot) async => saved[spot.id] = (spot: spot, savedAt: DateTime(2026, 11, 20, 9, 30));
}

class _MemoryHistory implements ComparisonHistoryStorage {
  final entries = <ComparisonEntry>[];

  @override
  Future<List<ComparisonEntry>> recent() async => entries.reversed.toList();

  @override
  Future<void> save(ComparisonEntry entry) async => entries.add(entry);
}

/// A backend that counts requests and can be offline or broken per spot.
class _FakeApi {
  final pages = {'conda': conda, 'bowl': bowl};
  final calls = <String>[];
  Object? spotError;
  final errorFor = <String, Object>{};
  Object? waitsError;
  var waits = [wait('conda', 8), wait('bowl', 20)];
  Completer<void>? gate;

  Future<SpotDetail> fetchSpot(String id) async {
    calls.add(id);
    await gate?.future;
    if (errorFor[id] ?? spotError case final e?) throw e;
    return pages[id]!;
  }

  Future<List<LastWaitTime>> fetchWaits() async {
    calls.add('waits');
    await gate?.future;
    if (waitsError case final e?) throw e;
    return waits;
  }
}

void main() {
  group('buildSpotComparison', () {
    SpotComparison build({SpotDetail? a, SpotDetail? b, int? waitA = 8, int? waitB = 20, int? matchA, int? matchB}) =>
        buildSpotComparison((
          first: CompareSideInput(
              id: 'conda', detail: a?.toJson(), match: matchA, waitMinutes: waitA, fallbackName: 'Conda', fallbackEmoji: '🍔'),
          second: CompareSideInput(
              id: 'bowl', detail: b?.toJson(), match: matchB, waitMinutes: waitB, fallbackName: 'Bowl', fallbackEmoji: '🥗'),
        ));

    test('marks the better restaurant in every row and gives a verdict', () {
      final c = build(a: conda, b: bowl);
      final rows = {for (final r in c.rows) r.label: r};
      expect(rows['Taste match']!.first, '88%');
      expect(rows['Taste match']!.winner, CompareSide.first);
      expect(rows['Rating']!.first, '5.0 ★ (10)');
      expect(rows['Rating']!.winner, CompareSide.first);
      expect(rows['Price']!.winner, CompareSide.second); // 15.000 < 18.500
      expect(rows['Walk']!.winner, CompareSide.second);
      expect(rows['Wait now']!.first, '8 min');
      expect(rows['Wait now']!.winner, CompareSide.first);
      expect(rows['Vegetarian']!.second, 'Yes');
      expect(rows['Vegetarian']!.winner, CompareSide.second);
      expect(rows['Cuisine']!.second, 'Healthy Bowls');
      expect(rows['Cuisine']!.winner, CompareSide.none);
      expect((c.firstWins, c.secondWins, c.decidedRows), (3, 3, 6));
      expect(c.verdict, "It's a tie, 3 each.");
      expect(c.complete, isTrue);
    });

    test("the student's match replaces the catalog % and decides the verdict", () {
      final c = build(a: conda, b: bowl, matchA: 40, matchB: 95, waitA: null);
      expect(c.rows.first.first, '40%');
      expect(c.rows.first.winner, CompareSide.second);
      expect(c.rows.firstWhere((r) => r.label == 'Wait now').first, 'No recent report');
      expect(c.verdict, 'Green Bowl Co. wins 4 of 5.');
    });

    test('a missing page shows dashes, no winners and no verdict', () {
      final c = build(a: conda, b: null);
      expect(c.complete, isFalse);
      expect(c.secondName, 'Bowl');
      expect(c.secondEmoji, '🥗');
      expect(c.rows.every((r) => r.second == '—' && r.winner == CompareSide.none), isTrue);
      expect(c.verdict, isNull);
    });

    test('prices compare by their lowest value', () {
      expect(lowestPrice('\$12.000 - \$22.000 COP'), 12000);
      expect(lowestPrice('\$6.500 COP'), 6500);
      expect(lowestPrice('Free'), isNull);
      expect(cuisineOf('Burgers & Fries • North Quad Plaza'), 'Burgers & Fries');
    });
  });

  group('CompareLoader', () {
    late _FakeApi api;
    late _MemoryDetails details;
    late _MemoryHistory history;
    List<LastWaitTime>? savedWaits;

    CompareLoader loader() => CompareLoader(
          fetchSpot: api.fetchSpot,
          fetchWaits: api.fetchWaits,
          details: details,
          savedWaits: () async => savedWaits,
          history: history,
        );

    setUp(() {
      api = _FakeApi();
      details = _MemoryDetails();
      history = _MemoryHistory();
      savedWaits = null;
    });

    test('asks for both pages and the waits at the same time and builds in an isolate', () async {
      api.gate = Completer();
      final future = loader().load('conda', 'bowl');
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, ['conda', 'bowl', 'waits']); // all three started before any answered
      api.gate!.complete();

      final state = await future as CompareLoaded;
      expect(state.comparison.firstName, 'Conda de Bons');
      expect(state.offlineSavedAt, isNull);
      expect(state.needsNetwork, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(details.saved.keys, containsAll(['conda', 'bowl'])); // saved for offline use
      expect(history.entries.single.pairId, 'bowl|conda');
    });

    test('LRU: a second comparison reuses the pages and waits, Retry skips the cache', () async {
      final l = loader();
      await l.load('conda', 'bowl');
      api.calls.clear();
      await l.load('bowl', 'conda');
      expect(api.calls, isEmpty);
      await l.load('conda', 'bowl', forceRefresh: true);
      expect(api.calls, ['conda', 'bowl', 'waits']);
    });

    test('offline: compares the pages saved on the phone and says when they were saved', () async {
      await details.save(conda);
      await details.save(bowl);
      api.spotError = const SocketException('offline');
      api.waitsError = const SocketException('offline');
      savedWaits = [wait('conda', 12)];

      final state = await loader().load('conda', 'bowl') as CompareLoaded;
      expect(state.offlineSavedAt, DateTime(2026, 11, 20, 9, 30));
      expect(state.missingIds, isEmpty);
      expect(state.needsNetwork, isTrue);
      expect(state.comparison.rows.firstWhere((r) => r.label == 'Wait now').first, '12 min');
    });

    test('offline with one page never opened: that side is missing, the other still shows', () async {
      await details.save(conda);
      api.spotError = TimeoutException('no answer');
      final state = await loader().load('conda', 'bowl') as CompareLoaded;
      expect(state.missingIds, {'bowl'});
      expect(state.comparison.complete, isFalse);
      expect(state.comparison.rows.first.first, '88%');
      expect(history.entries, isEmpty); // incomplete comparisons are not saved
    });

    test('offline with nothing saved fails as network; a server error never uses saved pages', () async {
      api.spotError = const SocketException('offline');
      expect(((await loader().load('conda', 'bowl')) as CompareFailed).reason, CompareFailure.network);

      await details.save(conda);
      await details.save(bowl);
      api.spotError = null;
      api.errorFor['bowl'] = const ApiException(500);
      expect(((await loader().load('conda', 'bowl')) as CompareFailed).reason, CompareFailure.server);
    });

    test('the waits failing does not fail the comparison', () async {
      api.waitsError = const ApiException(503);
      final state = await loader().load('conda', 'bowl') as CompareLoaded;
      expect(state.comparison.rows.firstWhere((r) => r.label == 'Wait now').first, 'No recent report');
    });
  });

  group('CompareScreen', () {
    Future<void> pump(WidgetTester tester, CompareLoader loader, {Stream<List<ConnectivityResult>>? connectivity}) async {
      // Tall enough for the whole table: the list builds its rows lazily.
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: CompareScreen(firstId: 'conda', secondId: 'bowl', loader: loader, connectivity: connectivity),
      ));
    }

    // The isolate needs real async; the table is built synchronously in these tests.
    CompareLoader loaderFor(_FakeApi api, _MemoryDetails details) => CompareLoader(
          fetchSpot: api.fetchSpot,
          fetchWaits: api.fetchWaits,
          details: details,
          build: (input) async => buildSpotComparison(input),
        );

    testWidgets('shows both columns, the winners and the verdict', (tester) async {
      await pump(tester, loaderFor(_FakeApi(), _MemoryDetails()));
      await tester.pumpAndSettle();
      expect(find.text('Conda de Bons'), findsOneWidget);
      expect(find.text('Green Bowl Co.'), findsOneWidget);
      expect(find.text("It's a tie, 3 each."), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(6));
    });

    testWidgets('offline with saved pages shows the banner, and reloads when the network returns', (tester) async {
      final api = _FakeApi()..spotError = const SocketException('offline');
      final details = _MemoryDetails();
      await details.save(conda);
      await details.save(bowl);
      final connectivity = StreamController<List<ConnectivityResult>>();
      await pump(tester, loaderFor(api, details), connectivity: connectivity.stream);
      await tester.pumpAndSettle();
      expect(find.text('Offline · pages saved at 09:30'), findsOneWidget);

      api.spotError = null;
      connectivity.add([ConnectivityResult.wifi]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('Offline'), findsNothing);
      await connectivity.close();
    });

    testWidgets('offline with nothing saved explains it and offers Retry', (tester) async {
      final api = _FakeApi()..spotError = const SocketException('offline');
      await pump(tester, loaderFor(api, _MemoryDetails()));
      await tester.pumpAndSettle();
      expect(find.textContaining("You're offline and these places aren't saved"), findsOneWidget);

      api.spotError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Conda de Bons'), findsOneWidget);
    });

    testWidgets('a server error has its own message', (tester) async {
      final api = _FakeApi()..spotError = const ApiException(500);
      await pump(tester, loaderFor(api, _MemoryDetails()));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load this comparison."), findsOneWidget);
    });
  });
}
