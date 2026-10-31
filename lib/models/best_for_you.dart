import 'user_preferences.dart';

/// One restaurant in "Best for you right now" (BQ6), as the backend ranked it.
class BestForYouSpot {
  final String spotId;
  final String name;
  final String emoji;
  final String cuisine;
  final double rating;

  /// The last wait reported by a student (BQ4); null if nobody reported one.
  final int? waitMinutes;

  /// How long ago, in minutes, when the backend answered.
  final int? minutesAgo;

  /// Reported within the last two hours. An older wait doesn't count in the
  /// score, so the card doesn't show it either.
  final bool isRecent;

  /// 0–100 match with the taste profile that was sent; null without one.
  final int? tasteMatch;

  const BestForYouSpot({
    required this.spotId,
    required this.name,
    required this.emoji,
    required this.cuisine,
    required this.rating,
    required this.waitMinutes,
    required this.minutesAgo,
    required this.isRecent,
    required this.tasteMatch,
  });

  factory BestForYouSpot.fromJson(Map<String, dynamic> json) => BestForYouSpot(
        spotId: json['spotId'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        cuisine: json['cuisine'] as String,
        rating: (json['rating'] as num).toDouble(),
        waitMinutes: json['waitMinutes'] as int?,
        minutesAgo: json['minutesAgo'] as int?,
        isRecent: json['isRecent'] as bool,
        tasteMatch: json['tasteMatch'] as int?,
      );
}

/// `GET /recommendations/best-for-you`: restaurants with the shortest wait
/// and the best match with the student's taste, best first.
class BestForYouRanking {
  /// False when no taste profile was sent: then the order is by wait only.
  final bool personalized;
  final List<BestForYouSpot> spots;

  const BestForYouRanking({required this.personalized, required this.spots});

  factory BestForYouRanking.fromJson(Map<String, dynamic> json) => BestForYouRanking(
        personalized: json['personalized'] as bool,
        spots: [
          for (final spot in json['spots'] as List<dynamic>)
            BestForYouSpot.fromJson(spot as Map<String, dynamic>),
        ],
      );
}

/// The parts of the taste profile the BQ6 endpoint scores: cuisine (50
/// points), a vegetarian or vegan diet (30) and budget (20).
///
/// Taste Profile names some things differently from the backend, so they are
/// translated here: "Fast food" is what the backend calls "Artisan Burgers",
/// and "Good value" is the "Budget-friendly" budget. Cuisines with the same
/// name in both, like "Mexican", go as they are.
class BestForYouProfile {
  static const _backendCuisines = {
    'Fast food': 'Artisan Burgers',
    'Bakery & desserts': 'Specialty Coffee',
    'Asian': 'Asian Wok',
  };

  final String? cuisine;
  final String? diet;
  final bool budgetFriendly;

  const BestForYouProfile({this.cuisine, this.diet, this.budgetFriendly = false});

  /// No profile: the backend ranks by wait only.
  static const none = BestForYouProfile();

  factory BestForYouProfile.from(UserPreferences? preferences) {
    if (preferences == null) return none;
    final diet = preferences.diet;
    return BestForYouProfile(
      cuisine: preferences.mainCuisine,
      diet: diet == UserPreferences.noDiet ? null : diet,
      budgetFriendly: preferences.interests.contains('Good value'),
    );
  }

  Map<String, dynamic> get queryParameters => {
        if (cuisine case final c?) 'cuisines': _backendCuisines[c] ?? c,
        'dietary': ?diet,
        if (budgetFriendly) 'budget': 'Budget-friendly',
      };

  /// Identifies the profile in the cache: the same profile, the same ranking.
  String get key => '${cuisine ?? ''}|${diet ?? ''}|$budgetFriendly';

  @override
  bool operator ==(Object other) => other is BestForYouProfile && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
