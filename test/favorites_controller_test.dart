import 'dart:async';

import 'package:campus_bites/data/spots_data.dart';
import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/favorites_repository.dart';
import 'package:campus_bites/services/favorites_controller.dart';
import 'package:campus_bites/services/telemetry_queue.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository extends Fake implements FavoritesRepository {
  final calls = <String>[];
  Set<String> serverIds = {};
  Object? error;
  Completer<void>? gate;

  @override
  Future<Set<String>> fetchFavoriteIds(String userId) async => serverIds;

  @override
  Future<void> addFavorite(String userId, String spotId) =>
      _call('PUT $userId $spotId');

  @override
  Future<void> removeFavorite(String userId, String spotId) =>
      _call('DELETE $userId $spotId');

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

void main() {
  late _FakeRepository repo;
  late _FakeTelemetry telemetry;

  FavoritesController controller({String? userId = 'u1'}) => FavoritesController(
        repository: repo,
        telemetry: telemetry,
        currentUserId: () => userId,
      );

  bool isSaved(FavoritesController c, String id) =>
      c.spots.firstWhere((s) => s.id == id).isSaved;

  setUp(() {
    repo = _FakeRepository();
    telemetry = _FakeTelemetry();
  });

  test('saving calls PUT and then queues favorite_added', () async {
    final c = controller();
    await c.toggleSaved('poodle-pizza-slices');

    expect(isSaved(c, 'poodle-pizza-slices'), isTrue);
    expect(repo.calls, ['PUT u1 poodle-pizza-slices']);
    expect(telemetry.events.single.toJson(), containsPair('screen', 'favorite_added'));
    expect(telemetry.events.single.toJson(), containsPair('userId', 'u1'));
    expect(telemetry.events.single.toJson(),
        containsPair('spotId', 'poodle-pizza-slices'));
  });

  test('unsaving calls DELETE and sends no telemetry', () async {
    final c = controller();
    await c.toggleSaved('conda-de-bons');

    expect(isSaved(c, 'conda-de-bons'), isFalse);
    expect(repo.calls, ['DELETE u1 conda-de-bons']);
    expect(telemetry.events, isEmpty);
  });

  test('a failed save rolls back and sends no telemetry', () async {
    repo.error = const ApiException(404);
    final c = controller();

    await expectLater(c.toggleSaved('poodle-pizza-slices'),
        throwsA(isA<ApiException>()));
    expect(isSaved(c, 'poodle-pizza-slices'), isFalse);
    expect(telemetry.events, isEmpty);
  });

  test('without a user, saving stays local', () async {
    final c = controller(userId: null);
    await c.toggleSaved('poodle-pizza-slices');

    expect(isSaved(c, 'poodle-pizza-slices'), isTrue);
    expect(repo.calls, isEmpty);
    expect(telemetry.events, isEmpty);
  });

  test('taps while a change is in flight are ignored', () async {
    repo.gate = Completer();
    final c = controller();
    final first = c.toggleSaved('poodle-pizza-slices');
    await c.toggleSaved('poodle-pizza-slices');
    repo.gate!.complete();
    await first;

    expect(repo.calls, ['PUT u1 poodle-pizza-slices']);
    expect(isSaved(c, 'poodle-pizza-slices'), isTrue);
  });

  test('sync replaces local saved state with the server', () async {
    repo.serverIds = {'poodle-pizza-slices'};
    final c = controller();
    await c.syncFromServer();

    final saved = c.spots.where((s) => s.isSaved).map((s) => s.id);
    expect(saved, ['poodle-pizza-slices']);
    expect(c.spots.length, sampleSpots.length);
  });
}
