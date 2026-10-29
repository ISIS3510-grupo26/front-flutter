import 'dart:math';

import '../models/hourly_ranking.dart';

/// A spot in "Popular right now" and why it is shown there.
class PopularPick {
  static const popularNow = 'Popular now';
  static const popularAndMatches = 'Popular now + matches your profile';

  final SpotActivity spot;
  final String reason;

  const PopularPick(this.spot, this.reason);
}

/// Smart ordering for "Popular right now": popularity and compatibility,
/// weighted 50/50.
///
/// Popularity is each spot's total (views + searches) divided by the highest
/// total of the hour, so it is 0–1 however busy the hour was.
/// [compatibility] scores how well a spot matches the student's taste
/// profile, also 0–1. The taste profile isn't saved anywhere the app's
/// services can read yet (Taste Profile and Dietary Preferences only keep it
/// on screen), so it defaults to 0 and the order is popularity alone, which is
/// the backend's own ranking. Ties keep the backend rank.
List<PopularPick> rankForProfile(
  List<SpotActivity> spots, {
  double Function(SpotActivity spot) compatibility = _noProfile,
}) {
  if (spots.isEmpty) return const [];
  final maxTotal = max(1, spots.map((s) => s.total).reduce(max));
  final scored = [
    for (final spot in spots)
      (spot: spot, popularity: spot.total / maxTotal, match: compatibility(spot)),
  ];
  double score(({SpotActivity spot, double popularity, double match}) s) =>
      0.5 * s.popularity + 0.5 * s.match;
  scored.sort((a, b) {
    final byScore = score(b).compareTo(score(a));
    return byScore != 0 ? byScore : a.spot.rank.compareTo(b.spot.rank);
  });
  return [
    for (final s in scored)
      PopularPick(
        s.spot,
        s.match > 0 ? PopularPick.popularAndMatches : PopularPick.popularNow,
      ),
  ];
}

double _noProfile(SpotActivity spot) => 0;
