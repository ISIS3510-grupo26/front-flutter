import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../services/popularity_loader.dart';
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

  const ForYouScreen({
    super.key,
    required this.spots,
    required this.onToggleSaved,
    required this.popularLoader,
    this.onOpenSpot,
    this.onOpenFromSearch,
  });

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  final Set<FeedFilterType> _activeFilters = {FeedFilterType.inARush};
  final _search = TextEditingController();
  PopularityState _popular = const PopularityLoading();

  /// Coming back to the app reloads the section: within 5 minutes it comes
  /// from the LRU cache, and after the hour changes it shows the new hour.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _loadPopular);
    _search.addListener(() => setState(() {}));
    _loadPopular();
  }

  @override
  void dispose() {
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
    final feed = widget.spots
        .where(
          (spot) => searching
              ? spot.matchesSearch(query)
              : _activeFilters.every(spot.matchesFilter),
        )
        .toList();
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
