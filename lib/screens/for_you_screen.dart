import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../services/popularity_loader.dart';
import '../services/shake_detector.dart';
import '../services/shake_picker.dart';
import '../services/weather_context.dart';
import '../services/weather_service.dart';
import '../theme/app_colors.dart';
import '../widgets/filter_chip_pill.dart';
import '../widgets/popular_now_section.dart';
import '../widgets/spot_card.dart';
import 'popular_by_hour_screen.dart';

class ForYouScreen extends StatefulWidget {
  final List<Spot> spots;
  final ValueChanged<String> onToggleSaved;
  final ValueChanged<String>? onOpenSpot;

  /// Opening a spot from search results, which BQ3 counts as a search.
  final ValueChanged<String>? onOpenFromSearch;
  final PopularityLoader popularLoader;

  /// Smart feature: compatibility 0-100 calculated by the backend for this
  /// student, keyed by spot id. It replaces the catalog's fixed percentage
  /// and the feed is sorted by it.
  final Map<String, int>? matchScores;

  /// Weather on campus from the external service. Null = unknown.
  final WeatherNow? weather;

  /// Sensor: listens to the accelerometer only while [shakeActive] (this tab
  /// on screen and the app open). Null disables "shake to decide".
  final ShakeDetector? shakeDetector;
  final bool shakeActive;

  /// Opens BQ4 ("Wait times now"). Null hides the banner.
  final VoidCallback? onOpenWaitTimes;

  const ForYouScreen({
    super.key,
    required this.spots,
    required this.onToggleSaved,
    required this.popularLoader,
    this.onOpenSpot,
    this.onOpenFromSearch,
    this.matchScores,
    this.weather,
    this.shakeDetector,
    this.shakeActive = false,
    this.onOpenWaitTimes,
  });

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  final Set<FeedFilterType> _activeFilters = {FeedFilterType.inARush};
  final _search = TextEditingController();
  PopularityState _popular = const PopularityLoading();

  /// The student chose "Usual order" while it rains.
  bool _ignoreWeather = false;

  /// The feed exactly as it is on screen: what "shake to decide" picks from.
  List<Spot> _feed = const [];
  bool _pickOpen = false;

  /// Coming back to the app reloads the section: within 5 minutes it comes
  /// from the LRU cache, and after the hour changes it shows the new hour.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _loadPopular);
    _search.addListener(() => setState(() {}));
    _loadPopular();
    _syncShake();
  }

  @override
  void didUpdateWidget(ForYouScreen old) {
    super.didUpdateWidget(old);
    if (old.shakeActive != widget.shakeActive || old.shakeDetector != widget.shakeDetector) {
      old.shakeDetector?.stop();
      _syncShake();
    }
  }

  @override
  void dispose() {
    widget.shakeDetector?.stop();
    _lifecycle.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Keeps the current section on screen until the new ranking arrives.
  Future<void> _loadPopular({bool forceRefresh = false}) async {
    final state = await widget.popularLoader.load(forceRefresh: forceRefresh);
    if (mounted) setState(() => _popular = state);
  }

  void _retryPopular() {
    setState(() => _popular = const PopularityLoading());
    _loadPopular();
  }

  void _openPopularByHour() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PopularByHourScreen(
          loader: widget.popularLoader,
          onOpenSpot: widget.onOpenSpot,
        ),
      ),
    );
  }

  void _syncShake() {
    final detector = widget.shakeDetector;
    if (detector == null) return;
    if (widget.shakeActive) {
      detector.start(_onShake);
    } else {
      detector.stop();
    }
  }

  Future<void> _onShake() async {
    // Only when this screen is the one on top (not under a restaurant page)
    // and there isn't already a suggestion open.
    if (!mounted || _pickOpen) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final pick = pickForShake(_feed);
    if (pick == null) return;
    _pickOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cream,
      builder: (sheetContext) => _ShakePick(
        spot: pick,
        onOpen: widget.onOpenSpot == null
            ? null
            : () {
                Navigator.pop(sheetContext);
                widget.onOpenSpot!(pick.id);
              },
      ),
    );
    _pickOpen = false;
  }

  void _toggleFilter(FeedFilterType filter) {
    setState(() {
      if (_activeFilters.contains(filter)) {
        _activeFilters.remove(filter);
      } else {
        _activeFilters.add(filter);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // While searching, the filters and Popular right now step aside, as in
    // the Kotlin app: the list shows every spot that matches the text.
    final query = _search.text.trim();
    final searching = query.isNotEmpty;
    final scores = widget.matchScores;
    var feed = [
      for (final spot in widget.spots)
        if (searching ? spot.matchesSearch(query) : _activeFilters.every(spot.matchesFilter))
          scores?[spot.id] == null ? spot : spot.copyWith(affinityPercent: scores![spot.id]),
    ];
    if (scores != null) {
      feed.sort((a, b) => b.affinityPercent.compareTo(a.affinityPercent));
    }
    // Context aware: with rain, the closest places go first. Not while
    // searching: then the student is looking for something specific.
    final weather = _ignoreWeather || searching ? null : widget.weather;
    feed = orderForWeather(feed, weather);
    final note = weatherNote(weather);
    _feed = feed;
    final openSpot = searching ? widget.onOpenFromSearch : widget.onOpenSpot;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _loadPopular(forceRefresh: true),
        color: AppColors.tomato,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CampusBites',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.tomato,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Campus food,\ntailored for you',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.espresso,
                        height: 1.15,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Curated by what students with your taste and schedule love',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                        height: 1.3,
                      ),
                    ),
                    if (widget.weather case final w?) ...[
                      const SizedBox(height: 12),
                      _WeatherChip(weather: w),
                    ],
                    if (note != null) ...[
                      const SizedBox(height: 10),
                      _WeatherNote(note: note, onUsualOrder: () => setState(() => _ignoreWeather = true)),
                    ],
                    if (widget.onOpenWaitTimes case final onTap?) ...[
                      const SizedBox(height: 12),
                      _WaitTimesBanner(onTap: onTap),
                    ],
                    if (widget.shakeDetector != null && widget.shakeActive) ...[
                      const SizedBox(height: 10),
                      const Text(
                        "🎲 Can't decide? Shake your phone and we'll pick for you.",
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SearchBar(controller: _search),
                    if (!searching) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: FeedFilterType.values.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final filter = FeedFilterType.values[index];
                            return FilterChipPill(
                              label: filter.label,
                              active: _activeFilters.contains(filter),
                              onTap: () => _toggleFilter(filter),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            if (!searching)
              SliverToBoxAdapter(
                child: PopularNowSection(
                  state: _popular,
                  onRetry: _retryPopular,
                  onSeeAll: _openPopularByHour,
                  onOpenSpot: widget.onOpenSpot,
                ),
              ),
            if (feed.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      searching
                          ? 'No spots match "$query".'
                          : 'No spots match these filters yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                sliver: SliverList.separated(
                  itemCount: feed.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final spot = feed[index];
                    return SpotCard(
                      spot: spot,
                      onToggleSaved: () => widget.onToggleSaved(spot.id),
                      onTap: openSpot == null ? null : () => openSpot(spot.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;

  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color),
    );
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      cursorColor: AppColors.tomato,
      style: const TextStyle(fontSize: 14, color: AppColors.espresso),
      decoration: InputDecoration(
        hintText: 'Search a spot, cuisine or place',
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.muted),
        prefixIcon: const Icon(Icons.search, color: AppColors.muted),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: controller.clear,
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, color: AppColors.muted),
              ),
        filled: true,
        fillColor: AppColors.card,
        enabledBorder: border(AppColors.border),
        focusedBorder: border(AppColors.tomato),
      ),
    );
  }
}

class _WeatherChip extends StatelessWidget {
  final WeatherNow weather;

  const _WeatherChip({required this.weather});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '${weather.emoji}  ${weather.label} on campus',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.espresso),
      ),
    );
  }
}

class _WeatherNote extends StatelessWidget {
  final String note;
  final VoidCallback onUsualOrder;

  const _WeatherNote({required this.note, required this.onUsualOrder});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(child: Text(note, style: const TextStyle(fontSize: 12, color: AppColors.espresso))),
          TextButton(onPressed: onUsualOrder, child: const Text('Usual order')),
        ],
      ),
    );
  }
}

class _WaitTimesBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _WaitTimesBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.tomato,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.hourglass_bottom, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wait times now',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'How long the line is at each place, reported by students',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShakePick extends StatelessWidget {
  final Spot spot;
  final VoidCallback? onOpen;

  const _ShakePick({required this.spot, this.onOpen});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '🎲 How about...',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Text(
              '${spot.emoji}  ${spot.name}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.espresso),
            ),
            const SizedBox(height: 4),
            Text(
              '${spot.affinityPercent}% match · ${spot.walkMinutes} min walk · ${spot.price}',
              style: const TextStyle(fontSize: 13, color: AppColors.espresso),
            ),
            const SizedBox(height: 4),
            const Text(
              'Picked from your top places. Close this and shake again for another one.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            if (onOpen != null)
              FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.tomato,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text("Let's go"),
              ),
          ],
        ),
      ),
    );
  }
}
