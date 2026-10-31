import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/spot_detail.dart';
import '../models/telemetry_event.dart';
import '../repositories/api_exception.dart';
import '../repositories/spots_repository.dart';
import '../services/favorites_controller.dart';
import '../services/local_database.dart';
import '../services/place_detail_loader.dart';
import '../services/review_submitter.dart';
import '../services/telemetry_queue.dart';
import '../theme/app_colors.dart';
import '../widgets/offline_banner.dart';
import 'write_review_screen.dart';

class PlaceDetailScreen extends StatefulWidget {
  final String spotId;
  final SpotsRepository repository;
  final TelemetryQueue telemetry;
  final String? Function() currentUserId;

  final bool canReview;

  /// The app-wide saved state, so the heart here matches For You and Saved,
  /// and the catalog coordinates for walking directions.
  final FavoritesController favorites;
  final ValueChanged<String> onToggleSaved;

  /// Saved copies of the pages, for offline use.
  final SpotDetailStorage storage;
  
  /// Publishes reviews (BQ13) and keeps their drafts on the phone.
  final ReviewSubmitter reviewSubmitter;

  const PlaceDetailScreen({
    super.key,
    required this.spotId,
    required this.repository,
    required this.telemetry,
    required this.currentUserId,
    required this.canReview,
    required this.favorites,
    required this.onToggleSaved,
    required this.reviewSubmitter,
    this.storage = const SqliteSpotDetailStorage(),
  });

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  SpotDetail? _spot;
  bool _failed = false;
  bool _reviewed = false;

  /// Set while the page shows the copy saved on the phone.
  DateTime? _offlineSavedAt;
  late final StreamSubscription<List<ConnectivityResult>> _connectivity;

  @override
  void initState() {
    super.initState();
    _connectivity = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    _load(reportVisit: true);
  }

  @override
  void dispose() {
    _connectivity.cancel();
    super.dispose();
  }

  /// Stream: when the connection comes back while the page shows saved data
  /// (or an error), it reloads by itself. Not reported as a new visit.
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online && (_offlineSavedAt != null || _failed)) _load(reportVisit: false);
  }

  Future<void> _load({required bool reportVisit}) async {
    if (_failed) setState(() => _failed = false);
    final watch = Stopwatch()..start();
    final result = await loadPlaceDetail(
      spotId: widget.spotId,
      fetch: widget.repository.fetchSpot,
      storage: widget.storage,
    );
    if (reportVisit) {
      final error = result.error;
      _report(watch.elapsedMilliseconds, httpStatus: error == null ? 200 : null, error: error);
    }
    if (!mounted) return;
    setState(() {
      if (result.spot case final spot?) {
        _spot = spot;
        _offlineSavedAt = result.offlineSavedAt;
      } else {
        _failed = true;
      }
    });
  }

  void _report(int durationMs, {int? httpStatus, Object? error}) {
    widget.telemetry.enqueue(TelemetryEvent.restaurantDetail(
      spotId: widget.spotId,
      userId: widget.currentUserId(),
      durationMs: durationMs,
      success: error == null,
      httpStatus: error is ApiException ? error.statusCode : httpStatus,
      errorType: error == null ? null : _errorType(error),
    ));
  }

  /// Same categories as the Kotlin app, so BQ2 can compare both apps.
  static String _errorType(Object e) => switch (e) {
        ApiException(:final statusCode) => 'HTTP_$statusCode',
        TimeoutException() => 'TIMEOUT',
        SocketException() => 'NO_CONNECTION',
        FormatException() || TypeError() => 'PARSE_ERROR',
        http.ClientException() => 'NETWORK_ERROR',
        _ => 'UNKNOWN',
      };

  /// Google Maps walking directions to the spot, from the catalog
  /// coordinates; null for a spot the app has no coordinates for.
  Uri? _directionsUri(String spotId) {
    final spot = widget.favorites.spotById(spotId);
    if (spot == null) return null;
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${spot.latitude},${spot.longitude}',
      'travelmode': 'walking',
    });
  }

  Future<void> _openDirections(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showMessage("Couldn't open maps on this phone.");
  }

  Future<void> _share(SpotDetail spot) async {
    final directions = _directionsUri(spot.id);
    try {
      await SharePlus.instance.share(
        ShareParams(
          subject: spot.name,
          text: [
            '${spot.name} · ${spot.subtitle}',
            '⭐ ${spot.rating} on CampusBites',
            if (directions != null) '$directions',
          ].join('\n'),
        ),
      );
    } on Exception {
      _showMessage("Couldn't open the share menu.");
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _writeReview(SpotDetail spot) async {
    final result = await Navigator.push<ReviewResult>(
      context,
      MaterialPageRoute(
        builder: (_) => WriteReviewScreen(
          spotId: spot.id,
          spotName: spot.name,
          submitter: widget.reviewSubmitter,
        ),
      ),
    );
        if (!mounted) return;
    if (result == null) {
      setState(() {}); // there may be a draft now, the button changes to "Continue your review"
      return;
    }
    setState(() => _reviewed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks! Your review was published.')),
    );
    _load(reportVisit: false);
  }

  @override
  Widget build(BuildContext context) {
    final spot = _spot;
    if (spot == null) {
      return Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(backgroundColor: AppColors.cream, foregroundColor: AppColors.espresso, elevation: 0),
        body: Center(
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Couldn't load this place.",
                      style: TextStyle(fontSize: 15, color: AppColors.espresso),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _load(reportVisit: true),
                      child: const Text('Try again'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(color: AppColors.tomato),
        ),
      );
    }
    return _buildPage(spot);
  }

  Widget _buildPage(SpotDetail spot) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: AppColors.espresso),
                  ),
                  Expanded(
                    child: Text(
                      spot.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.espresso,
                      ),
                    ),
                  ),
                  if (widget.favorites.spotById(spot.id) != null)
                    ListenableBuilder(
                      listenable: widget.favorites,
                      builder: (context, _) {
                        final saved =
                            widget.favorites.spotById(spot.id)?.isSaved ?? false;
                        return IconButton(
                          onPressed: () => widget.onToggleSaved(spot.id),
                          tooltip: saved ? 'Remove from saved' : 'Save this spot',
                          icon: Icon(
                            saved ? Icons.favorite : Icons.favorite_border,
                            color: AppColors.tomato,
                          ),
                        );
                      },
                    ),
                  IconButton(
                    onPressed: () => _share(spot),
                    tooltip: 'Share',
                    icon: const Icon(Icons.share_outlined, color: AppColors.espresso),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            sliver: SliverList.list(
              children: [
                if (_offlineSavedAt case final savedAt?) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OfflineBanner(message: 'Offline · saved on ${hourMinute(savedAt)}'),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  height: 200,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: spot.emojiBackground,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          alignment: Alignment.center,
                          child: Text(spot.emoji, style: const TextStyle(fontSize: 72)),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _TomatoPill(label: '${spot.affinityPercent}% Taste Match'),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 14, color: AppColors.tomato),
                              const SizedBox(width: 4),
                              Text(
                                spot.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.espresso,
                                ),
                              ),
                              Text(
                                ' (${spot.totalReviews})',
                                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Row(
                          children: [
                            if (spot.uniCardPerk != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.mint,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check, size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Campus Card Accepted',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (spot.uniCardPerk != null) const SizedBox(width: 8),
                            if (spot.isVegetarian)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Veggie Friendly',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.espresso,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spot.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.espresso,
                        ),
                      ),
                    ),
                    if (_isOpenNow)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.mintLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: AppColors.mint),
                            SizedBox(width: 6),
                            Text(
                              'Open Now',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.mint,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  spot.subtitle,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(icon: Icons.directions_walk, label: 'Distance', value: spot.distance),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: _StatTile(icon: Icons.access_time, label: 'Wait Time', value: _waitTimeLabel),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(icon: Icons.attach_money, label: 'Price Range', value: spot.price),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: _StatTile(icon: Icons.calendar_today, label: 'Hours Today', value: _hoursTodayLabel),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.tomatoLight,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Why it fits your profile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.tomato,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        spot.note,
                        style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.espresso),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 56,
                            height: 24,
                            child: Stack(
                              children: const [
                                Positioned(left: 0, child: _Avatar('JL')),
                                Positioned(left: 16, child: _Avatar('M')),
                                Positioned(left: 32, child: _Avatar('AR')),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Verified student community consensus',
                              style: TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _ReviewsHeader(
                  totalReviews: spot.totalReviews,
                  onWrite: widget.canReview && !_reviewed ? () => _writeReview(spot) : null,
                  hint: widget.canReview ? null : 'Sign in with an account to leave a review.',
                  offline: _offlineSavedAt != null,
                  hasDraft: widget.reviewSubmitter.store.hasDraft(spot.id),
                ),
                const SizedBox(height: 10),
                for (final review in spot.reviews) ...[
                  _ReviewCard(review: review),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _directionsUri(spot.id) == null
                  ? null
                  : () => _openDirections(_directionsUri(spot.id)!),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.tomato,
                disabledBackgroundColor: AppColors.tomato,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.explore_outlined, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Get Walking Directions (${spot.walkMinutes} min)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewsHeader extends StatelessWidget {
  final int totalReviews;
  final VoidCallback? onWrite;
  final String? hint;

  /// Showing saved data: the write button stays visible but disabled.
  final bool offline;
  
  /// The student left a review half written here (saved in Hive).
  final bool hasDraft;

  const _ReviewsHeader({
    required this.totalReviews,
    required this.onWrite,
    this.hint,
    this.offline = false,
    this.hasDraft = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Student Reviews ($totalReviews)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.espresso,
                ),
              ),
            ),
            if (offline)
              TextButton.icon(
                onPressed: null,
                icon: const Icon(Icons.cloud_off, size: 18),
                label: const Text('Reviews need internet'),
              )
            else if (onWrite != null)
              TextButton.icon(
                onPressed: onWrite,
                icon: const Icon(Icons.rate_review_outlined, size: 18, color: AppColors.tomato),
                label: Text(
                  hasDraft ? 'Continue your review' : 'Rate it',
                  style: const TextStyle(color: AppColors.tomato, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        if (hint != null)
          Text(hint!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final SpotReview review;

  const _ReviewCard({required this.review});

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
              _Avatar(review.initials),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.authorName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.espresso,
                  ),
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
            Text(
              review.text,
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.espresso),
            ),
          ],
          const SizedBox(height: 6),
          Text(review.dinedAgo, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tomatoLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.tomato),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.espresso),
          ),
        ],
      ),
    );
  }
}

class _TomatoPill extends StatelessWidget {
  final String label;

  const _TomatoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tomato,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;

  const _Avatar(this.initials);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.cream, width: 2),
      ),
      child: Text(
        initials,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.espresso),
      ),
    );
  }
}

// Not served by the backend yet (wait times are BQ4, still unassigned).
const _waitTimeLabel = '8-12 min';
const _hoursTodayLabel = '11:00 AM - 7:30 PM';
const _isOpenNow = true;
