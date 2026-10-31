import 'package:flutter/material.dart';

import '../models/hourly_ranking.dart';
import '../services/popularity_loader.dart';
import '../services/popularity_ranking.dart';
import 'for_you_section.dart';
import 'retry_row.dart';

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
      PopularityLoading() => const SectionLoadingBar(),
      PopularityEmpty(:final hour) => _header(
        HourlyRanking.labelFor(hour),
        'No activity yet at this hour this week',
        onSeeAll,
      ),
      PopularityFailed(:final reason) => RetryRow(
        offline: reason == PopularityFailure.network,
        offlineMessage: "Offline · popular spots show up when you're back online",
        errorMessage: "Couldn't load what's popular right now.",
        onRetry: onRetry,
      ),
      PopularityLoaded(:final ranking, :final offlineSavedAt) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(
            ranking.label,
            '${countOf(ranking.totalPageViews, 'view', 'views')} · '
                '${countOf(ranking.totalSearches, 'search', 'searches')} '
                'at this hour this week',
            offlineSavedAt == null ? onSeeAll : null,
          ),
          if (offlineSavedAt != null) SectionOfflineBanner(savedAt: offlineSavedAt),
          RankedSpotRow(
            cards: [
              for (final (index, pick) in rankForProfile(ranking.spots).indexed)
                RankedSpotCard(
                  rank: index + 1,
                  emoji: pick.spot.emoji,
                  name: pick.spot.name,
                  detail: '👀 ${pick.spot.pageViews} · 🔎 ${pick.spot.searches}',
                  // Only once a taste profile exists: then the reason matters.
                  tag: pick.reason == PopularPick.popularAndMatches ? pick.reason : null,
                  onTap: onOpenSpot == null ? null : () => onOpenSpot!(pick.spot.spotId),
                ),
            ],
          ),
        ],
      ),
    };
  }

  // Word joiners keep '15:00–16:00' on one line.
  static Widget _header(String hourLabel, String summary, VoidCallback? onSeeAll) =>
      SectionHeader(
        title: '🔥 Popular right now · ${hourLabel.replaceAll('–', '⁠–⁠')}',
        summary: summary,
        linkLabel: 'By hour',
        onLink: onSeeAll,
      );
}
