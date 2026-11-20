import 'dart:async';
import 'dart:io';

import 'package:campus_bites/data/spots_data.dart';
import 'package:campus_bites/main.dart';
import 'package:campus_bites/models/auth_user.dart';
import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/auth_repository.dart';
import 'package:campus_bites/repositories/favorites_repository.dart';
import 'package:campus_bites/screens/saved_places_screen.dart';
import 'package:campus_bites/services/auth_session.dart';
import 'package:campus_bites/services/favorites_controller.dart';
import 'package:campus_bites/services/favorites_local_store.dart';
import 'package:campus_bites/services/nearby_favorites_loader.dart';
import 'package:campus_bites/services/telemetry_queue.dart';
import 'package:campus_bites/services/token_store.dart';
import 'package:campus_bites/widgets/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _offline = SocketException('airplane mode');

class _FakeRepository extends Fake implements FavoritesRepository {
  final calls = <String>[];
  Set<String> serverIds = {};

  /// Thrown by PUT and DELETE; [fetchError] by the list.
  Object? error;
  Object? fetchError;
  var fetches = 0;

  /// While not completed, every request waits (to make calls overlap).
  Completer<void>? gate;

  @override
  Future<Set<String>> fetchFavoriteIds(String userId) async {
    fetches++;
    await gate?.future;
    if (fetchError case final e?) throw e;
    return serverIds;
  }

  @override
  Future<void> addFavorite(String userId, String spotId) => _call('PUT $spotId');

  @override
  Future<void> removeFavorite(String userId, String spotId) => _call('DELETE $spotId');

  Future<void> _call(String call) async {
    calls.add(call);
    await gate?.future;
    if (error case final e?) throw e;
  }
}

class _FakeTelemetry extends Fake implements TelemetryQueue {
  final events = <TelemetryEvent>[];

  @override
  void enqueue(TelemetryEvent event) => events.add(event);
}

class _NoNearby extends Fake implements NearbyFavoritesLoader {}

class _MemoryTokens extends Fake implements TokenStore {
  AuthUser? user;

  _MemoryTokens(this.user);

  @override
  Future<AuthUser?> read() async => user;

  @override
  Future<void> clear() async => user = null;
}

class _AcceptingAuth extends Fake implements AuthRepository {
  @override
  Future<void> verify(String accessToken) async {}
}

void main() {
  late Directory dir;
  late FavoritesLocalStore store;
  late _FakeRepository repo;
  late _FakeTelemetry telemetry;

  FavoritesController controller() => FavoritesController(
        repository: repo,
        telemetry: telemetry,
        currentUserId: () => 'u1',
        local: store,
      );

  bool isSaved(FavoritesController c, String id) => c.spots.firstWhere((s) => s.id == id).isSaved;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('favorites_hive_test');
    Hive.init(dir.path);
    store = await FavoritesLocalStore.open();
    repo = _FakeRepository();
    telemetry = _FakeTelemetry();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('a save without network stays saved, on screen and on the phone', () async {
    repo.error = _offline;
    final c = controller();

    await c.toggleSaved('nitro-coffee'); // no exception: nothing to roll back

    expect(isSaved(c, 'nitro-coffee'), isTrue);
    expect(store.savedIds, {'nitro-coffee'});
    expect(store.card('nitro-coffee'), containsPair('name', 'Nitro Coffee & Brew'));
    expect(store.pending.single.desired, isTrue);
    expect(c.pendingIds, {'nitro-coffee'});
    expect(telemetry.events, isEmpty); // favorite_added waits until the server has it

    // The app restarts offline: the copy on the phone still has it.
    expect(isSaved(controller(), 'nitro-coffee'), isTrue);
  });

  test('save then unsave of the same spot offline collapse into one pending change', () async {
    repo.error = _offline;
    final c = controller();
    await c.toggleSaved('nitro-coffee');
    await c.toggleSaved('nitro-coffee');

    expect(isSaved(c, 'nitro-coffee'), isFalse);
    expect(store.savedIds, isEmpty);
    expect(store.pending.map((p) => (p.spotId, p.desired)), [('nitro-coffee', false)]);

    repo
      ..error = null
      ..calls.clear();
    await c.sendPending();
    expect(repo.calls, ['DELETE nitro-coffee']); // one request: the last state wins
    expect(store.pending, isEmpty);
  });

  test('back online, pending changes are sent and forgotten only after they arrive', () async {
    repo.error = _offline;
    final c = controller();
    await c.toggleSaved('nitro-coffee');
    await c.toggleSaved('green-bowl-co');

    expect(await c.sendPending(), 0); // still offline: both wait
    expect(store.pendingIds, {'nitro-coffee', 'green-bowl-co'});

    repo
      ..error = null
      ..calls.clear()
      ..serverIds = {'nitro-coffee', 'green-bowl-co'};
    expect(await c.sendPending(), 2);
    await c.syncFromServer();

    expect(repo.calls, unorderedEquals(['PUT nitro-coffee', 'PUT green-bowl-co']));
    expect(store.pending, isEmpty);
    expect(c.sync, FavoritesSync.loaded);
    expect(telemetry.events.map((e) => e.toJson()['spotId']),
        unorderedEquals(['nitro-coffee', 'green-bowl-co']));
  });

  test('a 404 on a pending save drops it and turns the heart off', () async {
    final nitro = sampleSpots.firstWhere((s) => s.id == 'nitro-coffee');
    await store.setSaved(nitro, true);
    await store.queue('nitro-coffee', desired: true);
    final c = controller();
    expect(isSaved(c, 'nitro-coffee'), isTrue);

    repo.error = const ApiException(404); // the spot no longer exists
    expect(await c.sendPending(), 0);

    expect(store.pending, isEmpty);
    expect(store.savedIds, isEmpty);
    expect(isSaved(c, 'nitro-coffee'), isFalse);
    expect(telemetry.events, isEmpty);
  });

  test('syncs that overlap (open, reconnect, Retry) send each pending change once', () async {
    await store.queue('nitro-coffee', desired: true);
    await store.queue('green-bowl-co', desired: false);
    repo.gate = Completer();
    final c = controller();

    final runs = [c.syncAll(), c.syncAll(), c.sendPending()];
    repo.gate!.complete();
    await Future.wait(runs);

    expect(repo.calls, unorderedEquals(['PUT nitro-coffee', 'DELETE green-bowl-co']));
    expect(repo.fetches, 1);
    expect(store.pending, isEmpty);
    expect(telemetry.events, hasLength(1));
  });

  test('a save sent twice (the app closed before forgetting it) reuses its eventId', () async {
    final tappedAt = DateTime.utc(2026, 11, 20, 9, 30);
    await store.queue('nitro-coffee', desired: true, now: tappedAt);
    final queued = store.pending.single;
    final saved = Map<dynamic, dynamic>.from(Hive.box<Map>(FavoritesLocalStore.pendingBox).get('nitro-coffee')!);
    final c = controller();

    await c.sendPending();
    // The PUT arrived but the app died before deleting the pending change.
    await Hive.box<Map>(FavoritesLocalStore.pendingBox).put('nitro-coffee', saved);
    await c.sendPending();

    expect(repo.calls, ['PUT nitro-coffee', 'PUT nitro-coffee']); // the backend answers 204 both times
    expect(telemetry.events.map((e) => e.eventId), [queued.eventId, queued.eventId]);
    expect(telemetry.events.first.occurredAt, tappedAt); // when the student tapped, not when it synced
  });

  testWidgets('cold start without network: Saved shows the 2 favorites from Hive', (tester) async {
    await tester.runAsync(() => store.replaceAll([
          sampleSpots.firstWhere((s) => s.id == 'green-bowl-co'),
          sampleSpots.firstWhere((s) => s.id == 'nitro-coffee'),
        ]));
    repo.fetchError = _offline;
    final c = controller(); // a new app process: only the bundled catalog and Hive
    await tester.runAsync(c.syncAll);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SavedPlacesScreen(
          spots: c.spots,
          onToggleSaved: (_) {},
          nearbyLoader: _NoNearby(),
          onRetrySync: () {},
          sync: c.sync,
          offlineSince: c.copySavedAt,
        ),
      ),
    ));

    expect(c.sync, FavoritesSync.offline);
    expect(find.text('Green Bowl Co.'), findsOneWidget);
    expect(find.text('Nitro Coffee & Brew'), findsOneWidget);
    expect(find.textContaining('Offline · saved places from'), findsOneWidget);
  });

  test('a 5xx while sending keeps the change for next time', () async {
    await store.queue('nitro-coffee', desired: true);
    repo.error = const ApiException(502);

    expect(await controller().sendPending(), 0);
    expect(store.pendingIds, {'nitro-coffee'});
  });

  test('a change made while another was being sent is not lost', () async {
    await store.queue('nitro-coffee', desired: true, now: DateTime.utc(2026, 11, 20, 10));
    final sent = store.pending.single;
    await store.queue('nitro-coffee', desired: false, now: DateTime.utc(2026, 11, 20, 10, 1));

    await store.markSent(sent);

    expect(store.pending.single.desired, isFalse);
  });

  test('a 5xx is a server error, not offline: the copy is not shown as current', () async {
    await store.replaceAll([sampleSpots.firstWhere((s) => s.id == 'nitro-coffee')]);
    repo.fetchError = const ApiException(503);
    final c = controller();

    await expectLater(c.syncFromServer(), throwsA(isA<ApiException>()));
    expect(c.sync, FavoritesSync.failed);
    expect(c.isOffline, isFalse);

    // A failed save for a reason other than the network rolls back and isn't queued.
    repo.error = const ApiException(500);
    await expectLater(c.toggleSaved('green-bowl-co'), throwsA(isA<ApiException>()));
    expect(isSaved(c, 'green-bowl-co'), isFalse);
    expect(store.savedIds, {'nitro-coffee'});
    expect(store.pending, isEmpty);
  });

  test('without network Saved starts from the copy on the phone', () async {
    final copiedAt = DateTime(2026, 11, 20, 9, 41);
    await store.replaceAll([sampleSpots.firstWhere((s) => s.id == 'green-bowl-co')], now: copiedAt);
    repo.fetchError = _offline;
    final c = controller();

    expect(isSaved(c, 'green-bowl-co'), isTrue); // before the network answers
    await c.syncFromServer(); // no exception: the screen says it is offline
    expect(c.sync, FavoritesSync.offline);
    expect(c.copySavedAt, copiedAt.toUtc());
    expect(isSaved(c, 'green-bowl-co'), isTrue);
  });

  test('a successful sync replaces the copy, keeping changes not sent yet', () async {
    await store.replaceAll([sampleSpots.firstWhere((s) => s.id == 'green-bowl-co')]);
    await store.queue('nitro-coffee', desired: true);
    repo.serverIds = {'conda-de-bons'};
    final c = controller();

    await c.syncFromServer();

    expect(store.savedIds, {'conda-de-bons', 'nitro-coffee'});
    expect(isSaved(c, 'green-bowl-co'), isFalse);
  });

  test('signing out empties both boxes', () async {
    await store.replaceAll([sampleSpots.first]);
    await store.queue('nitro-coffee', desired: true);
    final session = AuthSession(
      repository: _AcceptingAuth(),
      store: _MemoryTokens(const AuthUser(userId: 'u1', email: 'a@uniandes.edu.co', accessToken: 't')),
      devUserId: '',
    );
    clearFavoritesOnSignOut(session, store);
    await session.restore();
    expect(store.savedIds, isNotEmpty); // signing in keeps them

    await session.signOut();
    for (var i = 0; i < 100 && (store.savedIds.isNotEmpty || store.pendingIds.isNotEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(store.savedIds, isEmpty);
    expect(store.pending, isEmpty);
    expect(store.syncedAt, isNull);
  });

  group('Saved screen', () {
    Widget saved({required FavoritesSync sync, Set<String> savedIds = const {}, DateTime? since}) =>
        MaterialApp(
          home: Scaffold(
            body: SavedPlacesScreen(
              spots: [for (final s in sampleSpots) s.copyWith(isSaved: savedIds.contains(s.id))],
              onToggleSaved: (_) {},
              nearbyLoader: _NoNearby(),
              onRetrySync: () {},
              sync: sync,
              offlineSince: since,
              pendingIds: savedIds.take(1).toSet(),
            ),
          ),
        );

    testWidgets('offline with a copy says from when it is', (tester) async {
      final since = DateTime(2026, 11, 20, 9, 41);
      await tester.pumpWidget(saved(sync: FavoritesSync.offline, savedIds: {'green-bowl-co'}, since: since));

      expect(find.text('Offline · saved places from ${hourMinute(since)}'), findsOneWidget);
      expect(find.text('Green Bowl Co.'), findsOneWidget);
      expect(find.text('Waiting to sync'), findsOneWidget);
    });

    testWidgets('offline without a copy says it will show up later', (tester) async {
      await tester.pumpWidget(saved(sync: FavoritesSync.offline));

      expect(find.text("Offline · your saved places show up when you're back online"), findsOneWidget);
    });

    testWidgets('a server error shows Retry and hides the copy', (tester) async {
      await tester.pumpWidget(saved(sync: FavoritesSync.failed, savedIds: {'green-bowl-co'}));

      expect(find.text("The server couldn't load your saved places right now."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(OfflineBanner), findsNothing);
      expect(find.text('Green Bowl Co.'), findsNothing);
    });
  });
}
