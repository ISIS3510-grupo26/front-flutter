// Micro-optimization evidence (Sprint 4): what HomeShell rebuilds when a heart
// is tapped on For You. Run in profile mode on a phone, with the local backend
// reachable from the phone (adb reverse) so every save gets the same answer:
//
//   adb reverse tcp:8000 tcp:8000
//   flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart \
//     --target=integration_test/home_shell_perf_test.dart \
//     --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 --endless-trace-buffer
//
// It opens the real HomeShell with a development user and fresh Hive boxes,
// waits until the first loads are done (weather, matches, sections) and taps
// the heart of the first For You card 20 times (save, unsave, ...), waiting
// for each save to reach the backend. home_shell_heart_taps has the frame
// times; home_shell_heart_taps_builds the same taps with every widget build
// in the timeline, to count what each tab rebuilds per tap
// (docs/profiling/count_rebuilds.py, ForYouScreen as the per-tap widget).
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:campus_bites/models/auth_user.dart';
import 'package:campus_bites/repositories/auth_repository.dart';
import 'package:campus_bites/screens/home_shell.dart';
import 'package:campus_bites/services/auth_session.dart';
import 'package:campus_bites/services/favorites_local_store.dart';
import 'package:campus_bites/services/hive_store.dart';
import 'package:campus_bites/services/reviews_local_store.dart';
import 'package:campus_bites/services/token_store.dart';
import 'package:campus_bites/widgets/spot_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

const _taps = 20;

/// No stored session: the test enters as the development user.
class _NoTokens implements TokenStore {
  const _NoTokens();

  @override
  Future<AuthUser?> read() async => null;

  @override
  Future<void> write(AuthUser user) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomeShell: tapping a heart on For You', (tester) async {
    final dir = await Directory.systemTemp.createTemp('home_shell_perf');
    final store = await HiveStore.open(directory: dir.path);
    final favoritesStore = await FavoritesLocalStore.open();
    final reviewsStore = await ReviewsLocalStore.open();
    final session = AuthSession(
      repository: AuthRepository(client: http.Client()),
      store: const _NoTokens(),
      devUserId: 'perf-home-shell',
    );
    await session.restore();
    session.continueAsDevUser();

    await tester.pumpWidget(MaterialApp(
      home: HomeShell(
        session: session,
        store: store,
        favoritesStore: favoritesStore,
        reviewsStore: reviewsStore,
      ),
    ));

    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // The first loads (weather from the internet, saved places, matches, the
    // For You sections) finish here, so they don't land in the measured taps.
    await frames(600); // about 10 s
    // The feed is a lazy list: when the sections above it have loaded, its
    // cards are not built until the list is scrolled down to them.
    final cards = find.byType(SpotCard);
    for (var i = 0; i < 60 && cards.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300), warnIfMissed: false);
      await frames(10);
    }
    final heart = find.descendant(of: cards.first, matching: find.byType(IconButton));
    await tester.scrollUntilVisible(heart, 100, scrollable: find.byType(Scrollable).first);
    await frames(600); // about 10 s more, so nothing is loading while the taps are measured

    Future<void> tapTheHeart() async {
      for (var i = 0; i < _taps; i++) {
        await tester.tap(heart, warnIfMissed: false);
        // A tap on a heart whose save is still in flight is ignored, so each
        // tap waits for its save (local backend: a few ms) before the next.
        await frames(20);
      }
    }

    // For the DevTools screenshots, the same two modes as
    // place_detail_perf_test.dart (see docs/profiling/home_shell_rebuilds/README.md):
    // PERF_WAIT_FOR_START waits for ext.campus_bites.startPerf from the PC,
    // PERF_DEVTOOLS runs the taps without traceAction. Both off when measuring.
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
    if (const bool.fromEnvironment('PERF_DEVTOOLS')) {
      await tapTheHeart();
      debugPrint('PERF: scenarios finished; the app stays open for DevTools');
      await Future<void>.delayed(const Duration(days: 1));
      return;
    }

    // 1) Frame times, without extra instrumentation.
    await binding.traceAction(tapTheHeart, reportKey: 'home_shell_heart_taps');

    // 2) The same taps with every widget build in the timeline.
    widgets.debugProfileBuildsEnabled = true;
    await binding.traceAction(tapTheHeart, reportKey: 'home_shell_heart_taps_builds');
    widgets.debugProfileBuildsEnabled = false;

    await tester.pumpWidget(const SizedBox());
    await favoritesStore.clear();
    await reviewsStore.clear();
  });
}
