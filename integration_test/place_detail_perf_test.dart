// Micro-optimization evidence (Sprint 4): the reviews of a restaurant page.
// Run in profile mode on a phone, with the same driver as the Taste Map:
//
//   flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart \
//     --target=integration_test/place_detail_perf_test.dart
//
// It opens a restaurant with 200 reviews (fake backend, so every run sees the
// same data) and records three scenarios, each with a fixed number of
// repetitions:
//
// - reviews_load: the page opened 5 times (request, JSON, first frames).
// - reviews_rebuild: the page rebuilt 30 times by its parent, which runs the
//   same build() as a setState of the page.
// - reviews_scroll: 4 rounds of 10 drags of 300 px down and 10 back up.
//
// reviews_rebuild_builds and reviews_scroll_builds repeat the last two with
// debugProfileBuildsEnabled, to count the widgets built
// (docs/profiling/count_rebuilds.py). The driver writes everything to build/;
// the copies kept for the wiki are in docs/profiling/reviews_list/.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:campus_bites/models/spot_detail.dart';
import 'package:campus_bites/repositories/favorites_repository.dart';
import 'package:campus_bites/repositories/spots_repository.dart';
import 'package:campus_bites/screens/place_detail_screen.dart';
import 'package:campus_bites/services/favorites_controller.dart';
import 'package:campus_bites/services/hive_store.dart';
import 'package:campus_bites/services/local_database.dart';
import 'package:campus_bites/services/review_submitter.dart';
import 'package:campus_bites/services/telemetry_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

const _spotId = 'nitro-coffee';
const _reviewCount = 200;

/// 200 reviews with texts of 1 to 4 sentences, so the cards have different
/// heights like real ones.
final _page = {
  'id': _spotId,
  'emoji': '☕',
  'emojiBackground': '#FFFBEB',
  'name': 'Nitro Coffee & Brew',
  'subtitle': 'Café & Bakery · Edificio ML',
  'rating': 4.6,
  'totalReviews': _reviewCount,
  'price': r'$$',
  'distance': '120 m',
  'walkMinutes': 2,
  'isVegetarian': true,
  'affinityPercent': 87,
  'note': 'Cold brew on tap.',
  'uniCardPerk': null,
  'reviews': [
    for (var i = 1; i <= _reviewCount; i++)
      {
        'authorName': 'Student $i',
        'initials': 'S${i % 10}',
        'stars': i % 5 + 1,
        'text': List.filled(i % 4 + 1, 'Review $i: good coffee, the line moves fast and the staff is friendly.')
            .join(' '),
        'dinedAgo': '${i % 30 + 1} days ago',
      },
  ],
};

class _MemoryDetails implements SpotDetailStorage {
  @override
  Future<void> save(SpotDetail spot) async {}

  @override
  Future<({SpotDetail spot, DateTime savedAt})?> read(String id) async => null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Place detail: 200 reviews', (tester) async {
    final client = MockClient((request) async => request.url.path.endsWith('/spots/$_spotId')
        ? http.Response(jsonEncode(_page), 200, headers: {'content-type': 'application/json; charset=utf-8'})
        : http.Response('{"accepted":0,"duplicates":0}', 202));
    final telemetry = TelemetryQueue(
      client: client,
      loadDevice: () async => const DeviceContext(model: 'perf', osVersion: '16'),
    );
    final dir = await Directory.systemTemp.createTemp('place_detail_perf');
    final store = await HiveStore.open(directory: dir.path);
    final spots = SpotsRepository(client: client, baseUrl: 'http://perf');
    final favorites = FavoritesController(
      repository: FavoritesRepository(client: client, baseUrl: 'http://perf'),
      telemetry: telemetry,
      currentUserId: () => null,
    );
    late StateSetter rebuildParent;
    var rebuilds = 0;

    Widget app() => MaterialApp(
          home: StatefulBuilder(builder: (context, setState) {
            rebuildParent = setState;
            return PlaceDetailScreen(
              spotId: _spotId,
              repository: spots,
              telemetry: telemetry,
              currentUserId: () => null,
              canReview: false,
              favorites: favorites,
              onToggleSaved: (_) {},
              reviewSubmitter: ReviewSubmitter(repository: spots, store: store, currentUserId: () => null),
              storage: _MemoryDetails(),
              onOpenAllReviews: (_, _) {},
            );
          }),
        );

    final loaded = find.text('Student Reviews ($_reviewCount)');

    Future<void> openPage() async {
      await tester.pumpWidget(app());
      for (var i = 0; i < 100 && loaded.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(loaded, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 16));
    }

    Future<void> openFiveTimes() async {
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 50));
        await openPage();
      }
    }

    Future<void> rebuildThirtyTimes() async {
      for (var i = 0; i < 30; i++) {
        rebuildParent(() => rebuilds++);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> scrollRounds() async {
      final list = find.byType(CustomScrollView);
      for (var round = 0; round < 4; round++) {
        for (final dy in [-300.0, 300.0]) {
          for (var i = 0; i < 10; i++) {
            await tester.drag(list, Offset(0, dy), warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 16));
          }
        }
      }
    }

    await openPage();
    // For the DevTools screenshots (flutter run --profile
    // --dart-define=PERF_WAIT_FOR_START=true): the scenarios wait until
    // DevTools is ready and someone confirms from the PC console by calling
    // the VM service extension ext.campus_bites.startPerf (see
    // docs/profiling/reviews_list/README.md). Off when measuring.
    if (const bool.fromEnvironment('PERF_WAIT_FOR_START')) {
      final start = Completer<void>();
      developer.registerExtension('ext.campus_bites.startPerf', (method, parameters) async {
        if (!start.isCompleted) start.complete();
        return developer.ServiceExtensionResponse.result('{"started":true}');
      });
      debugPrint('PERF: waiting for ext.campus_bites.startPerf to start the scenarios');
      await start.future;
      debugPrint('PERF: starting the scenarios');
    }

    // DevTools mode (flutter run --profile --dart-define=PERF_DEVTOOLS=true):
    // the same gestures without traceAction. traceAction connects to the VM
    // service from inside the app, which only works under flutter drive, and
    // it would take the timeline away from DevTools anyway. The numbers come
    // from the normal runs; this one is only for the DevTools screenshots.
    if (const bool.fromEnvironment('PERF_DEVTOOLS')) {
      await openFiveTimes();
      await rebuildThirtyTimes();
      await scrollRounds();
      debugPrint('PERF: scenarios finished; the app stays open for DevTools');
      await Future<void>.delayed(const Duration(days: 1));
      return;
    }

    // 1) Frame times, without extra instrumentation.
    await binding.traceAction(openFiveTimes, reportKey: 'reviews_load');
    await binding.traceAction(rebuildThirtyTimes, reportKey: 'reviews_rebuild');
    await binding.traceAction(scrollRounds, reportKey: 'reviews_scroll');

    // 2) The same rebuilds and scrolls with every widget build in the
    //    timeline, to count what is built.
    widgets.debugProfileBuildsEnabled = true;
    await binding.traceAction(rebuildThirtyTimes, reportKey: 'reviews_rebuild_builds');
    await binding.traceAction(scrollRounds, reportKey: 'reviews_scroll_builds');
    widgets.debugProfileBuildsEnabled = false;

    await tester.pumpWidget(const SizedBox());
    favorites.dispose();
    telemetry.dispose();
    await Hive.close();
  });
}
