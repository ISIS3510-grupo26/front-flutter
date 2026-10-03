import 'package:flutter/material.dart';

/// `GET /spots/{id}` devuelve la página del restaurante.
class SpotDetail {
  final String id;
  final String emoji;
  final Color emojiBackground;
  final String name;
  final String subtitle;
  final double rating;
  final int totalReviews;
  final String price;
  final String distance;
  final int walkMinutes;
  final bool isVegetarian;
  final int affinityPercent;
  final String note;
  final String? uniCardPerk;
  final List<SpotReview> reviews;

  const SpotDetail({
    required this.id,
    required this.emoji,
    required this.emojiBackground,
    required this.name,
    required this.subtitle,
    required this.rating,
    required this.totalReviews,
    required this.price,
    required this.distance,
    required this.walkMinutes,
    required this.isVegetarian,
    required this.affinityPercent,
    required this.note,
    required this.uniCardPerk,
    required this.reviews,
  });

  factory SpotDetail.fromJson(Map<String, dynamic> json) => SpotDetail(
        id: json['id'] as String,
        emoji: json['emoji'] as String,
        emojiBackground: _hexColor(json['emojiBackground'] as String),
        name: json['name'] as String,
        subtitle: json['subtitle'] as String,
        rating: (json['rating'] as num).toDouble(),
        totalReviews: json['totalReviews'] as int,
        price: json['price'] as String,
        distance: json['distance'] as String,
        walkMinutes: json['walkMinutes'] as int,
        isVegetarian: json['isVegetarian'] as bool,
        affinityPercent: json['affinityPercent'] as int,
        note: json['note'] as String,
        uniCardPerk: json['uniCardPerk'] as String?,
        reviews: [
          for (final r in json['reviews'] as List<dynamic>)
            SpotReview.fromJson(r as Map<String, dynamic>),
        ],
      );

  /// '#FFFBEB' -> Color(0xFFFFFBEB)
  static Color _hexColor(String hex) =>
      Color(int.parse(hex.replaceFirst('#', ''), radix: 16) | 0xFF000000);
}

class SpotReview {
  final String authorName;
  final String initials;
  final int stars;
  final String text;
  final String dinedAgo;

  const SpotReview({
    required this.authorName,
    required this.initials,
    required this.stars,
    required this.text,
    required this.dinedAgo,
  });

  factory SpotReview.fromJson(Map<String, dynamic> json) => SpotReview(
        authorName: json['authorName'] as String,
        initials: json['initials'] as String,
        stars: json['stars'] as int,
        text: json['text'] as String,
        dinedAgo: json['dinedAgo'] as String,
      );
}

/// `POST /spots/{id}/reviews` devuelve la nueva media del restaurante.
class ReviewResult {
  final double rating;
  final int totalReviews;

  const ReviewResult({required this.rating, required this.totalReviews});

  factory ReviewResult.fromJson(Map<String, dynamic> json) => ReviewResult(
        rating: (json['rating'] as num).toDouble(),
        totalReviews: json['totalReviews'] as int,
      );
}
