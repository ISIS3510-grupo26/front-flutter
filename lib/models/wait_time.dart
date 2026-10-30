import 'dart:math';

/// BQ4, the last wait reported by students for one restaurant
class LastWaitTime {
  final String spotId;
  final String name;
  final String emoji;
  /// Null when nobody has reported yet.
  final int? minutes;
  final int? minutesAgo;
  final bool isRecent;

  /// How many reports arrived in that window, more reports, more trust.
  final int recentReports;

  const LastWaitTime({
    required this.spotId,
    required this.name,
    required this.emoji,
    required this.minutes,
    required this.minutesAgo,
    required this.isRecent,
    required this.recentReports,
  });

  factory LastWaitTime.fromJson(Map<String, dynamic> json) => LastWaitTime(
        spotId: json['spotId'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        minutes: json['minutes'] as int?,
        minutesAgo: json['minutesAgo'] as int?,
        isRecent: json['isRecent'] as bool,
        recentReports: json['recentReports'] as int,
      );

  bool get hasReport => minutes != null;

  /// "reported 8 min ago · 3 reports in the last 2 h"
  String get detail {
    if (!hasReport) return 'No reports yet: be the first';
    final ago = minutesAgo ?? 0;
    final when = ago == 0
        ? 'reported just now'
        : ago < 60
            ? 'reported $ago min ago'
            : 'old report (${ago ~/ 60} h ago)';
    if (!isRecent) return when;
    return '$when · $recentReports report${recentReports == 1 ? '' : 's'} in the last 2 h';
  }
}

/// One report the student is sending. The id and the time are fixed when it is created, so if the request 
/// fails and the student taps "Retry", the backend recognizes the same report (no duplicate) and keeps the 
/// real time.
class WaitReport {
  final String reportId;
  final String spotId;
  final int minutes;
  final DateTime reportedAt;

  WaitReport({required this.spotId, required this.minutes, DateTime? reportedAt, String? reportId})
      : reportedAt = (reportedAt ?? DateTime.now()).toUtc(),
        reportId = reportId ?? _newId();

  Map<String, dynamic> toJson() => {
        'reportId': reportId,
        'minutes': minutes,
        'platform': 'flutter',
        'reportedAt': reportedAt.toIso8601String(),
      };

  static final _random = Random.secure();

  static String _newId() =>
      [for (var i = 0; i < 16; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

/// What the BQ4 screen shows, in the order the student needs to decide, recent reports from the shortest wait, 
/// then old reports, then places nobody has reported yet.
List<LastWaitTime> sortForDecision(List<LastWaitTime> waits) {
  int group(LastWaitTime w) => !w.hasReport ? 2 : (w.isRecent ? 0 : 1);
  return [...waits]..sort((a, b) {
      final byGroup = group(a).compareTo(group(b));
      if (byGroup != 0) return byGroup;
      if (group(a) == 0) return a.minutes!.compareTo(b.minutes!);
      if (group(a) == 1) return a.minutesAgo!.compareTo(b.minutesAgo!);
      return a.name.compareTo(b.name);
    });
}
