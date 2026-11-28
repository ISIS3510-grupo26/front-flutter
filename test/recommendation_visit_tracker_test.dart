import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/services/recommendation_visit_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _MemoryCandidates implements VisitCandidateStorage {
  final items = <VisitCandidate>[];

  @override
  Future<void> add(VisitCandidate c) async => items
    ..removeWhere((e) => e.eventId == c.eventId)
    ..add(c);

  @override
  Future<List<VisitCandidate>> all() async => List.of(items);

  @override
  Future<void> remove(Iterable<String> eventIds) async {
    final ids = eventIds.toSet();
    items.removeWhere((e) => ids.contains(e.eventId));
  }

  @override
  Future<void> removeOpenedBefore(DateTime time) async => items.removeWhere((e) => e.openedAt.isBefore(time));
}

// Conda de Bons and Green Bowl Co. as in the catalog, about 210 m apart.
const conda = LatLng(4.6031, -74.0662);
const greenBowl = LatLng(4.6014, -74.0651);
const library = LatLng(4.6018, -74.0661); // campus center, about 145 m from Conda de Bons

void main() {
  late _MemoryCandidates storage;
  late List<TelemetryEvent> sent;
  late LatLng? here;
  late int positionReads;
  late DateTime now;

  RecommendationVisitTracker tracker({String? userId = 'ana', void Function(List<String>)? onVisited}) =>
      RecommendationVisitTracker(
        send: sent.add,
        currentUserId: () => userId,
        storage: storage,
        position: () async {
          positionReads++;
          return here;
        },
        now: () => now,
        onVisited: onVisited,
      );

  setUp(() {
    storage = _MemoryCandidates();
    sent = [];
    here = library;
    positionReads = 0;
    now = DateTime.utc(2026, 11, 20, 12);
  });

  test('opening a recommendation sends recommendation_open and saves a candidate', () async {
    await tracker().recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);

    expect(sent.single.screen, 'recommendation_open');
    expect(sent.single.spotId, 'conda-de-bons');
    expect(sent.single.userId, 'ana');
    expect(storage.items.single.eventId, sent.single.eventId);
  });

  test('arriving within 100 m sends one visit with an id derived from the open', () async {
    final t = tracker();
    await t.recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);
    final openId = sent.single.eventId;

    now = now.add(const Duration(minutes: 20));
    here = const LatLng(4.6033, -74.0663); // about 25 m away
    expect(await t.checkForVisits(), ['conda-de-bons']);

    final visit = sent.last;
    expect(visit.screen, 'recommendation_visit');
    expect(visit.eventId, 'visit-$openId');
    expect(visit.userId, 'ana');
    expect(storage.items, isEmpty);
    expect(await t.checkForVisits(), isEmpty); // already counted
    expect(sent.where((e) => e.screen == 'recommendation_visit'), hasLength(1));
  });

  test('far away or after 4 hours is not a visit, and old candidates are dropped', () async {
    final t = tracker();
    await t.recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);
    expect(await t.checkForVisits(), isEmpty); // still at the library
    expect(storage.items, hasLength(1));

    now = now.add(const Duration(hours: 4, minutes: 1));
    here = conda;
    expect(await t.checkForVisits(), isEmpty);
    expect(storage.items, isEmpty);
    expect(sent.where((e) => e.screen == 'recommendation_visit'), isEmpty);
  });

  test('being at the place when opening it is not a visit because of the app', () async {
    here = conda;
    final t = tracker();
    await t.recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);
    expect(sent.single.screen, 'recommendation_open'); // the open still counts for BQ9
    expect(storage.items, isEmpty);
    expect(await t.checkForVisits(), isEmpty);
  });

  test('the same place opened twice is one visit; another place stays pending', () async {
    final visited = <List<String>>[];
    final t = tracker(onVisited: visited.add);
    await t.recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);
    await t.recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);
    await t.recordOpen(spotId: 'green-bowl-co', latitude: greenBowl.latitude, longitude: greenBowl.longitude);

    here = conda;
    expect(await t.checkForVisits(), ['conda-de-bons']);
    expect(sent.where((e) => e.screen == 'recommendation_visit'), hasLength(1));
    expect(storage.items.single.spotId, 'green-bowl-co');
    expect(visited, [
      ['conda-de-bons'],
    ]);
  });

  test('checks that start together share one GPS read and one visit', () async {
    final t = tracker();
    await t.recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);
    here = conda;
    positionReads = 0;

    final results = await Future.wait([t.checkForVisits(), t.checkForVisits(), t.checkForVisits()]);
    expect(results, everyElement(['conda-de-bons']));
    expect(positionReads, 1);
    expect(sent.where((e) => e.screen == 'recommendation_visit'), hasLength(1));
  });

  test('without candidates or without location the GPS is not used and nothing is sent', () async {
    final t = tracker();
    expect(await t.checkForVisits(), isEmpty);
    expect(positionReads, 0);

    await t.recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);
    here = null; // permission not granted: the app never asks for it here
    expect(await t.checkForVisits(), isEmpty);
    expect(storage.items, hasLength(1));
  });

  test('a GPS error is not a visit and does not break the check', () async {
    final t = RecommendationVisitTracker(
      send: sent.add,
      currentUserId: () => 'ana',
      storage: storage,
      position: () async => throw StateError('plugin error'),
      now: () => now,
    );
    await t.recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);
    expect(await t.checkForVisits(), isEmpty);
    expect(storage.items, hasLength(1));
  });

  test('visit events keep the user of the open, even if the session changed', () async {
    var user = 'ana';
    final t = RecommendationVisitTracker(
      send: sent.add,
      currentUserId: () => user,
      storage: storage,
      position: () async => here,
      now: () => now,
    );
    await t.recordOpen(spotId: 'conda-de-bons', latitude: conda.latitude, longitude: conda.longitude);
    user = 'beto';
    here = conda;
    await t.checkForVisits();
    expect(sent.last.userId, 'ana');
  });
}
