import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_bites/data/spots_data.dart';
import 'package:campus_bites/models/best_for_you.dart';
import 'package:campus_bites/models/user_preferences.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/screens/for_you_screen.dart';
import 'package:campus_bites/services/best_for_you_loader.dart';
import 'package:campus_bites/services/best_for_you_service.dart';
import 'package:campus_bites/services/local_database.dart';
import 'package:campus_bites/services/popularity_loader.dart';
import 'package:campus_bites/widgets/best_for_you_section.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// What the backend answers, trimmed to two spots.
const _backendJson = {
  'question': 'Which restaurants have the shortest waiting time and the best match with my taste profile?',
  'freshMinutes': 120,
  'maxWaitMinutes': 40,
  'personalized': true,
  'spots': [
    {
      'rank': 1,
      'spotId': 'nitro-coffee',
      'name': 'Nitro Coffee & Brew',
      'emoji': '☕',
      'cuisine': 'Café & Bakery',
      'rating': 5.0,
      'isBudget': true,
      'isVegetarian': true,
      'isHighProtein': false,
      'waitMinutes': 8,
      'minutesAgo': 12,
      'isRecent': true,
      'recentReports': 2,
      'waitScore': 80,
      'tasteMatch': 85,
      'score': 82.5,
    },
    {
      'rank': 2,
      'spotId': 'conda-de-bons',
      'name': 'Conda de Bons',
      'emoji': '🍔',
      'cuisine': 'Burgers & Fries',
      'rating': 4.9,
      'isBudget': false,
      'isVegetarian': false,
      'isHighProtein': true,
      'waitMinutes': 25,
      'minutesAgo': 200,
      'isRecent': false,
      'recentReports': 0,
      'waitScore': 50,
      'tasteMatch': null,
      'score': 50.0,
    },
  ],
};

final _ranking = BestForYouRanking.fromJson(_backendJson);

class _FakeService implements BestForYouService {
  final calls = <BestForYouProfile>[];
  Object? error;

  @override
  Future<BestForYouRanking> ranking(BestForYouProfile profile) async {
    calls.add(profile);
    if (error case final e?) throw e;
    return _ranking;
  }
}

class _MemoryStorage implements BestForYouStorage {
  ({BestForYouRanking ranking, DateTime savedAt})? saved;
  bool failWrites = false;

  @override
  Future<void> save(BestForYouRanking ranking, {required DateTime savedAt}) async {
    if (failWrites) throw const FileSystemException('disk full');
    saved = (ranking: ranking, savedAt: savedAt);
  }

  @override
  Future<({BestForYouRanking ranking, DateTime savedAt})?> read() async => saved;
}

class _FakePopular extends Fake implements PopularityLoader {
  @override
  Future<PopularityState> load({bool forceRefresh = false}) async => const PopularityEmpty(12);
}

void main() {
  group('model', () {
    test('reads the backend ranking', () {
      expect(_ranking.personalized, isTrue);
      final nitro = _ranking.spots.first;
      expect(nitro.spotId, 'nitro-coffee');
      expect(nitro.waitMinutes, 8);
      expect(nitro.minutesAgo, 12);
      expect(nitro.isRecent, isTrue);
      expect(nitro.tasteMatch, 85);
      expect(_ranking.spots.last.tasteMatch, isNull);
    });

    test('translates the Taste Profile into what the backend scores', () {
      final profile = BestForYouProfile.from(const UserPreferences(
        mainCuisine: 'Fast food',
        diet: 'Vegan',
        interests: ['Good value', 'Something new'],
      ));

      expect(profile.queryParameters, {
        'cuisines': 'Artisan Burgers',
        'dietary': 'Vegan',
        'budget': 'Budget-friendly',
      });
    });

    test('sends only what the student filled in', () {
      final profile = BestForYouProfile.from(const UserPreferences(mainCuisine: 'Mexican'));

      expect(profile.queryParameters, {'cuisines': 'Mexican'});
      expect(BestForYouProfile.from(null).queryParameters, isEmpty);
      expect(BestForYouProfile.from(const UserPreferences()), BestForYouProfile.none);
    });
  });

  group('service adapter', () {
    test('asks for the top five with the profile and reads the answer', () async {
      late Uri asked;
      final service = BestForYouServiceAdapter(
        baseUrl: 'http://api.test/api/v1',
        client: MockClient((request) async {
          asked = request.url;
          return http.Response.bytes(utf8.encode(jsonEncode(_backendJson)), 200);
        }),
      );

      final ranking = await service.ranking(
        const BestForYouProfile(cuisine: 'Asian', diet: 'Vegetarian'),
      );

      expect(asked.path, '/api/v1/recommendations/best-for-you');
      expect(asked.queryParameters, {
        'freshMinutes': '120',
        'limit': '5',
        'cuisines': 'Asian Wok',
        'dietary': 'Vegetarian',
      });
      expect(ranking.spots.first.name, 'Nitro Coffee & Brew');
    });

    test('any status other than 200 is an ApiException', () async {
      final service = BestForYouServiceAdapter(
        baseUrl: 'http://api.test/api/v1',
        client: MockClient((_) async => http.Response('{}', 500)),
      );

      await expectLater(
        service.ranking(BestForYouProfile.none),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 500)),
      );
    });
  });

  group('loader', () {
    late _FakeService service;
    late _MemoryStorage storage;
    late DateTime now;
    late BestForYouLoader loader;
    const vegan = BestForYouProfile(diet: 'Vegan');

    setUp(() {
      service = _FakeService();
      storage = _MemoryStorage();
      now = DateTime(2026, 10, 30, 12);
      loader = BestForYouLoader(service: service, storage: storage, now: () => now);
    });

    test('a fresh ranking is shown and saved for offline use', () async {
      final state = await loader.load(vegan);

      expect(state, isA<BestForYouLoaded>().having((s) => s.offlineSavedAt, 'offline', isNull));
      await pumpEventQueue();
      expect(storage.saved?.savedAt, now);
    });

    test('the same profile within two minutes comes from the LRU cache', () async {
      await loader.load(vegan);
      now = now.add(const Duration(minutes: 1));
      await loader.load(vegan);
      expect(service.calls, hasLength(1));

      now = now.add(const Duration(minutes: 2));
      await loader.load(vegan);
      expect(service.calls, hasLength(2));
    });

    test('each profile has its own cache entry, and refresh skips it', () async {
      await loader.load(vegan);
      await loader.load(BestForYouProfile.none);
      await loader.load(vegan);
      expect(service.calls, [vegan, BestForYouProfile.none]);

      await loader.load(vegan, forceRefresh: true);
      expect(service.calls, hasLength(3));
    });

    test('without network, the saved ranking with when it was saved', () async {
      final savedAt = DateTime(2026, 10, 30, 9, 15);
      storage.saved = (ranking: _ranking, savedAt: savedAt);
      service.error = const SocketException('no network');

      final state = await loader.load(vegan);

      expect(state, isA<BestForYouLoaded>().having((s) => s.offlineSavedAt, 'offline', savedAt));
    });

    test('without network and nothing saved, a network failure', () async {
      service.error = TimeoutException('slow');

      final state = await loader.load(vegan);

      expect(state, isA<BestForYouFailed>().having((s) => s.reason, 'reason', BestForYouFailure.network));
    });

    test('a server error never falls back to the saved ranking', () async {
      storage.saved = (ranking: _ranking, savedAt: now);
      service.error = const ApiException(500);

      final state = await loader.load(vegan);

      expect(state, isA<BestForYouFailed>().having((s) => s.reason, 'reason', BestForYouFailure.server));
    });

    test('a failed save never breaks the section', () async {
      storage.failWrites = true;

      final state = await loader.load(vegan);
      await pumpEventQueue();

      expect(state, isA<BestForYouLoaded>());
      expect(storage.saved, isNull);
    });
  });

  group('section', () {
    Future<void> pump(WidgetTester tester, BestForYouState state, {VoidCallback? onRetry, ValueChanged<String>? onOpen}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: BestForYouSection(state: state, onRetry: onRetry ?? () {}, onOpenSpot: onOpen),
          ),
        ));

    testWidgets('shows the wait, how recent it is and the match', (tester) async {
      final opened = <String>[];
      await pump(tester, BestForYouLoaded(_ranking), onOpen: opened.add);

      expect(find.text('Short waits that match your taste'), findsOneWidget);
      expect(find.text('⏱ 8 min wait'), findsOneWidget);
      expect(find.text('reported 12 min ago'), findsOneWidget);
      // Nitro matches 85; Conda was ranked without a profile match.
      expect(find.text('Matches your taste'), findsOneWidget);
      // Conda's wait is older than two hours, so it doesn't count.
      expect(find.text('⏱ No recent wait report'), findsOneWidget);

      await tester.tap(find.text('Nitro Coffee & Brew'));
      expect(opened, ['nitro-coffee']);
    });

    testWidgets('offline: the saved ranking with its time, without report ages', (tester) async {
      await pump(tester, BestForYouLoaded(_ranking, offlineSavedAt: DateTime(2026, 10, 30, 9, 5)));

      expect(find.text('Offline · data from 09:05'), findsOneWidget);
      expect(find.text('⏱ 8 min wait'), findsOneWidget);
      expect(find.text('reported 12 min ago'), findsNothing);
    });

    testWidgets('each failure has its own message and Retry', (tester) async {
      var retries = 0;
      await pump(tester, const BestForYouFailed(BestForYouFailure.network), onRetry: () => retries++);
      expect(find.text("Offline · your best picks show up when you're back online"), findsOneWidget);

      await pump(tester, const BestForYouFailed(BestForYouFailure.server), onRetry: () => retries++);
      expect(find.text("Couldn't load your best picks right now."), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });
  });

  group('For You', () {
    late _FakeService service;
    late StreamController<List<ConnectivityResult>> connectivity;

    setUp(() {
      service = _FakeService();
      connectivity = StreamController<List<ConnectivityResult>>();
    });

    tearDown(() => connectivity.close());

    Widget forYou(BestForYouProfile profile) => MaterialApp(
          home: Scaffold(
            body: ForYouScreen(
              spots: sampleSpots,
              onToggleSaved: (_) {},
              popularLoader: _FakePopular(),
              bestForYouLoader: BestForYouLoader(service: service, storage: _MemoryStorage()),
              bestForYouProfile: profile,
              connectivity: connectivity.stream,
            ),
          ),
        );

    testWidgets('saving a new taste profile asks for its ranking', (tester) async {
      await tester.pumpWidget(forYou(BestForYouProfile.none));
      await tester.pumpAndSettle();
      expect(find.text('⚡ Best for you right now'), findsOneWidget);

      const vegan = BestForYouProfile(diet: 'Vegan');
      await tester.pumpWidget(forYou(vegan));
      await tester.pumpAndSettle();

      expect(service.calls, [BestForYouProfile.none, vegan]);
    });

    testWidgets('the connection coming back reloads the section by itself', (tester) async {
      service.error = const SocketException('no network');
      await tester.pumpWidget(forYou(BestForYouProfile.none));
      await tester.pumpAndSettle();
      expect(find.text("Offline · your best picks show up when you're back online"), findsOneWidget);

      connectivity.add([ConnectivityResult.none]);
      service.error = null;
      connectivity.add([ConnectivityResult.wifi]);
      await tester.pumpAndSettle();

      expect(find.text('⏱ 8 min wait'), findsOneWidget);
      expect(service.calls, hasLength(2));
    });
  });
}
