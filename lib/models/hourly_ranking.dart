/// One spot in an hourly popularity ranking: how many students opened its
/// page and picked it from search during that hour.
class SpotActivity {
  final int rank;
  final String spotId;
  final String name;
  final String emoji;
  final int pageViews;
  final int searches;

  /// pageViews + searches; the backend ranks by this.
  final int total;

  const SpotActivity({
    required this.rank,
    required this.spotId,
    required this.name,
    required this.emoji,
    required this.pageViews,
    required this.searches,
    required this.total,
  });

  factory SpotActivity.fromJson(Map<String, dynamic> json) {
    return SpotActivity(
      rank: json['rank'] as int,
      spotId: json['spotId'] as String,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      pageViews: json['pageViews'] as int,
      searches: json['searches'] as int,
      total: json['total'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'spotId': spotId,
        'name': name,
        'emoji': emoji,
        'pageViews': pageViews,
        'searches': searches,
        'total': total,
      };
}

/// The most popular spots during one hour of the day (campus local time),
/// most popular first.
class HourlyRanking {
  final int hour;
  final int totalPageViews;
  final int totalSearches;
  final List<SpotActivity> spots;

  const HourlyRanking({
    required this.hour,
    required this.totalPageViews,
    required this.totalSearches,
    required this.spots,
  });

  /// An hour with no activity. The backend leaves such hours out of its
  /// report, so the app uses this instead of treating it as an error.
  const HourlyRanking.empty(this.hour)
      : totalPageViews = 0,
        totalSearches = 0,
        spots = const [];

  factory HourlyRanking.fromJson(Map<String, dynamic> json) {
    return HourlyRanking(
      hour: json['hour'] as int,
      totalPageViews: json['totalPageViews'] as int,
      totalSearches: json['totalSearches'] as int,
      spots: [
        for (final spot in json['spots'] as List<dynamic>)
          SpotActivity.fromJson(spot as Map<String, dynamic>),
      ],
    );
  }

  /// Same shape as the backend JSON, so [fromJson] reads it back.
  Map<String, dynamic> toJson() => {
        'hour': hour,
        'totalPageViews': totalPageViews,
        'totalSearches': totalSearches,
        'spots': [for (final spot in spots) spot.toJson()],
      };

  bool get isEmpty => spots.isEmpty;

  /// The hour as a range, e.g. '13:00–14:00'; 23 wraps to '23:00–00:00'.
  String get label => '${_twoDigits(hour)}:00–${_twoDigits((hour + 1) % 24)}:00';

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

/// `GET /analytics/spot-views-by-hour`: the ranking of every hour with
/// activity over the last [days] days.
class PopularityReport {
  final int days;
  final List<HourlyRanking> hours;

  const PopularityReport({required this.days, required this.hours});

  factory PopularityReport.fromJson(Map<String, dynamic> json) {
    return PopularityReport(
      days: json['days'] as int,
      hours: [
        for (final hour in json['hours'] as List<dynamic>)
          HourlyRanking.fromJson(hour as Map<String, dynamic>),
      ],
    );
  }

  /// The ranking for [hour], or an empty one if nobody was active then.
  HourlyRanking rankingFor(int hour) => hours.firstWhere(
        (ranking) => ranking.hour == hour,
        orElse: () => HourlyRanking.empty(hour),
      );
}
