/// A nearby spot the backend recommends: highly rated and not reviewed yet
/// by the current user.
class NearbyPick {
  final String id;
  final String name;
  final String emoji;
  final double rating;
  final double latitude;
  final double longitude;
  final int distanceMeters;
  final int walkMinutes;

  const NearbyPick({
    required this.id,
    required this.name,
    required this.emoji,
    required this.rating,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.walkMinutes,
  });

  factory NearbyPick.fromJson(Map<String, dynamic> json) {
    return NearbyPick(
      id: json['id'].toString(),
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      rating: (json['rating'] as num).toDouble(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      distanceMeters: (json['distanceMeters'] as num).round(),
      walkMinutes: (json['walkMinutes'] as num).ceil(),
    );
  }
}
