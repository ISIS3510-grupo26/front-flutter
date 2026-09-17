import 'package:flutter/material.dart';

enum SpotCategory { foodTrucks, studySpots }

extension SpotCategoryLabel on SpotCategory {
  String get label => switch (this) {
        SpotCategory.foodTrucks => 'Food Trucks',
        SpotCategory.studySpots => 'Study Spots',
      };
}

enum FeedFilterType { inARush, budget, shortWalk, vegetarian, highProtein }

extension FeedFilterLabel on FeedFilterType {
  String get label => switch (this) {
        FeedFilterType.inARush => '⚡ In a rush (<10m)',
        FeedFilterType.budget => '\$ Budget',
        FeedFilterType.shortWalk => '≤ 5 min walk',
        FeedFilterType.vegetarian => 'Vegetarian',
        FeedFilterType.highProtein => 'High Protein',
      };
}

/// A single campus food spot. This is the one model behind every card in the
/// app: the For You feed and Saved Places both render the same [Spot]s,
/// just filtered differently. `isSaved` is the source of truth for whether a
/// spot shows up in Saved Places, and is toggled by the heart button on the
/// card regardless of which screen it's tapped from.
class Spot {
  final String id;
  final String emoji;
  final Color emojiBackground;
  final Color emojiBorder;
  final String name;
  final String subtitle;
  final double rating;
  final String price;
  final String distance;
  final int walkMinutes;
  final bool isBudget;
  final bool isVegetarian;
  final bool isHighProtein;
  final int affinityPercent;
  final SpotCategory category;
  final String noteLabel;
  final String note;
  final bool isSaved;

  const Spot({
    required this.id,
    required this.emoji,
    required this.emojiBackground,
    required this.emojiBorder,
    required this.name,
    required this.subtitle,
    required this.rating,
    required this.price,
    required this.distance,
    required this.walkMinutes,
    required this.isBudget,
    required this.isVegetarian,
    required this.isHighProtein,
    required this.affinityPercent,
    required this.category,
    required this.noteLabel,
    required this.note,
    this.isSaved = false,
  });

  bool matchesFilter(FeedFilterType filter) => switch (filter) {
        FeedFilterType.inARush => walkMinutes < 10,
        FeedFilterType.budget => isBudget,
        FeedFilterType.shortWalk => walkMinutes <= 5,
        FeedFilterType.vegetarian => isVegetarian,
        FeedFilterType.highProtein => isHighProtein,
      };

  Spot copyWith({bool? isSaved}) {
    return Spot(
      id: id,
      emoji: emoji,
      emojiBackground: emojiBackground,
      emojiBorder: emojiBorder,
      name: name,
      subtitle: subtitle,
      rating: rating,
      price: price,
      distance: distance,
      walkMinutes: walkMinutes,
      isBudget: isBudget,
      isVegetarian: isVegetarian,
      isHighProtein: isHighProtein,
      affinityPercent: affinityPercent,
      category: category,
      noteLabel: noteLabel,
      note: note,
      isSaved: isSaved ?? this.isSaved,
    );
  }
}
