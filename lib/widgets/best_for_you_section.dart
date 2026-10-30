import 'package:flutter/material.dart';

import '../models/best_for_you.dart';
import '../services/best_for_you_loader.dart';
import '../theme/app_colors.dart';
import 'for_you_section.dart';
import 'retry_row.dart';

/// "Best for you right now" on For You (BQ6): the restaurants with the
/// shortest wait that best match the student's taste. It only draws a
/// [BestForYouState]; For You loads it.
class BestForYouSection extends StatelessWidget {
  /// The feed cards already show a match % calculated from the whole profile
  /// (`/matches`), and BQ6 scores only cuisine, diet and budget, so the same
  /// place would show two different numbers. The card says it matches only
  /// when BQ6 gives at least 70: the cuisine alone, when filled in, is enough.
  static const _matchesTaste = 70;

  final BestForYouState state;
  final VoidCallback onRetry;
  final ValueChanged<String>? onOpenSpot;

  const BestForYouSection({
    super.key,
    required this.state,
    required this.onRetry,
    this.onOpenSpot,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      BestForYouLoading() => const SectionLoadingBar(),
      BestForYouFailed(:final reason) => RetryRow(
        offline: reason == BestForYouFailure.network,
        offlineMessage: "Offline · your best picks show up when you're back online",
        errorMessage: "Couldn't load your best picks right now.",
        onRetry: onRetry,
      ),
      BestForYouLoaded(:final ranking, :final offlineSavedAt) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '⚡ Best for you right now',
            summary: ranking.personalized
                ? 'Short waits that match your taste'
                : 'Shortest waits · fill in your Taste Profile to personalize',
          ),
          if (offlineSavedAt != null) SectionOfflineBanner(savedAt: offlineSavedAt),
          if (ranking.spots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'No places to rank yet.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            )
          else
            RankedSpotRow(
              cards: [
                for (final (index, spot) in ranking.spots.indexed)
                  RankedSpotCard(
                    rank: index + 1,
                    emoji: spot.emoji,
                    name: spot.name,
                    detail: _wait(spot),
                    // Saved offline, "reported 5 min ago" would be counted
                    // from when it was saved, not from now.
                    note: spot.isRecent && offlineSavedAt == null && spot.minutesAgo != null
                        ? 'reported ${spot.minutesAgo} min ago'
                        : null,
                    tag: (spot.tasteMatch ?? 0) >= _matchesTaste ? 'Matches your taste' : null,
                    onTap: onOpenSpot == null ? null : () => onOpenSpot!(spot.spotId),
                  ),
              ],
            ),
        ],
      ),
    };
  }

  /// Only a recent wait counts in the score, so only that one is shown.
  static String _wait(BestForYouSpot spot) => switch ((spot.isRecent, spot.waitMinutes)) {
    (true, final minutes?) => '⏱ $minutes min wait',
    _ => '⏱ No recent wait report',
  };
}
