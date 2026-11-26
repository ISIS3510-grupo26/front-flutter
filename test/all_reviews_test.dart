import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_bites/main.dart';
import 'package:campus_bites/models/auth_user.dart';
import 'package:campus_bites/models/review_page.dart';
import 'package:campus_bites/models/telemetry_event.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/repositories/auth_repository.dart';
import 'package:campus_bites/services/all_reviews_loader.dart';
import 'package:campus_bites/services/auth_session.dart';
import 'package:campus_bites/services/helpful_queue.dart';
import 'package:campus_bites/services/review_interactions.dart';
import 'package:campus_bites/services/reviews_local_store.dart';
import 'package:campus_bites/services/reviews_service.dart';
import 'package:campus_bites/services/token_store.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _spot = 'poodle-pizza-slices';
const _offline = SocketException('offline');

Map<String, dynamic> _json(int id, {int stars = 4, String text = 'Good', String author = 'ana', int helpful = 0, String? createdAt}) => {
      'id': id,
      'authorName': author,
      'initials': author.substring(0, 2).toUpperCase(),
      'program': 'Student',
      'stars': stars,
      'text': text,
      'dinedAgo': '2 days ago',
      'helpfulCount': helpful,
      'createdAt': createdAt,
    };

ReviewItem _item(int id, {int stars = 4, String text = 'Good', String author = 'ana', int helpful = 0, String? createdAt}) =>
    ReviewItem.fromJson(_json(id, stars: stars, text: text, author: author, helpful: helpful, createdAt: createdAt));

ReviewPage _page(List<ReviewItem> items, {int page = 1, int total = 0}) =>
    ReviewPage(items: items, page: page, pageSize: 10, total: total == 0 ? items.length : total);

/// Answers from [pages] and [votes], or throws [error]. Records every call.
class _FakeService implements ReviewsService {
  final pageCalls = <ReviewQuery>[];
  final voteCalls = <String>[];
  final helpfulCalls = <(int, bool)>[];
  Object? error;
  Object? helpfulError;
  ReviewPage Function(ReviewQuery query) pages = (q) => _page([_item(1)]);
  Set<int> votes = {};
  Completer<void>? helpfulGate;

  @override
  Future<ReviewPage> page(ReviewQuery query) async {
    pageCalls.add(query);
    if (error case final e?) throw e;
    return pages(query);
  }

  @override
  Future<Set<int>> myHelpfulVotes(String spotId, String userId) async {
    voteCalls.add(userId);
    if (error case final e?) throw e;
    return votes;
  }

  @override
  Future<void> setHelpful(String spotId, int reviewId, String userId, {required bool helpful}) async {
    helpfulCalls.add((reviewId, helpful));
    await helpfulGate?.future;
    if (helpfulError case final e?) throw e;
  }
}

void main() {
  group('parsing and local search', () {
    final body = jsonEncode({
      'items': [_json(7, text: 'Los ÑOQUIS de la casa', author: 'maría')],
      'page': 2,
      'pageSize': 10,
      'total': 25,
    });

    test('a page is decoded inside an isolate, with the text normalized for search', () async {
      final page = await parseReviewPageInIsolate(body);

      expect((page.page, page.total, page.hasMore), (2, 25, true));
      expect(page.items.single.id, 7);
      expect(page.items.single.searchText, 'los noquis de la casa maria');
    });

    test('normalizeForSearch drops case, accents and extra spaces', () {
      expect(normalizeForSearch('  Día   NORMAL, Ñandú '), 'dia normal, nandu');
    });

    test('order, stars and search work on the saved copy like on the server', () {
      final reviews = [
        _item(1, stars: 5, helpful: 1),
        _item(2, stars: 2, text: 'Too salty', helpful: 4, createdAt: '2026-11-01T10:00:00Z'),
        _item(3, stars: 5, text: 'Ñoquis!', helpful: 4, createdAt: '2026-11-02T10:00:00Z'),
      ];
      List<int> ids(ReviewQuery q) => applyLocalQuery(reviews, q).map((r) => r.id).toList();

      // Newest: dated ones first (newest on top), then the catalog ones.
      expect(ids(const ReviewQuery(spotId: _spot)), [3, 2, 1]);
      expect(ids(const ReviewQuery(spotId: _spot, sort: ReviewSort.helpful)), [3, 2, 1]);
      expect(ids(const ReviewQuery(spotId: _spot, sort: ReviewSort.lowest)), [2, 3, 1]);
      expect(ids(const ReviewQuery(spotId: _spot, stars: 5)), [3, 1]);
      expect(ids(const ReviewQuery(spotId: _spot, q: 'NOQUIS')), [3]);
    });
  });

  test('the adapter sends the query and the user, and expects 204 from Helpful', () async {
    final requests = <http.Request>[];
    final adapter = ReviewsServiceAdapter(
      baseUrl: 'http://api',
      parse: (body) async => parseReviewPage(body),
      client: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'GET' when request.url.path.endsWith('/helpful') => http.Response('{"reviewIds":[3,5]}', 200),
          'GET' => http.Response(jsonEncode({'items': [], 'page': 1, 'pageSize': 10, 'total': 0}), 200),
          _ => http.Response('', 204),
        };
      }),
    );

    await adapter.page(const ReviewQuery(spotId: _spot, sort: ReviewSort.helpful, stars: 5, q: ' pizza ', page: 2));
    expect(await adapter.myHelpfulVotes(_spot, 'dev-ana'), {3, 5});
    await adapter.setHelpful(_spot, 3, 'dev-ana', helpful: false);

    expect(requests[0].url.toString(),
        'http://api/spots/$_spot/reviews?sort=helpful&stars=5&q=pizza&page=2&pageSize=10');
    expect(requests[1].url.toString(), 'http://api/spots/$_spot/reviews/helpful?userId=dev-ana');
    expect((requests[2].method, requests[2].url.path), ('DELETE', '/spots/$_spot/reviews/3/helpful'));
  });

  group('AllReviewsLoader', () {
    late Directory dir;
    late ReviewsLocalStore store;
    late _FakeService service;
    var now = DateTime(2026, 11, 20, 12);

    AllReviewsLoader loader({String? userId = 'dev-ana', bool saveOffline = true}) => AllReviewsLoader(
          service: service,
          currentUserId: () => userId,
          local: saveOffline ? store : null,
          cache: AllReviewsLoader.newReviewPageCache(now: () => now),
        );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('reviews_hive_test');
      Hive.init(dir.path);
      store = await ReviewsLocalStore.open();
      service = _FakeService();
      now = DateTime(2026, 11, 20, 12);
    });

    tearDown(() async {
      // The loader saves each page without waiting; let those writes land.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('the page and the user votes are requested at the same time', () async {
      final pageGate = Completer<ReviewPage>();
      final votesGate = Completer<Set<int>>();
      final started = <String>[];
      final parallel = _GatedService(
        page: () {
          started.add('page');
          return pageGate.future;
        },
        votes: () {
          started.add('votes');
          return votesGate.future;
        },
      );
      final result = AllReviewsLoader(service: parallel, currentUserId: () => 'dev-ana')
          .load(const ReviewQuery(spotId: _spot));
      await Future<void>.delayed(Duration.zero);

      expect(started, ['page', 'votes']); // both out before either answered
      votesGate.complete({1});
      pageGate.complete(_page([_item(1)]));
      final loaded = await result as ReviewsLoaded;
      expect(loaded.votes, {1});
    });

    test('without a user it asks only for the page', () async {
      final loaded = await loader(userId: null, saveOffline: false).load(const ReviewQuery(spotId: _spot)) as ReviewsLoaded;

      expect(service.voteCalls, isEmpty);
      expect(loaded.votes, isEmpty);
    });

    test('LRU: a repeated query within 2 minutes is not requested again', () async {
      final l = loader(saveOffline: false);
      const query = ReviewQuery(spotId: _spot, sort: ReviewSort.highest);

      await l.load(query);
      now = now.add(const Duration(minutes: 1, seconds: 59));
      await l.load(query);
      expect(service.pageCalls, hasLength(1));

      now = now.add(const Duration(seconds: 2)); // 2:01 after it was saved
      await l.load(query);
      expect(service.pageCalls, hasLength(2));

      await l.load(query, forceRefresh: true); // Retry skips the cache
      expect(service.pageCalls, hasLength(3));
    });

    test('LRU: the 13th query evicts the least recently used one', () async {
      final l = loader(saveOffline: false);
      final queries = [for (var page = 1; page <= 13; page++) ReviewQuery(spotId: _spot, page: page)];

      for (final q in queries.take(12)) {
        await l.load(q);
      }
      await l.load(queries[0]); // page 1 becomes the most recent
      await l.load(queries[12]); // evicts page 2, the least recently used
      service.pageCalls.clear();

      await l.load(queries[0]);
      expect(service.pageCalls, isEmpty);
      await l.load(queries[1]);
      expect(service.pageCalls.single.page, 2);
    });

    test('offline with a saved copy: every saved review, ordered and filtered on the phone', () async {
      service
        ..pages = ((q) => q.page == 1
            ? _page([_item(1, stars: 5), _item(2, stars: 3)], total: 3)
            : _page([_item(3, stars: 5, text: 'Ñoquis')], page: 2, total: 3))
        ..votes = {2};
      final l = loader();
      await l.load(const ReviewQuery(spotId: _spot));
      await l.load(const ReviewQuery(spotId: _spot, page: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50)); // the fire-and-forget saves

      service.error = _offline;
      final offline = loader(); // a new session: empty memory cache, only Hive
      final all = await offline.load(const ReviewQuery(spotId: _spot)) as ReviewsLoaded;
      final fiveStars = await offline.load(const ReviewQuery(spotId: _spot, stars: 5, q: 'noquis')) as ReviewsLoaded;

      expect(all.items.map((r) => r.id), unorderedEquals([1, 2, 3]));
      expect(all.hasMore, isFalse);
      expect(all.votes, {2});
      expect(all.offlineSavedAt, isNotNull);
      expect(fiveStars.items.map((r) => r.id), [3]);
    });

    test('offline without a saved copy: a network failure', () async {
      service.error = _offline;
      final result = await loader().load(const ReviewQuery(spotId: _spot));

      expect(result, isA<ReviewsFailed>().having((f) => f.reason, 'reason', ReviewsFailure.network));
    });

    test('a 5xx is a server error, even with a saved copy', () async {
      final l = loader();
      await l.load(const ReviewQuery(spotId: _spot));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      service.error = const ApiException(503);
      final result = await l.load(const ReviewQuery(spotId: _spot), forceRefresh: true);

      expect(result, isA<ReviewsFailed>().having((f) => f.reason, 'reason', ReviewsFailure.server));
    });

    test('signing out empties the saved pages and the pending votes', () async {
      final session = AuthSession(
        repository: _AcceptingAuth(),
        store: _MemoryTokens(const AuthUser(userId: 'u1', email: 'a@uniandes.edu.co', accessToken: 't')),
        devUserId: '',
      );
      clearOnSignOut(session, store.clear); // what main() does
      await session.restore();
      await loader().load(const ReviewQuery(spotId: _spot));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await store.queue(_spot, 1, desired: true);
      expect(store.saved(_spot), isNotNull); // signing in keeps them

      await session.signOut();
      for (var i = 0; i < 100 && (store.saved(_spot) != null || store.pending.isNotEmpty); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(store.saved(_spot), isNull);
      expect(store.pending, isEmpty);
    });
  });

  group('HelpfulQueue', () {
    late Directory dir;
    late ReviewsLocalStore store;
    late _FakeService service;
    late StreamController<List<ConnectivityResult>> connectivity;

    HelpfulQueue queue() => HelpfulQueue(
          service: service,
          local: store,
          currentUserId: () => 'dev-ana',
          connectivity: connectivity.stream,
        );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('helpful_hive_test');
      Hive.init(dir.path);
      store = await ReviewsLocalStore.open();
      service = _FakeService();
      connectivity = StreamController.broadcast();
    });

    tearDown(() async {
      await connectivity.close();
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('offline, a vote stays marked and pending, and taps collapse per review', () async {
      service.helpfulError = _offline;
      final q = queue();

      await q.toggle(_spot, 7, {});
      expect((q.isMarked(7, {}), q.isPending(7), q.count(7, 3, {})), (true, true, 4));

      await q.toggle(_spot, 7, {}); // unmarked again, still offline
      await q.toggle(_spot, 7, {});
      expect(store.pending.map((p) => (p.reviewId, p.desired)), [(7, true)]);
    });

    test('pending wins over what the server said', () async {
      await store.queue(_spot, 7, desired: false);

      expect(queue().isMarked(7, {7}), isFalse);
      expect(queue().count(7, 5, {7}), 4);
    });

    test('coming back online sends what is pending, once', () async {
      service.helpfulError = _offline;
      final q = queue();
      await q.toggle(_spot, 7, {});
      await q.toggle(_spot, 8, {8}); // unmark
      service
        ..helpfulCalls.clear()
        ..helpfulError = null;

      connectivity.add([ConnectivityResult.wifi]);
      connectivity.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.helpfulCalls, unorderedEquals([(7, true), (8, false)]));
      expect(store.pending, isEmpty);
      expect((q.isMarked(7, {}), q.isMarked(8, {8})), (true, false)); // what was sent this session
    });

    test('one send at a time: flushes while sending join the same run', () async {
      final q = queue();
      await store.queue(_spot, 7, desired: true);
      service.helpfulGate = Completer();

      final runs = [q.flush(), q.flush(), q.flush()];
      await Future<void>.delayed(Duration.zero);
      expect(service.helpfulCalls, [(7, true)]);
      expect(identical(runs[0], runs[2]), isTrue);

      service.helpfulGate!.complete();
      await Future.wait(runs);
      expect(service.helpfulCalls, [(7, true)]);
    });

    test('a 4xx drops the vote and a 5xx keeps it for later', () async {
      await store.queue(_spot, 7, desired: true);
      service.helpfulError = const ApiException(503);
      await queue().flush();
      expect(store.pending, hasLength(1));

      service.helpfulError = const ApiException(404);
      await queue().flush();
      expect(store.pending, isEmpty);
    });
  });

  group('BQ8 review_interaction', () {
    test('the eventId is rvi-<visit>-<action>', () {
      final event = TelemetryEvent.reviewInteraction(
        spotId: _spot,
        visitEventId: '0123456789abcdef0123456789abcdef',
        action: ReviewAction.openAll,
        userId: 'dev-ana',
      );

      expect(event.eventId, 'rvi-0123456789abcdef0123456789abcdef-open_all');
      expect(event.toJson(), containsPair('screen', 'review_interaction'));
      expect(event.spotId, _spot);
      expect(
        RegExp(r'^rvi-[A-Za-z0-9-]{8,51}-(open_all|sort|filter|search|helpful)$').hasMatch(event.eventId),
        isTrue,
      );
    });

    test('each action is sent the first time it happens in the visit', () {
      final sent = <TelemetryEvent>[];
      final tracker = ReviewInteractionTracker(
        spotId: _spot,
        visitEventId: TelemetryEvent.newId(),
        currentUserId: () => null,
        send: sent.add,
      );

      for (final action in [ReviewAction.openAll, ReviewAction.sort, ReviewAction.sort, ReviewAction.openAll]) {
        tracker.record(action);
      }

      expect(sent.map((e) => e.eventId.split('-').last), ['open_all', 'sort']);
    });
  });
}

class _GatedService implements ReviewsService {
  final Future<ReviewPage> Function() _page;
  final Future<Set<int>> Function() _votes;

  _GatedService({required this._page, required this._votes});

  @override
  Future<ReviewPage> page(ReviewQuery query) => _page();

  @override
  Future<Set<int>> myHelpfulVotes(String spotId, String userId) => _votes();

  @override
  Future<void> setHelpful(String spotId, int reviewId, String userId, {required bool helpful}) async {}
}

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
