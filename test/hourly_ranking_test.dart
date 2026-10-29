import 'package:campus_bites/models/hourly_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

final _report = {
  'question': 'Which restaurants receive the highest number of page views and searches during each hour?',
  'days': 7,
  'tzOffsetMinutes': -300,
  'hours': [
    {
      'hour': 13,
      'totalPageViews': 12,
      'totalSearches': 3,
      'spots': [
        {
          'rank': 1,
          'spotId': 'conda-de-bons',
          'name': 'Conda de Bons',
          'emoji': '🍔',
          'pageViews': 10,
          'searches': 2,
          'total': 12,
        },
        {
          'rank': 2,
          'spotId': 'nitro-coffee',
          'name': 'Nitro Coffee & Brew',
          'emoji': '☕',
          'pageViews': 2,
          'searches': 1,
          'total': 3,
        },
      ],
    },
  ],
};

void main() {
  test('parses every hour and its spots in order', () {
    final report = PopularityReport.fromJson(_report);

    expect(report.days, 7);
    final ranking = report.hours.single;
    expect(ranking.hour, 13);
    expect((ranking.totalPageViews, ranking.totalSearches), (12, 3));
    expect(ranking.spots.map((s) => s.spotId), [
      'conda-de-bons',
      'nitro-coffee',
    ]);

    final first = ranking.spots.first;
    expect(first.rank, 1);
    expect(first.name, 'Conda de Bons');
    expect(first.emoji, '🍔');
    expect((first.pageViews, first.searches, first.total), (10, 2, 12));
  });

  test('an hour missing from the report is an empty ranking', () {
    final ranking = PopularityReport.fromJson(_report).rankingFor(9);

    expect(ranking.hour, 9);
    expect(ranking.isEmpty, isTrue);
    expect((ranking.totalPageViews, ranking.totalSearches), (0, 0));
  });

  test('an hour the backend returns without spots is empty too', () {
    final ranking = HourlyRanking.fromJson({
      'hour': 15,
      'totalPageViews': 0,
      'totalSearches': 0,
      'spots': <Object>[],
    });

    expect(ranking.isEmpty, isTrue);
  });

  test('the label is the hour as a range, wrapping at midnight', () {
    expect(const HourlyRanking.empty(13).label, '13:00–14:00');
    expect(const HourlyRanking.empty(9).label, '09:00–10:00');
    expect(const HourlyRanking.empty(23).label, '23:00–00:00');
  });

  test('toJson() reads back the same ranking with fromJson()', () {
    final ranking = PopularityReport.fromJson(_report).hours.single;

    final copy = HourlyRanking.fromJson(ranking.toJson());

    expect(copy.toJson(), ranking.toJson());
    expect(copy.spots.last.name, 'Nitro Coffee & Brew');
  });
}
