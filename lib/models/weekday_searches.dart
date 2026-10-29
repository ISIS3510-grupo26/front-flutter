/// How many times students opened a restaurant from search results on one
/// day of the week.
class WeekdaySearchCount {
  /// 0 = Monday ... 6 = Sunday.
  final int dayOfWeek;
  final String dayName;
  final int searches;

  const WeekdaySearchCount({
    required this.dayOfWeek,
    required this.dayName,
    required this.searches,
  });

  factory WeekdaySearchCount.fromJson(Map<String, dynamic> json) {
    return WeekdaySearchCount(
      dayOfWeek: json['dayOfWeek'] as int,
      dayName: json['dayName'] as String,
      searches: json['searches'] as int,
    );
  }
}

/// `GET /analytics/searches-by-weekday`: restaurant selections from search
/// results over the last [days] days, Monday to Sunday.
class WeekdaySearches {
  final int days;
  final int totalSearches;
  final List<WeekdaySearchCount> byDay;

  const WeekdaySearches({
    required this.days,
    required this.totalSearches,
    required this.byDay,
  });

  factory WeekdaySearches.fromJson(Map<String, dynamic> json) {
    return WeekdaySearches(
      days: json['days'] as int,
      totalSearches: json['totalSearches'] as int,
      byDay: [
        for (final day in json['byDay'] as List<dynamic>)
          WeekdaySearchCount.fromJson(day as Map<String, dynamic>),
      ],
    );
  }
}
