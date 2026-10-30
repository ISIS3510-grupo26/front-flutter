/// What the student saved in Taste Profile and Dietary Preferences.
/// Both screens edit the same object and send it complete to the backend.
class UserPreferences {
  final String? mainCuisine;
  final String? mealStyle;
  final List<String> flavors;
  final List<String> interests;
  final String diet;
  final List<String> avoid;
  final List<String> allergies;
  /// False until the student saves for the first time.
  final bool saved;

  const UserPreferences({
    this.mainCuisine,
    this.mealStyle,
    this.flavors = const [],
    this.interests = const [],
    this.diet = noDiet,
    this.avoid = const [],
    this.allergies = const [],
    this.saved = false,
  });

  static const noDiet = 'No specific diet';

  factory UserPreferences.fromJson(Map<String, dynamic> json) => UserPreferences(
        mainCuisine: json['mainCuisine'] as String?,
        mealStyle: json['mealStyle'] as String?,
        flavors: _strings(json['flavors']),
        interests: _strings(json['interests']),
        diet: json['diet'] as String? ?? noDiet,
        avoid: _strings(json['avoid']),
        allergies: _strings(json['allergies']),
        saved: json['saved'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'mainCuisine': mainCuisine,
        'mealStyle': mealStyle,
        'flavors': flavors,
        'interests': interests,
        'diet': diet,
        'avoid': avoid,
        'allergies': allergies,
      };

  UserPreferences copyWith({
    String? mainCuisine,
    String? mealStyle,
    List<String>? flavors,
    List<String>? interests,
    String? diet,
    List<String>? avoid,
    List<String>? allergies,
  }) =>
      UserPreferences(
        mainCuisine: mainCuisine ?? this.mainCuisine,
        mealStyle: mealStyle ?? this.mealStyle,
        flavors: flavors ?? this.flavors,
        interests: interests ?? this.interests,
        diet: diet ?? this.diet,
        avoid: avoid ?? this.avoid,
        allergies: allergies ?? this.allergies,
        saved: saved,
      );

  static List<String> _strings(Object? value) =>
      [for (final item in value as List<dynamic>? ?? const []) item as String];
}