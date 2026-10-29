import 'package:campus_bites/models/hourly_ranking.dart';
import 'package:campus_bites/services/popularity_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

SpotActivity _spot(String id, {required int rank, required int total}) => SpotActivity(
      rank: rank,
      spotId: id,
      name: id,
      emoji: '🍔',
      pageViews: total,
      searches: 0,
      total: total,
    );

List<String> _ids(List<PopularPick> picks) => [for (final p in picks) p.spot.spotId];

void main() {
  final busy = _spot('busy', rank: 1, total: 10);
  final medium = _spot('medium', rank: 2, total: 6);
  final quiet = _spot('quiet', rank: 3, total: 2);

  test('without a profile it orders by popularity alone', () {
    final picks = rankForProfile([quiet, busy, medium]);

    expect(_ids(picks), ['busy', 'medium', 'quiet']);
    expect(picks.map((p) => p.reason), everyElement(PopularPick.popularNow));
  });

  test('a profile match lifts a less popular spot', () {
    final picks = rankForProfile(
      [busy, medium, quiet],
      compatibility: (s) => s.spotId == 'quiet' ? 1 : 0,
    );

    // busy: 0.5 * 1.0 = 0.5; quiet: 0.5 * 0.2 + 0.5 * 1.0 = 0.6.
    expect(_ids(picks), ['quiet', 'busy', 'medium']);
    expect(picks.first.reason, PopularPick.popularAndMatches);
    expect(picks.last.reason, PopularPick.popularNow);
  });

  test('ties keep the backend rank', () {
    final first = _spot('first', rank: 1, total: 5);
    final second = _spot('second', rank: 2, total: 5);

    expect(_ids(rankForProfile([second, first])), ['first', 'second']);
  });

  test('no spots, no picks', () {
    expect(rankForProfile(const []), isEmpty);
  });
}
