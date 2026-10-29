/// What the student picked in Dietary Preferences.
class DietaryPreferences {
  final String diet;
  final Set<String> avoid;
  final Set<String> allergies;

  const DietaryPreferences({
    required this.diet,
    required this.avoid,
    required this.allergies,
  });

  factory DietaryPreferences.fromJson(Map<String, dynamic> json) {
    return DietaryPreferences(
      diet: json['diet'] as String,
      avoid: _stringSet(json['avoid']),
      allergies: _stringSet(json['allergies']),
    );
  }

  Map<String, dynamic> toJson() => {
        'diet': diet,
        'avoid': avoid.toList()..sort(),
        'allergies': allergies.toList()..sort(),
      };
}

/// What the student picked in Taste Profile.
class TastePreferences {
  final String mainCuisine;
  final String mealStyle;
  final Set<String> flavors;
  final Set<String> interests;

  const TastePreferences({
    required this.mainCuisine,
    required this.mealStyle,
    required this.flavors,
    required this.interests,
  });

  factory TastePreferences.fromJson(Map<String, dynamic> json) {
    return TastePreferences(
      mainCuisine: json['mainCuisine'] as String,
      mealStyle: json['mealStyle'] as String,
      flavors: _stringSet(json['flavors']),
      interests: _stringSet(json['interests']),
    );
  }

  Map<String, dynamic> toJson() => {
        'mainCuisine': mainCuisine,
        'mealStyle': mealStyle,
        'flavors': flavors.toList()..sort(),
        'interests': interests.toList()..sort(),
      };
}

Set<String> _stringSet(Object? value) => {
      for (final item in value as List<dynamic>) item as String,
    };
