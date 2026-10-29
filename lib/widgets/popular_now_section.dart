import 'package:flutter/material.dart';

import '../models/hourly_ranking.dart';
import '../services/popularity_loader.dart';
import '../services/popularity_ranking.dart';
import '../theme/app_colors.dart';
import 'offline_banner.dart';

/// '1 view', '3 views'.
String countOf(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';

/// "Popular right now" on For You, the same design as the Kotlin app: the
/// spots students open and search the most at this hour. It only draws a
/// [PopularityState]; For You loads it. "By hour" needs a connection, so it
/// is hidden while showing saved data or a network failure; an hour with no
/// activity still links to the others.
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
      PopularityLoading() => const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: LinearProgressIndicator(
          minHeight: 2,
          color: AppColors.tomato,
          backgroundColor: AppColors.tomatoLight,
        ),
      ),
      PopularityEmpty(:final hour) => _Header(
        hourLabel: HourlyRanking.labelFor(hour),
        summary: 'No activity yet at this hour this week',
        onSeeAll: onSeeAll,
      ),
      PopularityFailed(:final reason) => _FailedRow(
        reason: reason,
        onRetry: onRetry,
      ),
      PopularityLoaded(:final ranking, :final offlineSavedAt) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            hourLabel: ranking.label,
            summary:
                '${countOf(ranking.totalPageViews, 'view', 'views')} · '
                '${countOf(ranking.totalSearches, 'search', 'searches')} '
                'at this hour this week',
            onSeeAll: offlineSavedAt == null ? onSeeAll : null,
          ),
          if (offlineSavedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: OfflineBanner(
                message: 'Offline · data from ${hourMinute(offlineSavedAt)}',
              ),
            ),
          _Cards(picks: rankForProfile(ranking.spots), onOpenSpot: onOpenSpot),
        ],
      ),
    };
  }
}

class _Header extends StatelessWidget {
  final String hourLabel;
  final String summary;
  final VoidCallback? onSeeAll;

  const _Header({
    required this.hourLabel,
    required this.summary,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSeeAll,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Word joiners keep '15:00–16:00' on one line.
                    '🔥 Popular right now · ${hourLabel.replaceAll('–', '⁠–⁠')}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.espresso,
                    ),
                  ),
                  Text(
                    summary,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (onSeeAll != null) ...[
              const Text(
                'By hour',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.tomato,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.tomato,
              ),
            ],
          ],
        ),
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
      padding: const EdgeInsets.only(left: 20, top: 12, right: 8),
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, pick) in picks.indexed) ...[
              if (index > 0) const SizedBox(width: 10),
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
    final radius = BorderRadius.circular(18);
    return SizedBox(
      width: 136,
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RankBadge(rank: position),
                    const Spacer(),
                    Text(spot.emoji, style: const TextStyle(fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  spot.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.espresso,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '👀 ${spot.pageViews} · 🔎 ${spot.searches}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
                // Only once a taste profile exists: then the reason matters.
                if (pick.reason == PopularPick.popularAndMatches) ...[
                  const Spacer(),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.tomato,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      pick.reason,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// '#1' in a circle: tomato for the first, espresso for the second, light
/// for the rest.
class RankBadge extends StatelessWidget {
  final int rank;
  final double size;

  const RankBadge({super.key, required this.rank, this.size = 26});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (rank) {
      1 => (AppColors.tomato, Colors.white),
      2 => (AppColors.espresso, Colors.white),
      _ => (AppColors.tomatoLight, AppColors.tomato),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        '#$rank',
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}
