/// BQ15 (type 2): "At what time of the day is the reported waiting time at
/// each restaurant the shortest?"
/// It uses the same reports students make in "Wait times now" (BQ4), grouped
/// by the local hour when they were made.

/// The average wait reported at one hour of the day.
class HourlyWait {
  final int hour;
  final double avgMinutes;
  final int reports;

  const HourlyWait({required this.hour, required this.avgMinutes, required this.reports});

  factory HourlyWait.fromJson(Map<String, dynamic> json) => HourlyWait(
        hour: json['hour'] as int,
        avgMinutes: (json['avgMinutes'] as num).toDouble(),
        reports: json['reports'] as int,
      );

  /// Rounded for the screen: "~4 min".
  int get minutes => avgMinutes.round();
}

/// The best and worst hour of one restaurant.
class BestTimeSpot {
  final String spotId;
  final String name;
  final String emoji;

  /// Reports of this restaurant in the window.
  final int reports;

  /// Null when there are not enough reports to choose one.
  final int? bestHour;
  final double? bestAvgMinutes;
  final int? worstHour;
  final double? worstAvgMinutes;

  /// Only the hours that have reports, from 0 to 23.
  final List<HourlyWait> byHour;

  const BestTimeSpot({
    required this.spotId,
    required this.name,
    required this.emoji,
    required this.reports,
    required this.bestHour,
    required this.bestAvgMinutes,
    required this.worstHour,
    required this.worstAvgMinutes,
    required this.byHour,
  });

  factory BestTimeSpot.fromJson(Map<String, dynamic> json) => BestTimeSpot(
        spotId: json['spotId'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        reports: json['reports'] as int,
        bestHour: json['bestHour'] as int?,
        bestAvgMinutes: (json['bestHourAvgMinutes'] as num?)?.toDouble(),
        worstHour: json['worstHour'] as int?,
        worstAvgMinutes: (json['worstHourAvgMinutes'] as num?)?.toDouble(),
        byHour: [
          for (final item in json['byHour'] as List<dynamic>) HourlyWait.fromJson(item as Map<String, dynamic>),
        ],
      );

  bool get hasBestHour => bestHour != null;

  /// The best and the worst hour are different hours.
  bool get hasWorstHour => worstHour != null && worstHour != bestHour;

  /// The average at [hour], or null if nobody reported at that hour.
  HourlyWait? at(int hour) {
    for (final wait in byHour) {
      if (wait.hour == hour) return wait;
    }
    return null;
  }
}

/// `GET /analytics/best-time-to-go`.
class BestTimeReport {
  /// Window in days the averages come from.
  final int days;

  /// An hour needs at least this many reports to be the best or the worst.
  final int minReports;
  final int totalReports;

  /// Every restaurant together.
  final List<HourlyWait> campusByHour;

  final List<BestTimeSpot> spots;

  const BestTimeReport({
    required this.days,
    required this.minReports,
    required this.totalReports,
    required this.campusByHour,
    required this.spots,
  });

  factory BestTimeReport.fromJson(Map<String, dynamic> json) => BestTimeReport(
        days: json['days'] as int,
        minReports: json['minReports'] as int,
        totalReports: json['totalReports'] as int,
        campusByHour: [
          for (final item in json['byHour'] as List<dynamic>) HourlyWait.fromJson(item as Map<String, dynamic>),
        ],
        spots: [
          for (final item in json['spots'] as List<dynamic>) BestTimeSpot.fromJson(item as Map<String, dynamic>),
        ],
      );

  bool get isEmpty => totalReports == 0;

  /// The hour with the shortest average wait on the whole campus, counting only hours with [minReports] or more.
  HourlyWait? get calmestHour {
    HourlyWait? best;
    for (final wait in campusByHour) {
      if (wait.reports < minReports) continue;
      if (best == null ||
          wait.avgMinutes < best.avgMinutes ||
          (wait.avgMinutes == best.avgMinutes && wait.reports > best.reports)) {
        best = wait;
      }
    }
    return best;
  }

  /// The order the student needs to decide: restaurants with a best hour, from the shortest wait at that hour; 
  /// then the ones without enough reports, by name.
  List<BestTimeSpot> get spotsForDecision => [...spots]..sort((a, b) {
      if (a.hasBestHour != b.hasBestHour) return a.hasBestHour ? -1 : 1;
      if (a.hasBestHour) {
        final byWait = a.bestAvgMinutes!.compareTo(b.bestAvgMinutes!);
        if (byWait != 0) return byWait;
      }
      return a.name.compareTo(b.name);
    });
}

String hourLabel(int hour) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h ${hour < 12 ? 'AM' : 'PM'}';
}
