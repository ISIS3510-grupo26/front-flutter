import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/review_page.dart';
import '../repositories/api_exception.dart';

/// What "All reviews" needs from the backend, without knowing it is HTTP.
abstract class ReviewsService {
  /// One page of the reviews of [query]'s restaurant.
  Future<ReviewPage> page(ReviewQuery query);

  /// Ids of the reviews of [spotId] that [userId] marked as Helpful.
  Future<Set<int>> myHelpfulVotes(String spotId, String userId);

  /// Marks ([helpful] true) or unmarks the review. Repeating it changes
  /// nothing on the server, so a queued vote can be sent twice.
  Future<void> setHelpful(String spotId, int reviewId, String userId, {required bool helpful});
}

/// Multithreading strategy: Isolate. A page is decoded and every review's
/// text normalized for the offline search off the UI thread, so typing in
/// the search box never stutters while a page arrives.
Future<ReviewPage> parseReviewPageInIsolate(String body) => Isolate.run(() => parseReviewPage(body));

/// Service Adapter: adapts `GET /spots/{id}/reviews`,
/// `GET /spots/{id}/reviews/helpful` and `PUT/DELETE
/// /spots/{id}/reviews/{reviewId}/helpful` to [ReviewsService]. It turns the
/// query into parameters and the JSON into model objects.
///
/// The user goes as `?userId=`: with a token the backend checks it matches,
/// and with the dev user it is the only way to say who votes.
///
/// Failures: network errors are thrown as they come (TimeoutException,
/// SocketException, ClientException); an unexpected status is an
/// [ApiException].
class ReviewsServiceAdapter implements ReviewsService {
  static const pageSize = 10;

  final http.Client _client;
  final String _baseUrl;
  final Future<ReviewPage> Function(String body) _parse;

  /// [parse] is the isolate in the app; tests can pass [parseReviewPage].
  ReviewsServiceAdapter({
    required this._client,
    this._baseUrl = ApiConfig.baseUrl,
    this._parse = parseReviewPageInIsolate,
  });

  Uri _reviews(String spotId, [String path = '']) =>
      Uri.parse('$_baseUrl/spots/${Uri.encodeComponent(spotId)}/reviews$path');

  @override
  Future<ReviewPage> page(ReviewQuery query) async {
    final uri = _reviews(query.spotId).replace(queryParameters: {
      'sort': query.sort.wire,
      if (query.stars != null) 'stars': '${query.stars}',
      if (query.q.trim().isNotEmpty) 'q': query.q.trim(),
      'page': '${query.page}',
      'pageSize': '$pageSize',
    });
    final response = await _client.get(uri).timeout(apiTimeout);
    expectStatus(response, 200);
    return _parse(utf8.decode(response.bodyBytes));
  }

  @override
  Future<Set<int>> myHelpfulVotes(String spotId, String userId) async {
    final uri = _reviews(spotId, '/helpful').replace(queryParameters: {'userId': userId});
    final response = await _client.get(uri).timeout(apiTimeout);
    expectStatus(response, 200);
    final json = decodeJson(response) as Map<String, dynamic>;
    return {for (final id in json['reviewIds'] as List<dynamic>) id as int};
  }

  @override
  Future<void> setHelpful(String spotId, int reviewId, String userId, {required bool helpful}) async {
    final uri = _reviews(spotId, '/$reviewId/helpful').replace(queryParameters: {'userId': userId});
    final response = await (helpful ? _client.put(uri) : _client.delete(uri)).timeout(apiTimeout);
    expectStatus(response, 204);
  }
}
