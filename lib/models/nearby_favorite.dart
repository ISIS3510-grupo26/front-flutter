/// A saved spot the backend reports as open now and within walking range.
class NearbyFavorite {
  final String id;
  final int walkMinutes;

  const NearbyFavorite({required this.id, required this.walkMinutes});

  factory NearbyFavorite.fromJson(Map<String, dynamic> json) {
    return NearbyFavorite(
      id: json['id'].toString(),
      walkMinutes: (json['walkMinutes'] as num).ceil(),
    );
  }
}
