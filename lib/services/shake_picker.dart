import 'dart:math';

import '../models/spot.dart';

/// What the app suggests when the student shakes the phone because they
/// can't decide.

/// It doesn't pick at random from everything, it takes the first [top] places of the feed exactly as the 
/// student sees it (their filters, sorted by their match, and with the weather order if it rains) and draws 
/// one weighted by its match %, so a 90% place comes out more often than a 60% one
Spot? pickForShake(List<Spot> feed, {Random? random, int top = 3}) {
  if (feed.isEmpty) return null;
  final candidates = feed.take(top).toList();
  final weights = [for (final spot in candidates) max(1, spot.affinityPercent)];
  var ticket = (random ?? Random()).nextInt(weights.reduce((a, b) => a + b));
  for (var i = 0; i < candidates.length; i++) {
    ticket -= weights[i];
    if (ticket < 0) return candidates[i];
  }
  return candidates.last;
}