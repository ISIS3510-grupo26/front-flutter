import '../models/spot.dart';
import 'weather_service.dart';

/// Context-aware for the For You feed: when it rains on campus, a long  walk matters more than taste, so the 
/// places within [rainWalkLimit] minutes go first. Inside each group the order does not change (it is
/// still the student's match order).
const rainWalkLimit = 5;

List<Spot> orderForWeather(List<Spot> feed, WeatherNow? weather) {
  if (weather == null || !weather.isRaining) return feed;
  return [
    for (final spot in feed)
      if (spot.walkMinutes <= rainWalkLimit) spot,
    for (final spot in feed)
      if (spot.walkMinutes > rainWalkLimit) spot,
  ];
}

/// Why the feed changed, to show it to the student. Null when nothing changed.
String? weatherNote(WeatherNow? weather) => weather != null && weather.isRaining
    ? "It's raining on campus: places within a $rainWalkLimit min walk go first."
    : null;
