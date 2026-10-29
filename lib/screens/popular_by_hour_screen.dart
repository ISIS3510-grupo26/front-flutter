import 'package:flutter/material.dart';

import '../models/hourly_ranking.dart';
import '../models/weekday_searches.dart';
import '../services/popularity_loader.dart';
import '../theme/app_colors.dart';
import '../widgets/count_pill.dart';
import '../widgets/popular_now_section.dart';

/// "By hour" from Popular right now, the same design as the Kotlin app:
/// which restaurants get the most page views and searches at each hour. It
/// starts on the phone's current hour, and chips switch to any other hour.
class PopularByHourScreen extends StatefulWidget {
  final PopularityLoader loader;
  final ValueChanged<String>? onOpenSpot;

  const PopularByHourScreen({super.key, required this.loader, this.onOpenSpot});

  @override
  State<PopularByHourScreen> createState() => _PopularByHourScreenState();
}

class _PopularByHourScreenState extends State<PopularByHourScreen> {
  late final int _currentHour = widget.loader.currentHour;
  late int _selectedHour = _currentHour;
  PopularByHourState _state = const PopularByHourLoading();
  final _currentHourChip = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    // The chips start centered on the current hour.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentHourChip.currentContext case final chip?) {
        Scrollable.ensureVisible(chip, alignment: 0.5);
      }
    });
  }

  Future<void> _load() async {
    if (_state is! PopularByHourLoading) {
      setState(() => _state = const PopularByHourLoading());
    }
    final state = await widget.loader.loadByHours();
    if (mounted) setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) {
    final report = switch (_state) {
      PopularByHourLoaded(:final report) => report,
      _ => null,
    };
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TopBar(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  for (var hour = 0; hour < 24; hour++) ...[
                    if (hour > 0) const SizedBox(width: 8),
                    CountPill(
                      key: hour == _currentHour ? _currentHourChip : null,
                      label: hour == _currentHour
                          ? 'Now · ${_twoDigits(hour)}:00'
                          : '${_twoDigits(hour)}:00',
                      active: hour == _selectedHour,
                      count: _activityAt(report, hour),
                      onTap: () => setState(() => _selectedHour = hour),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: switch (_state) {
                PopularByHourLoading() => const Center(
                  child: CircularProgressIndicator(color: AppColors.tomato),
                ),
                PopularByHourFailed(:final reason) => _ErrorMessage(
                  switch (reason) {
                    PopularityFailure.network =>
                      "Couldn't load the ranking. Check your connection.",
                    PopularityFailure.server => "Couldn't load the ranking right now. Try again in a moment.",
                  },
                  onRetry: _load,
                ),
                PopularByHourLoaded(:final report) => _RankingList(
                  ranking: report.rankingFor(_selectedHour),
                  days: report.days,
                  loadWeekdaySearches: widget.loader.searchesByWeekday,
                  onOpenSpot: widget.onOpenSpot,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Views + searches at [hour], only for hours with activity.
  static int? _activityAt(PopularityReport? report, int hour) {
    final ranking = report?.rankingFor(hour);
    if (ranking == null || ranking.isEmpty) return null;
    return ranking.totalPageViews + ranking.totalSearches;
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, color: AppColors.espresso),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Popular by hour',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.espresso,
                  ),
                ),
                Text(
                  'Page views and searches per restaurant, this week',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingList extends StatelessWidget {
  final HourlyRanking ranking;
  final int days;
  final Future<WeekdaySearches> Function() loadWeekdaySearches;
  final ValueChanged<String>? onOpenSpot;

  const _RankingList({
    required this.ranking,
    required this.days,
    required this.loadWeekdaySearches,
    required this.onOpenSpot,
  });

  @override
  Widget build(BuildContext context) {
    final most = ranking.spots.isEmpty ? 1 : ranking.spots.first.total;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.tomatoLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Text('🕒', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ranking.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.tomato,
                      ),
                    ),
                    Text(
                      '${countOf(ranking.totalPageViews, 'page view', 'page views')} · '
                      '${countOf(ranking.totalSearches, 'search', 'searches')} '
                      'in the last $days days',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.espresso,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _WeekdaySearchesCard(load: loadWeekdaySearches),
        if (ranking.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No activity at this hour yet.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        for (final spot in ranking.spots) ...[
          const SizedBox(height: 10),
          _RankingRow(
            spot: spot,
            most: most,
            onTap: onOpenSpot == null ? null : () => onOpenSpot!(spot.spotId),
          ),
        ],
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  final SpotActivity spot;
  final int most;
  final VoidCallback? onTap;

  const _RankingRow({required this.spot, required this.most, this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              RankBadge(rank: spot.rank, size: 32),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(spot.emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.espresso,
                      ),
                    ),
                    Text(
                      '👀 ${countOf(spot.pageViews, 'page view', 'page views')} · '
                      '🔎 ${countOf(spot.searches, 'search', 'searches')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ActivityBar(
                      views: spot.pageViews,
                      searches: spot.searches,
                      most: most,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${spot.total}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.tomato,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A stacked bar as long as this spot's activity relative to the hour's most
/// active spot: page views in tomato, searches in mint.
class _ActivityBar extends StatelessWidget {
  final int views;
  final int searches;
  final int most;

  const _ActivityBar({
    required this.views,
    required this.searches,
    required this.most,
  });

  @override
  Widget build(BuildContext context) {
    final share = ((views + searches) / (most < 1 ? 1 : most)).clamp(0.04, 1.0);
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: share,
        child: Row(
          children: [
            if (views > 0) _Segment(flex: views, color: AppColors.tomato),
            if (searches > 0) _Segment(flex: searches, color: AppColors.mint),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final int flex;
  final Color color;

  const _Segment({required this.flex, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// Restaurant selections from search results per day of the week, loaded on
/// its own so the hourly ranking never waits for it.
class _WeekdaySearchesCard extends StatefulWidget {
  final Future<WeekdaySearches> Function() load;

  const _WeekdaySearchesCard({required this.load});

  @override
  State<_WeekdaySearchesCard> createState() => _WeekdaySearchesCardState();
}

class _WeekdaySearchesCardState extends State<_WeekdaySearchesCard> {
  /// Multithreading strategy: Future. A FutureBuilder awaits the request and
  /// rebuilds the card when it finishes; Retry starts a new Future.
  late Future<WeekdaySearches> _searches = widget.load();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Restaurant searches by weekday',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.espresso,
            ),
          ),
          const SizedBox(height: 10),
          FutureBuilder(
            future: _searches,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Couldn't load weekday searches. Check your connection.",
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 10),
                    _RetryButton(
                      onPressed: () =>
                          setState(() => _searches = widget.load()),
                    ),
                  ],
                );
              }
              final report = snapshot.data;
              if (report == null) {
                return const LinearProgressIndicator(
                  color: AppColors.tomato,
                  backgroundColor: AppColors.tomatoLight,
                );
              }
              return _WeekdayBars(report: report);
            },
          ),
        ],
      ),
    );
  }
}

class _WeekdayBars extends StatelessWidget {
  final WeekdaySearches report;

  const _WeekdayBars({required this.report});

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(fontSize: 12, color: AppColors.muted);
    final summary = Text(
      '${countOf(report.totalSearches, 'restaurant selection', 'restaurant selections')} '
      'from search results in the last ${report.days} days',
      style: muted,
    );
    if (report.totalSearches == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          summary,
          const SizedBox(height: 10),
          const Text('No search selections recorded yet.', style: muted),
        ],
      );
    }
    final highest = report.byDay
        .map((d) => d.searches)
        .reduce((a, b) => a > b ? a : b);
    final busiestDays = [
      for (final day in report.byDay)
        if (day.searches == highest) day.dayName,
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        summary,
        for (final day in report.byDay)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    day.dayName.length <= 3
                        ? day.dayName
                        : day.dayName.substring(0, 3),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.espresso,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: day.searches / highest,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.mint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${day.searches}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.espresso,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Text(
          'Highest: $busiestDays ($highest)',
          style: const TextStyle(fontSize: 12, color: AppColors.tomato),
        ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;

  const _ErrorMessage(this.text, {required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            _RetryButton(onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RetryButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.tomato,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
