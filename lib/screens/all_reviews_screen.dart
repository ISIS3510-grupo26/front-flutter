import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/review_page.dart';
import '../models/telemetry_event.dart';
import '../services/all_reviews_loader.dart';
import '../services/helpful_queue.dart';
import '../services/review_interactions.dart';
import '../theme/app_colors.dart';
import '../widgets/filter_chip_pill.dart';
import '../widgets/offline_banner.dart';

/// "All reviews" of a restaurant, opened from "Student Reviews (N)" on its
/// page: order, stars and search on top, the reviews below, more pages as the
/// student reaches the end, and Helpful on each one.
class AllReviewsScreen extends StatefulWidget {
  static const searchDebounce = Duration(milliseconds: 300);

  final String spotId;
  final String spotName;
  final AllReviewsLoader loader;

  /// The user's Helpful votes. Null (no account) hides the button's action.
  final HelpfulQueue? helpful;

  /// BQ8 actions of the visit to the restaurant page; null sends nothing.
  final ReviewInteractionTracker? interactions;

  /// `Connectivity().onConnectivityChanged`: showing the saved copy (or the
  /// offline message), the screen reloads when the connection comes back.
  final Stream<List<ConnectivityResult>>? connectivity;

  const AllReviewsScreen({
    super.key,
    required this.spotId,
    required this.spotName,
    required this.loader,
    this.helpful,
    this.interactions,
    this.connectivity,
  });

  @override
  State<AllReviewsScreen> createState() => _AllReviewsScreenState();
}

class _AllReviewsScreenState extends State<AllReviewsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  ReviewSort _sort = ReviewSort.newest;
  int? _stars;
  String _q = '';

  bool _loading = true;
  ReviewsFailure? _failure;
  List<ReviewItem> _items = const [];
  int _total = 0;
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _moreFailed = false;
  Set<int> _votes = const {};
  DateTime? _offlineSavedAt;

  /// Bumped by every new query: an answer to an older one is ignored.
  int _generation = 0;

  ReviewQuery get _query => ReviewQuery(spotId: widget.spotId, sort: _sort, stars: _stars, q: _q);

  bool get _showingOffline => _offlineSavedAt != null || _failure == ReviewsFailure.network;

  @override
  void initState() {
    super.initState();
    widget.helpful?.addListener(_onVotesChanged);
    _connectivity = widget.connectivity?.listen(_onConnectivityChanged);
    widget.interactions?.record(ReviewAction.openAll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _connectivity?.cancel();
    widget.helpful?.removeListener(_onVotesChanged);
    _search.dispose();
    super.dispose();
  }

  void _onVotesChanged() {
    if (mounted) setState(() {});
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online && _showingOffline) _load(forceRefresh: true);
  }

  /// Page 1 of the current query. While the screen shows the saved copy, a
  /// new order, stars or search is applied to it on the phone right away
  /// instead of waiting for a request that would fail again.
  Future<void> _load({bool forceRefresh = false}) async {
    final generation = ++_generation;
    final query = _query;
    if (!forceRefresh && _offlineSavedAt != null) return _show(widget.loader.offline(query), generation);
    setState(() {
      _loading = true;
      _moreFailed = false;
    });
    _show(await widget.loader.load(query, forceRefresh: forceRefresh), generation);
  }

  void _show(ReviewsResult result, int generation) {
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      _page = 1;
      switch (result) {
        case ReviewsFailed(:final reason):
          _failure = reason;
          _items = const [];
          _offlineSavedAt = null;
          _hasMore = false;
        case ReviewsLoaded():
          _failure = null;
          _items = result.items;
          _total = result.total;
          _hasMore = result.hasMore;
          _votes = result.votes;
          _offlineSavedAt = result.offlineSavedAt;
      }
    });
  }

  /// The next page, when the student reaches the end of the list.
  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    final result = await widget.loader.load(_query.withPage(_page + 1));
    if (!mounted || generation != _generation) return;
    setState(() {
      _loadingMore = false;
      switch (result) {
        // The connection dropped: the saved copy replaces the list.
        case ReviewsLoaded(offlineSavedAt: final savedAt?):
          _items = result.items;
          _total = result.total;
          _hasMore = false;
          _votes = result.votes;
          _offlineSavedAt = savedAt;
        case ReviewsLoaded():
          final known = {for (final item in _items) item.id};
          _items = [..._items, ...result.items.where((item) => !known.contains(item.id))];
          _page++;
          _total = result.total;
          _hasMore = result.hasMore;
          _votes = {..._votes, ...result.votes};
        case ReviewsFailed():
          _moreFailed = true;
      }
    });
  }

  void _setSort(ReviewSort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    widget.interactions?.record(ReviewAction.sort);
    _load();
  }

  void _setStars(int? stars) {
    if (stars == _stars) return;
    setState(() => _stars = stars);
    widget.interactions?.record(ReviewAction.filter);
    _load();
  }

  /// Waits [AllReviewsScreen.searchDebounce] after the last key, so typing a
  /// word sends one request, not one per letter.
  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(AllReviewsScreen.searchDebounce, () {
      final q = text.trim();
      if (q == _q) return;
      _q = q;
      if (q.isNotEmpty) widget.interactions?.record(ReviewAction.search);
      _load();
    });
  }

  void _toggleHelpful(ReviewItem review) {
    widget.interactions?.record(ReviewAction.helpful);
    widget.helpful?.toggle(widget.spotId, review.id, _votes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.espresso,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('All reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(widget.spotName, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search reviews',
                prefixIcon: const Icon(Icons.search, color: AppColors.muted),
                filled: true,
                fillColor: AppColors.card,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          _ChipRow(children: [
            for (final sort in ReviewSort.values)
              FilterChipPill(label: sort.label, active: sort == _sort, onTap: () => _setSort(sort)),
          ]),
          const SizedBox(height: 8),
          _ChipRow(children: [
            FilterChipPill(label: 'All stars', active: _stars == null, onTap: () => _setStars(null)),
            for (var stars = 5; stars >= 1; stars--)
              FilterChipPill(label: '$stars ★', active: _stars == stars, onTap: () => _setStars(stars)),
          ]),
          if (_offlineSavedAt case final savedAt?)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OfflineBanner(message: 'Offline · reviews from ${hourMinute(savedAt)}'),
              ),
            ),
          if (!_loading && _failure == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Text(
                '$_total ${_total == 1 ? 'review' : 'reviews'}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.tomato));
    }
    if (_failure case final failure?) {
      return _Message(
        icon: failure == ReviewsFailure.network ? Icons.cloud_off : Icons.error_outline,
        text: failure == ReviewsFailure.network
            ? "You're offline and this place has no reviews saved on your phone yet. "
                'They show up here once you open them with a connection.'
            : "CampusBites couldn't load the reviews right now.",
        onRetry: () => _load(forceRefresh: true),
      );
    }
    if (_items.isEmpty) {
      return _Message(
        icon: Icons.rate_review_outlined,
        text: _q.isEmpty && _stars == null ? 'No reviews yet.' : 'No reviews match.',
      );
    }
    final footer = _hasMore || _moreFailed;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: _items.length + (footer ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          if (_moreFailed) {
            return Center(
              child: TextButton(
                onPressed: _loadMore,
                style: TextButton.styleFrom(foregroundColor: AppColors.tomato),
                child: const Text("Couldn't load more · Retry"),
              ),
            );
          }
          // Pagination: the footer is built only when the student scrolls to
          // the end, so that is when the next page is asked for.
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: AppColors.tomato, strokeWidth: 2)),
          );
        }
        final review = _items[index];
        final helpful = widget.helpful;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ReviewTile(
            review: review,
            marked: helpful?.isMarked(review.id, _votes) ?? false,
            count: helpful?.count(review.id, review.helpfulCount, _votes) ?? review.helpfulCount,
            pending: helpful?.isPending(review.id) ?? false,
            onHelpful: helpful == null ? null : () => _toggleHelpful(review),
          ),
        );
      },
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<Widget> children;

  const _ChipRow({required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              child,
            ],
          ],
        ),
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  const _Message({required this.icon, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.muted, size: 32),
              const SizedBox(height: 10),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(foregroundColor: AppColors.tomato),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
}

/// One review with its Helpful button and count.
class ReviewTile extends StatelessWidget {
  final ReviewItem review;
  final bool marked;
  final int count;

  /// Marked offline: it is sent when the connection comes back.
  final bool pending;
  final VoidCallback? onHelpful;

  const ReviewTile({
    super.key,
    required this.review,
    required this.marked,
    required this.count,
    this.pending = false,
    this.onHelpful,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.tomatoLight,
                child: Text(
                  review.initials,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.tomato),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.authorName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.espresso),
                ),
              ),
              for (var i = 1; i <= 5; i++)
                Icon(
                  i <= review.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 14,
                  color: AppColors.tomato,
                ),
            ],
          ),
          if (review.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.text, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.espresso)),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(review.dinedAgo, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ),
              TextButton.icon(
                onPressed: onHelpful,
                style: TextButton.styleFrom(
                  foregroundColor: marked ? AppColors.tomato : AppColors.muted,
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(
                  pending ? Icons.cloud_upload_outlined : (marked ? Icons.thumb_up : Icons.thumb_up_outlined),
                  size: 16,
                ),
                label: Text('Helpful · $count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
