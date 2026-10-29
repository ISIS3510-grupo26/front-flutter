import 'package:flutter/material.dart';

import '../models/hourly_ranking.dart';
import '../services/popularity_loader.dart';
import '../services/popularity_ranking.dart';
import '../theme/app_colors.dart';
import 'offline_banner.dart';

/// '12 views · 1 search'.
String activitySummary(int views, int searches) =>
    '${_count(views, 'view', 'views')} · ${_count(searches, 'search', 'searches')}';

String _count(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';

/// "Popular right now" on For You: the spots students open and search the
/// most at this hour. It only draws a [PopularityState]; For You loads it.
/// "See all" needs a connection, so it is hidden while showing saved data or
/// a network failure; an hour with no activity still links to the others.
class PopularNowSection extends StatelessWidget {
  final PopularityState state;
  final VoidCallback onRetry;
  final VoidCallback onSeeAll;
  final ValueChanged<String>? onOpenSpot;

  const PopularNowSection({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onSeeAll,
    this.onOpenSpot,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      PopularityEmpty(:final hour) => _Frame(
        hourLabel: HourlyRanking.labelFor(hour),
        onSeeAll: onSeeAll,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No activity yet this hour.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
      ),
      PopularityLoading() => const _Frame(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(999)),
            child: LinearProgressIndicator(
              minHeight: 3,
              color: AppColors.tomato,
              backgroundColor: AppColors.tomatoLight,
            ),
          ),
        ),
      ),
      PopularityFailed(:final reason) => _Frame(
        child: _FailedRow(reason: reason, onRetry: onRetry),
      ),
      PopularityLoaded(:final ranking, :final offlineSavedAt) => _Frame(
        hourLabel: ranking.label,
        onSeeAll: offlineSavedAt == null ? onSeeAll : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (offlineSavedAt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: OfflineBanner(
                  message: 'Offline · data from ${hourMinute(offlineSavedAt)}',
                ),
              ),
            _Cards(
              picks: rankForProfile(ranking.spots),
              onOpenSpot: onOpenSpot,
            ),
          ],
        ),
      ),
    };
  }
}

class _Frame extends StatelessWidget {
  final String? hourLabel;
  final VoidCallback? onSeeAll;
  final Widget child;

  const _Frame({this.hourLabel, this.onSeeAll, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Popular right now',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.espresso,
                          ),
                        ),
                        if (hourLabel case final label?)
                          TextSpan(
                            text: '  $label',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (onSeeAll case final seeAll?)
                  TextButton(
                    onPressed: seeAll,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.tomato,
                    ),
                    child: const Text('See all'),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _FailedRow extends StatelessWidget {
  final PopularityFailure reason;
  final VoidCallback onRetry;

  const _FailedRow({required this.reason, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final notice = switch (reason) {
      PopularityFailure.network => const OfflineBanner(
        message: "Offline · popular spots show up when you're back online",
      ),
      PopularityFailure.server => const Text(
        "Couldn't load what's popular right now.",
        style: TextStyle(fontSize: 13, color: AppColors.muted),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: notice),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.tomato),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _Cards extends StatelessWidget {
  final List<PopularPick> picks;
  final ValueChanged<String>? onOpenSpot;

  const _Cards({required this.picks, required this.onOpenSpot});

  @override
  Widget build(BuildContext context) {
    // At most a handful of spots per hour, so a Row is enough, and
    // IntrinsicHeight makes every card as tall as the tallest one.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, pick) in picks.indexed) ...[
              if (index > 0) const SizedBox(width: 12),
              _PopularCard(
                position: index + 1,
                pick: pick,
                onTap: onOpenSpot == null
                    ? null
                    : () => onOpenSpot!(pick.spot.spotId),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PopularCard extends StatelessWidget {
  final int position;
  final PopularPick pick;
  final VoidCallback? onTap;

  const _PopularCard({required this.position, required this.pick, this.onTap});

  @override
  Widget build(BuildContext context) {
    final spot = pick.spot;
    final matches = pick.reason == PopularPick.popularAndMatches;
    return SizedBox(
      width: 160,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.espresso.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        spot.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '#$position',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.tomato,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  spot.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.espresso,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  activitySummary(spot.pageViews, spot.searches),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                const Spacer(),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: matches ? AppColors.tomato : AppColors.tomatoLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pick.reason,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: matches ? Colors.white : AppColors.tomato,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
